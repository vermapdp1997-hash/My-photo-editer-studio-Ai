import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../data/models/edit_state.dart';
import '../../features/filters/filter_catalog.dart';

class PipelineRequest {
  final String sourcePath;
  final Map<String, dynamic> editStateJson;
  final int maxDimension; // 0 means full original resolution

  const PipelineRequest({
    required this.sourcePath,
    required this.editStateJson,
    this.maxDimension = 1080,
  });
}

class ImagePipelineService {
  ImagePipelineService._();
  static final ImagePipelineService instance = ImagePipelineService._();

  Future<Uint8List> renderPreviewPng(
    String sourcePath,
    EditState state, {
    int maxDimension = 1080,
  }) async {
    final req = PipelineRequest(
      sourcePath: sourcePath,
      editStateJson: state.toJson(),
      maxDimension: maxDimension,
    );
    return Isolate.run(() => _executeRender(req, outputPngForPreview: true));
  }

  Future<img.Image> renderForExport(
    String sourcePath,
    EditState state, {
    int maxDimension = 0,
  }) async {
    final req = PipelineRequest(
      sourcePath: sourcePath,
      editStateJson: state.toJson(),
      maxDimension: maxDimension,
    );
    final pngBytes = await Isolate.run(
      () => _executeRender(req, outputPngForPreview: true),
    );
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) {
      throw StateError('Failed to decode rendered export image.');
    }
    return decoded;
  }

  static Future<Uint8List> _executeRender(
    PipelineRequest req, {
    required bool outputPngForPreview,
  }) async {
    final state = EditState.fromJson(req.editStateJson);
    final activeSourcePath = state.aiProcessedImagePath ?? req.sourcePath;
    final bytes = await File(activeSourcePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      throw StateError('Unable to decode image at $activeSourcePath');
    }

    image = img.bakeOrientation(image);

    // Resize early for preview speed while preserving full-res for export
    if (req.maxDimension > 0) {
      final maxSide = math.max(image.width, image.height);
      if (maxSide > req.maxDimension) {
        final scale = req.maxDimension / maxSide;
        image = img.copyResize(
          image,
          width: math.max(1, (image.width * scale).round()),
          height: math.max(1, (image.height * scale).round()),
          interpolation: img.Interpolation.linear,
        );
      }
    }

    // Ensure 4-channel RGBA so transparency/mask/eraser operations always work
    image = image.convert(numChannels: 4);

    // 1. Portrait Blur or Background Replacement using AI Segmentation Mask
    if (state.aiMaskPath != null &&
        (state.portraitBlurIntensity > 0 ||
            state.bgReplacementType != BackgroundReplacementType.none)) {
      final maskFile = File(state.aiMaskPath!);
      if (await maskFile.exists()) {
        final maskBytes = await maskFile.readAsBytes();
        final maskImg = img.decodeImage(maskBytes);
        if (maskImg != null) {
          image = await _applySegmentationComposite(image, maskImg, state);
        }
      }
    }

    // 2. Retouch Brush Strokes (Healing, Spot Removal, Eraser, Selective Blur)
    if (state.retouchStrokes.isNotEmpty) {
      image = _applyRetouchStrokes(image, state.retouchStrokes);
    }

    // 3. Crop & Transform
    if (state.cropLeft > 0 ||
        state.cropTop > 0 ||
        state.cropRight < 1 ||
        state.cropBottom < 1) {
      final x = (state.cropLeft.clamp(0.0, 0.95) * image.width).round();
      final y = (state.cropTop.clamp(0.0, 0.95) * image.height).round();
      final w = math.max(
        8,
        ((state.cropRight.clamp(0.05, 1.0) - state.cropLeft.clamp(0.0, 0.95)) *
                image.width)
            .round(),
      );
      final h = math.max(
        8,
        ((state.cropBottom.clamp(0.05, 1.0) - state.cropTop.clamp(0.0, 0.95)) *
                image.height)
            .round(),
      );
      image = img.copyCrop(
        image,
        x: x.clamp(0, image.width - 1),
        y: y.clamp(0, image.height - 1),
        width: math.min(w, image.width - x),
        height: math.min(h, image.height - y),
      );
    }

    if (state.rotationQuarterTurns % 4 != 0) {
      image = img.copyRotate(image, angle: (state.rotationQuarterTurns % 4) * 90);
    }
    if (state.flipHorizontal) {
      image = img.flip(image, direction: img.FlipDirection.horizontal);
    }
    if (state.flipVertical) {
      image = img.flip(image, direction: img.FlipDirection.vertical);
    }
    if (state.straightenDegrees.abs() > 0.1) {
      image = _rotateAndCropClean(image, state.straightenDegrees);
    }
    if (state.perspectiveX.abs() > 0.005 || state.perspectiveY.abs() > 0.005) {
      image = _applyPerspectiveCorrection(
        image,
        state.perspectiveX,
        state.perspectiveY,
      );
    }
    // 4. Pixel-level Basic + Advanced + Filter Color Pipeline
    final activeFilter = FilterCatalog.byId(state.filterId);
    if (state.hasAdjustments || activeFilter != null) {
      _applyColorAndFilterPipeline(image, state, activeFilter);
    }

    // 5. Spatial Filters (Noise Reduction, Clarity/Sharpness, Blur)
    if (state.noiseReduction > 0.02) {
      final nr = img.gaussianBlur(
        img.Image.from(image),
        radius: math.max(1, (state.noiseReduction * 2).round()),
      );
      image = _blendImages(image, nr, state.noiseReduction * 0.55);
    }

    if (state.clarity > 0.02 || state.sharpness > 0.02) {
      final strength = (state.clarity * 0.8 + state.sharpness * 1.1).clamp(0.0, 2.0);
      image = _applyUnsharpMask(image, strength);
    }

    if (state.blur > 0.02) {
      image = img.gaussianBlur(
        image,
        radius: math.max(1, (state.blur * 14).round()),
      );
    }

    // 6. Double Exposure Blend
    if (state.doubleExposurePath != null) {
      final deFile = File(state.doubleExposurePath!);
      if (await deFile.exists()) {
        final deRaw = img.decodeImage(await deFile.readAsBytes());
        if (deRaw != null) {
          final resizedDe = img.copyResize(
            deRaw.convert(numChannels: 4),
            width: image.width,
            height: image.height,
          );
          image = _blendScreenDoubleExposure(
            image,
            resizedDe,
            state.doubleExposureOpacity,
          );
        }
      }
    }

    // 7. Creative Overlays (Bokeh, Sunflare, Dust, Prism)
    if (state.overlayStyle != 'none') {
      _applyCreativeOverlay(image, state.overlayStyle);
    }

    // 8. Vignette & Film Grain
    final totalVig = math.max(
      state.vignette,
      activeFilter != null ? activeFilter.vignette * state.filterIntensity : 0.0,
    );
    if (totalVig > 0.01 || state.grain > 0.01) {
      _applyVignetteAndGrain(image, totalVig, state.grain);
    }

    // 9. Borders & Frames
    if (state.borderWidth > 0 || state.frameStyle != 'none') {
      image = _applyFrameAndBorder(image, state);
    }

    return Uint8List.fromList(img.encodePng(image, level: 2));
  }

  static Future<img.Image> _applySegmentationComposite(
    img.Image fg,
    img.Image rawMask,
    EditState state,
  ) async {
    final mask = img.copyResize(
      rawMask.convert(numChannels: 4),
      width: fg.width,
      height: fg.height,
      interpolation: img.Interpolation.linear,
    );

    img.Image? bgLayer;
    if (state.bgReplacementType == BackgroundReplacementType.image &&
        state.bgReplacementImagePath != null) {
      final f = File(state.bgReplacementImagePath!);
      if (await f.exists()) {
        final decoded = img.decodeImage(await f.readAsBytes());
        if (decoded != null) {
          bgLayer = img.copyResize(
            decoded.convert(numChannels: 4),
            width: fg.width,
            height: fg.height,
          );
        }
      }
    } else if (state.portraitBlurIntensity > 0 &&
        state.bgReplacementType == BackgroundReplacementType.none) {
      final blurR = math.max(2, (state.portraitBlurIntensity * 18).round());
      bgLayer = img.gaussianBlur(img.Image.from(fg), radius: blurR);
    }

    final feather = state.aiEdgeFeather.clamp(0.0, 0.9);
    final lowT = 0.45 - feather * 0.35;
    final highT = 0.55 + feather * 0.35;
    final span = math.max(0.01, highT - lowT);

    final cVal = state.bgReplacementColor;
    final bgR = (cVal >> 16) & 0xFF;
    final bgG = (cVal >> 8) & 0xFF;
    final bgB = cVal & 0xFF;

    final out = img.Image(width: fg.width, height: fg.height, numChannels: 4);
    for (int y = 0; y < fg.height; y++) {
      for (int x = 0; x < fg.width; x++) {
        final fp = fg.getPixel(x, y);
        final mp = mask.getPixel(x, y);
        final rawM = mp.r / 255.0;
        final alpha = ((rawM - lowT) / span).clamp(0.0, 1.0);

        if (state.bgReplacementType == BackgroundReplacementType.transparent) {
          out.setPixelRgba(
            x,
            y,
            fp.r.round(),
            fp.g.round(),
            fp.b.round(),
            (fp.a * alpha).round(),
          );
        } else {
          int br = bgR, bg = bgG, bb = bgB;
          if (bgLayer != null) {
            final bp = bgLayer.getPixel(x, y);
            br = bp.r.round();
            bg = bp.g.round();
            bb = bp.b.round();
          } else if (state.bgReplacementType == BackgroundReplacementType.gradient) {
            final gy = y / math.max(1, fg.height - 1);
            br = (bgR * (1 - gy) + 34 * gy).round();
            bg = (bgG * (1 - gy) + 211 * gy).round();
            bb = (bgB * (1 - gy) + 238 * gy).round();
          }
          final r = (fp.r * alpha + br * (1 - alpha)).round();
          final g = (fp.g * alpha + bg * (1 - alpha)).round();
          final b = (fp.b * alpha + bb * (1 - alpha)).round();
          out.setPixelRgba(x, y, r, g, b, 255);
        }
      }
    }
    return out;
  }

  static img.Image _applyRetouchStrokes(
    img.Image src,
    List<RetouchStroke> strokes,
  ) {
    final work = img.Image.from(src);
    final blurred = img.gaussianBlur(img.Image.from(src), radius: 6);

    for (final s in strokes) {
      final radius = math.max(3, (s.brushSize * math.min(work.width, work.height)).round());
      final r2 = radius * radius;
      for (final pt in s.normalizedPoints) {
        final cx = (pt.dx * work.width).round();
        final cy = (pt.dy * work.height).round();
        for (int dy = -radius; dy <= radius; dy++) {
          final py = cy + dy;
          if (py < 0 || py >= work.height) continue;
          for (int dx = -radius; dx <= radius; dx++) {
            final px = cx + dx;
            if (px < 0 || px >= work.width) continue;
            final dist2 = dx * dx + dy * dy;
            if (dist2 > r2) continue;
            final falloff = (1.0 - math.sqrt(dist2) / radius) * s.intensity;
            final p = work.getPixel(px, py);

            if (s.tool == RetouchToolType.manualEraser) {
              work.setPixelRgba(
                px,
                py,
                p.r.round(),
                p.g.round(),
                p.b.round(),
                (p.a * (1.0 - falloff)).round().clamp(0, 255),
              );
            } else if (s.tool == RetouchToolType.selectiveBlur ||
                s.tool == RetouchToolType.spotRemoval) {
              final bp = blurred.getPixel(px, py);
              work.setPixelRgba(
                px,
                py,
                (p.r * (1 - falloff) + bp.r * falloff).round(),
                (p.g * (1 - falloff) + bp.g * falloff).round(),
                (p.b * (1 - falloff) + bp.b * falloff).round(),
                p.a.round(),
              );
            } else if (s.tool == RetouchToolType.healing) {
              // Sample clean neighboring patch offset outside brush radius
              final sx = (px - radius - 2).clamp(0, work.width - 1);
              final sy = (py - radius - 2).clamp(0, work.height - 1);
              final sp = src.getPixel(sx, sy);
              final bp = blurred.getPixel(px, py);
              final hr = (sp.r * 0.65 + bp.r * 0.35);
              final hg = (sp.g * 0.65 + bp.g * 0.35);
              final hb = (sp.b * 0.65 + bp.b * 0.35);
              work.setPixelRgba(
                px,
                py,
                (p.r * (1 - falloff) + hr * falloff).round(),
                (p.g * (1 - falloff) + hg * falloff).round(),
                (p.b * (1 - falloff) + hb * falloff).round(),
                p.a.round(),
              );
            }
          }
        }
      }
    }
    return work;
  }

  static img.Image _rotateAndCropClean(img.Image src, double degrees) {
    final rotated = img.copyRotate(src, angle: degrees, interpolation: img.Interpolation.linear);
    final rad = degrees.abs() * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final trimScale = (cosA - sinA * 0.5).clamp(0.72, 1.0);
    final nw = math.max(16, (src.width * trimScale).round());
    final nh = math.max(16, (src.height * trimScale).round());
    final ox = ((rotated.width - nw) / 2).round().clamp(0, rotated.width - 1);
    final oy = ((rotated.height - nh) / 2).round().clamp(0, rotated.height - 1);
    return img.copyCrop(
      rotated,
      x: ox,
      y: oy,
      width: math.min(nw, rotated.width - ox),
      height: math.min(nh, rotated.height - oy),
    );
  }

  static img.Image _applyPerspectiveCorrection(
    img.Image src,
    double tiltX,
    double tiltY,
  ) {
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h, numChannels: 4);
    for (int y = 0; y < h; y++) {
      final ny = (y / h) - 0.5;
      final rowScale = (1.0 + tiltY * ny).clamp(0.65, 1.45);
      for (int x = 0; x < w; x++) {
        final nx = (x / w) - 0.5;
        final colScale = (1.0 + tiltX * nx).clamp(0.65, 1.45);
        final sx = ((nx / rowScale) + 0.5) * w;
        final sy = ((ny / colScale) + 0.5) * h;
        final ix = sx.round().clamp(0, w - 1);
        final iy = sy.round().clamp(0, h - 1);
        final p = src.getPixel(ix, iy);
        out.setPixelRgba(x, y, p.r.round(), p.g.round(), p.b.round(), p.a.round());
      }
    }
    return out;
  }

  static void _applyColorAndFilterPipeline(
    img.Image image,
    EditState s,
    FilterPreset? f,
  ) {
    final fi = f != null ? s.filterIntensity.clamp(0.0, 1.0) : 0.0;
    final expMul = math.pow(2.0, s.exposure + (f?.exposure ?? 0) * fi);
    final brightAdd = s.brightness * 90.0;
    final contrastFactor = (1.0 + s.contrast + (f?.contrast ?? 0) * fi).clamp(0.2, 2.5);
    final satFactor = (1.0 + s.saturation + (f?.saturation ?? 0) * fi).clamp(0.0, 2.5);
    final tempShift = (s.temperature + (f?.warmth ?? 0) * fi) * 42.0;
    final tintShift = (s.tint + (f?.tint ?? 0) * fi) * 32.0;
    final fadeAmt = (s.fade + (f?.fade ?? 0) * fi).clamp(0.0, 0.7);
    final rGain = (1.0 + s.redGain) * (1.0 + ((f?.redScale ?? 1.0) - 1.0) * fi);
    final gGain = (1.0 + s.greenGain) * (1.0 + ((f?.greenScale ?? 1.0) - 1.0) * fi);
    final bGain = (1.0 + s.blueGain) * (1.0 + ((f?.blueScale ?? 1.0) - 1.0) * fi);
    final sepiaAmt = (f?.sepia ?? 0) * fi;
    final isMono = (f?.monochrome ?? false) && fi > 0.05;

    for (final p in image) {
      double r = p.r.toDouble();
      double g = p.g.toDouble();
      double b = p.b.toDouble();

      // Exposure & RGB gains
      r = r * expMul * rGain + brightAdd;
      g = g * expMul * gGain + brightAdd;
      b = b * expMul * bGain + brightAdd;

      // Temperature, Tint & Color Balance
      r += tempShift + s.colorBalanceWarmth * 24.0;
      g += tintShift + s.colorGradingTint * 16.0;
      b -= tempShift + s.colorBalanceWarmth * 20.0;

      // Highlights, Shadows, Whites, Blacks & Tone Curve
      final lum0 = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
      final shadowW = (1.0 - lum0).clamp(0.0, 1.0);
      final highW = lum0.clamp(0.0, 1.0);
      final midW = (1.0 - (lum0 - 0.5).abs() * 2.0).clamp(0.0, 1.0);

      final toneOffset =
          (s.shadows * 55.0 + s.curveShadows * 70.0) * shadowW * shadowW +
              (s.highlights * 55.0 + s.curveHighlights * 70.0) * highW * highW +
              (s.curveMidtones * 65.0) * midW +
              s.whites * 40.0 * highW +
              s.blacks * 40.0 * shadowW;
      r += toneOffset;
      g += toneOffset;
      b += toneOffset;

      // Contrast
      r = (r - 128.0) * contrastFactor + 128.0;
      g = (g - 128.0) * contrastFactor + 128.0;
      b = (b - 128.0) * contrastFactor + 128.0;

      // HSL + Vibrance + Selective Warm Shift
      if (s.hslHue != 0 ||
          s.hslSaturation != 0 ||
          s.hslLightness != 0 ||
          s.vibrance != 0 ||
          s.selectiveWarmShift != 0) {
        final hsl = _rgbToHsl(
          r.clamp(0, 255) / 255.0,
          g.clamp(0, 255) / 255.0,
          b.clamp(0, 255) / 255.0,
        );
        var h = (hsl[0] + s.hslHue / 360.0) % 1.0;
        if (h < 0) h += 1.0;
        final vibBoost = s.vibrance * (1.0 - hsl[1]) * 0.6;
        final sat = (hsl[1] * (1.0 + s.hslSaturation) + vibBoost).clamp(0.0, 1.0);
        final light = (hsl[2] + s.hslLightness * 0.35).clamp(0.0, 1.0);
        final rgb = _hslToRgb(h, sat, light);
        r = rgb[0] * 255.0;
        g = rgb[1] * 255.0;
        b = rgb[2] * 255.0;

        if (s.selectiveWarmShift != 0 && (r > b)) {
          r += s.selectiveWarmShift * 26.0;
        }
      }

      // Saturation
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      r = lum + (r - lum) * satFactor;
      g = lum + (g - lum) * satFactor;
      b = lum + (b - lum) * satFactor;

      // Monochrome filter blend
      if (isMono) {
        final gray = (0.299 * r + 0.587 * g + 0.114 * b);
        r = r * (1 - fi) + gray * fi;
        g = g * (1 - fi) + gray * fi;
        b = b * (1 - fi) + gray * fi;
      }

      // Sepia vintage tone
      if (sepiaAmt > 0.01) {
        final sr = 0.393 * r + 0.769 * g + 0.189 * b;
        final sg = 0.349 * r + 0.686 * g + 0.168 * b;
        final sb = 0.272 * r + 0.534 * g + 0.131 * b;
        r = r * (1 - sepiaAmt) + sr * sepiaAmt;
        g = g * (1 - sepiaAmt) + sg * sepiaAmt;
        b = b * (1 - sepiaAmt) + sb * sepiaAmt;
      }

      // Matte Fade (lift blacks)
      if (fadeAmt > 0.01) {
        final lift = fadeAmt * 42.0;
        r = r * (1 - fadeAmt * 0.22) + lift;
        g = g * (1 - fadeAmt * 0.22) + lift;
        b = b * (1 - fadeAmt * 0.22) + lift;
      }

      p
        ..r = r.clamp(0, 255).round()
        ..g = g.clamp(0, 255).round()
        ..b = b.clamp(0, 255).round();
    }
  }

  static img.Image _applyUnsharpMask(img.Image src, double strength) {
    final blurred = img.gaussianBlur(img.Image.from(src), radius: 2);
    final out = img.Image.from(src);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final op = src.getPixel(x, y);
        final bp = blurred.getPixel(x, y);
        final r = (op.r + (op.r - bp.r) * strength).clamp(0, 255).round();
        final g = (op.g + (op.g - bp.g) * strength).clamp(0, 255).round();
        final b = (op.b + (op.b - bp.b) * strength).clamp(0, 255).round();
        out.setPixelRgba(x, y, r, g, b, op.a.round());
      }
    }
    return out;
  }

  static img.Image _blendImages(img.Image base, img.Image top, double alpha) {
    final out = img.Image.from(base);
    for (int y = 0; y < base.height; y++) {
      for (int x = 0; x < base.width; x++) {
        final bp = base.getPixel(x, y);
        final tp = top.getPixel(x, y);
        out.setPixelRgba(
          x,
          y,
          (bp.r * (1 - alpha) + tp.r * alpha).round(),
          (bp.g * (1 - alpha) + tp.g * alpha).round(),
          (bp.b * (1 - alpha) + tp.b * alpha).round(),
          bp.a.round(),
        );
      }
    }
    return out;
  }

  static img.Image _blendScreenDoubleExposure(
    img.Image base,
    img.Image top,
    double opacity,
  ) {
    final out = img.Image.from(base);
    for (int y = 0; y < base.height; y++) {
      for (int x = 0; x < base.width; x++) {
        final a = base.getPixel(x, y);
        final b = top.getPixel(x, y);
        final sr = 255.0 - ((255.0 - a.r) * (255.0 - b.r)) / 255.0;
        final sg = 255.0 - ((255.0 - a.g) * (255.0 - b.g)) / 255.0;
        final sb = 255.0 - ((255.0 - a.b) * (255.0 - b.b)) / 255.0;
        out.setPixelRgba(
          x,
          y,
          (a.r * (1 - opacity) + sr * opacity).round().clamp(0, 255),
          (a.g * (1 - opacity) + sg * opacity).round().clamp(0, 255),
          (a.b * (1 - opacity) + sb * opacity).round().clamp(0, 255),
          a.a.round(),
        );
      }
    }
    return out;
  }

  static void _applyCreativeOverlay(img.Image image, String style) {
    final w = image.width;
    final h = image.height;
    for (int y = 0; y < h; y++) {
      final ny = y / h;
      for (int x = 0; x < w; x++) {
        final nx = x / w;
        final p = image.getPixel(x, y);
        double addR = 0, addG = 0, addB = 0;
        if (style == 'sunflare') {
          final d = math.sqrt((nx - 0.15) * (nx - 0.15) + (ny - 0.15) * (ny - 0.15));
          final glow = (1.0 - d * 1.4).clamp(0.0, 1.0);
          addR = glow * 95;
          addG = glow * 62;
          addB = glow * 20;
        } else if (style == 'prism') {
          addR = math.max(0, math.sin(nx * 9 + ny * 4)) * 28;
          addG = math.max(0, math.sin(nx * 9 + ny * 4 + 2.1)) * 24;
          addB = math.max(0, math.sin(nx * 9 + ny * 4 + 4.2)) * 34;
        } else if (style == 'bokeh') {
          final spot = (math.sin(nx * 14) * math.cos(ny * 14)).clamp(0.0, 1.0);
          if (spot > 0.78) {
            final b = (spot - 0.78) * 140;
            addR = b;
            addG = b * 0.9;
            addB = b * 0.75;
          }
        } else if (style == 'dust') {
          final hash = ((x * 73856093) ^ (y * 19349663)) & 0x3FF;
          if (hash == 7) {
            addR = 70;
            addG = 66;
            addB = 58;
          }
        }
        if (addR > 0 || addG > 0 || addB > 0) {
          image.setPixelRgba(
            x,
            y,
            (p.r + addR).clamp(0, 255).round(),
            (p.g + addG).clamp(0, 255).round(),
            (p.b + addB).clamp(0, 255).round(),
            p.a.round(),
          );
        }
      }
    }
  }

  static void _applyVignetteAndGrain(
    img.Image image,
    double vignette,
    double grain,
  ) {
    final w = image.width;
    final h = image.height;
    final cx = w / 2.0;
    final cy = h / 2.0;
    final maxD = math.sqrt(cx * cx + cy * cy);
    final rng = math.Random(42);

    for (int y = 0; y < h; y++) {
      final dy = y - cy;
      for (int x = 0; x < w; x++) {
        final dx = x - cx;
        final p = image.getPixel(x, y);
        double r = p.r.toDouble();
        double g = p.g.toDouble();
        double b = p.b.toDouble();

        if (vignette > 0.01) {
          final dist = math.sqrt(dx * dx + dy * dy) / maxD;
          final falloff = (1.0 - math.pow(dist, 2.2) * vignette * 0.85).clamp(0.15, 1.0);
          r *= falloff;
          g *= falloff;
          b *= falloff;
        }
        if (grain > 0.01) {
          final n = (rng.nextDouble() - 0.5) * grain * 55.0;
          r += n;
          g += n;
          b += n;
        }
        image.setPixelRgba(
          x,
          y,
          r.clamp(0, 255).round(),
          g.clamp(0, 255).round(),
          b.clamp(0, 255).round(),
          p.a.round(),
        );
      }
    }
  }

  static img.Image _applyFrameAndBorder(img.Image src, EditState state) {
    final pad = math.max(
      (state.borderWidth * math.min(src.width, src.height) * 0.08).round(),
      state.frameStyle == 'none' ? 0 : (math.min(src.width, src.height) * 0.04).round(),
    );
    if (pad <= 0) return src;
    final bottomExtra = state.frameStyle == 'polaroid' ? pad * 3 : pad;

    int c = state.borderColorValue;
    if (state.frameStyle == 'polaroid') c = 0xFFF8FAFC;
    if (state.frameStyle == 'film') c = 0xFF0B0E14;
    if (state.frameStyle == 'neon') c = 0xFF22D3EE;

    final out = img.Image(
      width: src.width + pad * 2,
      height: src.height + pad + bottomExtra,
      numChannels: 4,
    );
    final cr = (c >> 16) & 0xFF;
    final cg = (c >> 8) & 0xFF;
    final cb = c & 0xFF;
    img.fill(out, color: img.ColorRgba8(cr, cg, cb, 255));
    img.compositeImage(out, src, dstX: pad, dstY: pad);
    return out;
  }

  static List<double> _rgbToHsl(double r, double g, double b) {
    final maxV = math.max(r, math.max(g, b));
    final minV = math.min(r, math.min(g, b));
    final l = (maxV + minV) / 2.0;
    if (maxV == minV) return [0, 0, l];
    final d = maxV - minV;
    final s = l > 0.5 ? d / (2.0 - maxV - minV) : d / (maxV + minV);
    double h;
    if (maxV == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (maxV == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    return [h / 6.0, s, l];
  }

  static List<double> _hslToRgb(double h, double s, double l) {
    if (s == 0) return [l, l, l];
    double hue2rgb(double p, double q, double t) {
      var tt = t;
      if (tt < 0) tt += 1;
      if (tt > 1) tt -= 1;
      if (tt < 1 / 6) return p + (q - p) * 6 * tt;
      if (tt < 1 / 2) return q;
      if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
      return p;
    }

    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    return [
      hue2rgb(p, q, h + 1 / 3),
      hue2rgb(p, q, h),
      hue2rgb(p, q, h - 1 / 3),
    ];
  }
}
