import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/performance/performance_profile.dart';
import '../../data/models/edit_state.dart';

class AiModelUnavailableException implements Exception {
  final String message;
  const AiModelUnavailableException(this.message);
  @override
  String toString() => message;
}

class AiModelStatus {
  final String id;
  final String title;
  final String assetPath;
  final String license;
  final bool available;
  final int sizeBytes;
  final String sha256Short;

  const AiModelStatus({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.license,
    required this.available,
    required this.sizeBytes,
    required this.sha256Short,
  });
}

class LocalAiService {
  LocalAiService._();
  static final LocalAiService instance = LocalAiService._();

  static const String esrganAsset = 'assets/ai_models/real_esrgan.tflite';
  static const String aotGanAsset = 'assets/ai_models/aot_gan.tflite';
  static const String ddColorAsset = 'assets/ai_models/ddcolor.tflite';

  static const String esrganExpectedSha256 =
      '4fc65b68a3e5d4bfa97bc6e9c51cfa9ab7dc579a4486613abc00ecf68e1864f0';
  static const String aotGanExpectedSha256 =
      'f1dfc75f2ba4d87af6f173d3ba704b5f89860c88dd60620bf050d5c06f055411';

  Future<List<AiModelStatus>> inspectAllModels() async {
    return [
      const AiModelStatus(
        id: 'mlkit_segmentation',
        title: 'ML Kit Person Segmentation (On-Device)',
        assetPath: 'Bundled via Android ML Kit',
        license: 'Google ML Kit Terms',
        available: true,
        sizeBytes: 0,
        sha256Short: 'On-Device Native',
      ),
      const AiModelStatus(
        id: 'mlkit_face',
        title: 'ML Kit Face Detection (On-Device)',
        assetPath: 'Bundled via Android ML Kit',
        license: 'Google ML Kit Terms',
        available: true,
        sizeBytes: 0,
        sha256Short: 'On-Device Native',
      ),
      await _checkTfliteAsset(
        id: 'real_esrgan',
        title: 'Real-ESRGAN x4v3 (Enhancer & Restoration)',
        assetPath: esrganAsset,
        license: 'BSD-3-Clause',
        expectedSha: esrganExpectedSha256,
      ),
      await _checkTfliteAsset(
        id: 'aot_gan',
        title: 'AOT-GAN (Object Eraser / Inpainting)',
        assetPath: aotGanAsset,
        license: 'MIT License',
        expectedSha: aotGanExpectedSha256,
      ),
      await _checkTfliteAsset(
        id: 'ddcolor',
        title: 'DDColor (B&W Photo Colorization)',
        assetPath: ddColorAsset,
        license: 'Apache-2.0',
      ),
    ];
  }

  Future<AiModelStatus> _checkTfliteAsset({
    required String id,
    required String title,
    required String assetPath,
    required String license,
    String? expectedSha,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final digest = sha256.convert(bytes).toString();
      final valid = bytes.length > 1024 &&
          (expectedSha == null || digest == expectedSha);
      return AiModelStatus(
        id: id,
        title: title,
        assetPath: assetPath,
        license: license,
        available: valid,
        sizeBytes: bytes.length,
        sha256Short: digest.substring(0, 12),
      );
    } catch (_) {
      return AiModelStatus(
        id: id,
        title: title,
        assetPath: assetPath,
        license: license,
        available: false,
        sizeBytes: 0,
        sha256Short: 'Unavailable',
      );
    }
  }

  Future<String> _makeTempOutputPath(String prefix, String ext) async {
    final dir = await getApplicationSupportDirectory();
    final aiDir = Directory(p.join(dir.path, 'ai_cache'));
    if (!await aiDir.exists()) {
      await aiDir.create(recursive: true);
    }
    return p.join(
      aiDir.path,
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
  }

  /// Real On-Device Person Segmentation via Google ML Kit
  Future<String> generatePersonSegmentationMask(String sourcePath) async {
    final segmenter = SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: false,
    );
    try {
      final inputImage = InputImage.fromFilePath(sourcePath);
      final mask = await segmenter.processImage(inputImage);
      if (mask == null || mask.confidences.isEmpty) {
        throw const AiModelUnavailableException(
          'No subject segmentation mask could be generated for this photo.',
        );
      }

      final maskImg = img.Image(
        width: mask.width,
        height: mask.height,
        numChannels: 4,
      );
      for (int y = 0; y < mask.height; y++) {
        for (int x = 0; x < mask.width; x++) {
          final conf = mask.confidences[y * mask.width + x].clamp(0.0, 1.0);
          final v = (conf * 255).round();
          maskImg.setPixelRgba(x, y, v, v, v, 255);
        }
      }

      final outPath = await _makeTempOutputPath('seg_mask', 'png');
      await File(outPath).writeAsBytes(img.encodePng(maskImg), flush: true);
      return outPath;
    } finally {
      await segmenter.close();
    }
  }

  /// Real On-Device Face Detection + Localized Skin Smoothing & Brightening
  Future<String> retouchFacesOnDevice(
    String sourcePath, {
    double intensity = 0.6,
  }) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: false,
        enableContours: false,
      ),
    );
    try {
      final inputImage = InputImage.fromFilePath(sourcePath);
      final faces = await detector.processImage(inputImage);
      if (faces.isEmpty) {
        throw const AiModelUnavailableException(
          'No faces detected by on-device ML Kit Face Detector.',
        );
      }

      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const AiModelUnavailableException('Could not decode photo for retouching.');
      }
      final work = img.bakeOrientation(decoded).convert(numChannels: 4);
      final smoothLayer = img.gaussianBlur(img.Image.from(work), radius: 5);
      final amount = intensity.clamp(0.1, 1.0);

      for (final face in faces) {
        final Rect box = face.boundingBox;
        final x0 = math.max(0, box.left.round());
        final y0 = math.max(0, box.top.round());
        final x1 = math.min(work.width - 1, box.right.round());
        final y1 = math.min(work.height - 1, box.bottom.round());
        final cx = (x0 + x1) / 2.0;
        final cy = (y0 + y1) / 2.0;
        final rx = math.max(1.0, (x1 - x0) / 2.0);
        final ry = math.max(1.0, (y1 - y0) / 2.0);

        for (int y = y0; y <= y1; y++) {
          final dy = (y - cy) / ry;
          for (int x = x0; x <= x1; x++) {
            final dx = (x - cx) / rx;
            final ellip = dx * dx + dy * dy;
            if (ellip > 1.0) continue;

            final op = work.getPixel(x, y);
            final sp = smoothLayer.getPixel(x, y);

            // Preserve sharp edges (eyes, brows, lips, hair) while smoothing skin patches
            final diff = ((op.r - sp.r).abs() +
                    (op.g - sp.g).abs() +
                    (op.b - sp.b).abs()) /
                3.0;
            final edgePreservation = (1.0 - (diff / 34.0)).clamp(0.0, 1.0);
            final radialWeight = (1.0 - ellip).clamp(0.0, 1.0);
            final blend = amount * 0.65 * edgePreservation * radialWeight;
            final brightLift = 1.0 + (amount * 0.06 * radialWeight);

            final r = ((op.r * (1 - blend) + sp.r * blend) * brightLift)
                .clamp(0, 255)
                .round();
            final g = ((op.g * (1 - blend) + sp.g * blend) * brightLift)
                .clamp(0, 255)
                .round();
            final b = ((op.b * (1 - blend) + sp.b * blend) * brightLift)
                .clamp(0, 255)
                .round();

            work.setPixelRgba(x, y, r, g, b, op.a.round());
          }
        }
      }

      final outPath = await _makeTempOutputPath('face_retouch', 'png');
      await File(outPath).writeAsBytes(img.encodePng(work), flush: true);
      return outPath;
    } finally {
      await detector.close();
    }
  }
  Future<Interpreter> _openVerifiedInterpreter(
    String assetPath,
    PerformanceConfig config, {
    String? expectedSha,
  }) async {
    ByteData data;
    try {
      data = await rootBundle.load(assetPath);
    } catch (_) {
      throw AiModelUnavailableException(
        'On-device AI model ($assetPath) is not bundled or unavailable.',
      );
    }

    final bytes = data.buffer.asUint8List();
    if (bytes.length < 1024) {
      throw AiModelUnavailableException(
        'On-device AI model ($assetPath) is incomplete.',
      );
    }
    if (expectedSha != null) {
      final digest = sha256.convert(bytes).toString();
      if (digest != expectedSha) {
        throw AiModelUnavailableException(
          'Checksum verification failed for $assetPath.',
        );
      }
    }

    final options = InterpreterOptions()..threads = config.interpreterThreads;
    return Interpreter.fromAsset(assetPath, options: options);
  }

  /// Real-ESRGAN TFLite Enhancement & Old Photo Restoration
  Future<String> enhanceOrRestoreWithRealEsrgan(
    String sourcePath,
    PerformanceConfig config, {
    bool restoreMode = false,
  }) async {
    final interpreter = await _openVerifiedInterpreter(
      esrganAsset,
      config,
      expectedSha: esrganExpectedSha256,
    );
    try {
      final rawBytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        throw const AiModelUnavailableException('Could not decode input image.');
      }
      var work = img.bakeOrientation(decoded).convert(numChannels: 4);

      if (restoreMode) {
        // Gentle pre-denoising for faded/scratched prints before neural super-resolution
        final denoised = img.gaussianBlur(img.Image.from(work), radius: 1);
        for (int y = 0; y < work.height; y++) {
          for (int x = 0; x < work.width; x++) {
            final a = work.getPixel(x, y);
            final b = denoised.getPixel(x, y);
            work.setPixelRgba(
              x,
              y,
              (a.r * 0.7 + b.r * 0.3).round(),
              (a.g * 0.7 + b.g * 0.3).round(),
              (a.b * 0.7 + b.b * 0.3).round(),
              255,
            );
          }
        }
      }

      final inTensor = interpreter.getInputTensor(0);
      final outTensor = interpreter.getOutputTensor(0);
      final inShape = inTensor.shape; // e.g. [1, H, W, 3] or [1, 3, H, W]
      final isNchw = inShape.length == 4 && inShape[1] == 3;
      final modelH = isNchw ? inShape[2] : inShape[1];
      final modelW = isNchw ? inShape[3] : inShape[2];

      final resizedIn = img.copyResize(
        work,
        width: modelW,
        height: modelH,
        interpolation: img.Interpolation.linear,
      );

      final inBuf = _imageToTensorBuffer(resizedIn, inTensor, isNchw: isNchw);
      final outBuf = _allocateOutputBuffer(outTensor);
      interpreter.run(inBuf, outBuf);

      final outShape = outTensor.shape;
      final outIsNchw = outShape.length == 4 && outShape[1] == 3;
      final outH = outIsNchw ? outShape[2] : outShape[1];
      final outW = outIsNchw ? outShape[3] : outShape[2];

      final enhancedPatch = _tensorBufferToImage(
        outBuf,
        outTensor,
        width: outW,
        height: outH,
        isNchw: outIsNchw,
      );

      // Fit enhanced neural output back to working resolution up to performance cap
      final targetMax = math.min(
        config.aiInputMaxDimension * 2,
        math.max(work.width, work.height),
      );
      final scale = targetMax / math.max(work.width, work.height);
      final finalW = scale < 1.0 ? (work.width * scale).round() : work.width;
      final finalH = scale < 1.0 ? (work.height * scale).round() : work.height;

      final upscaledAi = img.copyResize(
        enhancedPatch,
        width: finalW,
        height: finalH,
        interpolation: img.Interpolation.cubic,
      );
      final baseScaled = img.copyResize(
        work,
        width: finalW,
        height: finalH,
        interpolation: img.Interpolation.linear,
      );

      // Preserve authentic identity by blending 75% AI output + 25% original texture
      for (int y = 0; y < finalH; y++) {
        for (int x = 0; x < finalW; x++) {
          final ap = upscaledAi.getPixel(x, y);
          final bp = baseScaled.getPixel(x, y);
          baseScaled.setPixelRgba(
            x,
            y,
            (ap.r * 0.75 + bp.r * 0.25).round().clamp(0, 255),
            (ap.g * 0.75 + bp.g * 0.25).round().clamp(0, 255),
            (ap.b * 0.75 + bp.b * 0.25).round().clamp(0, 255),
            255,
          );
        }
      }

      final outPath = await _makeTempOutputPath(
        restoreMode ? 'ai_restored' : 'ai_enhanced',
        'png',
      );
      await File(outPath).writeAsBytes(img.encodePng(baseScaled), flush: true);
      return outPath;
    } finally {
      interpreter.close();
    }
  }

  /// AOT-GAN Local TFLite Inpainting (Object Eraser)
  Future<String> eraseObjectWithAotGan(
    String sourcePath,
    List<RetouchStroke> maskStrokes,
    PerformanceConfig config,
  ) async {
    if (maskStrokes.isEmpty) {
      throw const AiModelUnavailableException(
        'Please brush over the object you want to erase first.',
      );
    }

    final interpreter = await _openVerifiedInterpreter(
      aotGanAsset,
      config,
      expectedSha: aotGanExpectedSha256,
    );
    try {
      final rawBytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        throw const AiModelUnavailableException('Could not decode input image.');
      }
      final work = img.bakeOrientation(decoded).convert(numChannels: 4);

      final inTensor0 = interpreter.getInputTensor(0);
      final inShape0 = inTensor0.shape;
      final isNchw = inShape0.length == 4 &&
          (inShape0[1] == 3 || inShape0[1] == 4);
      final modelH = isNchw ? inShape0[2] : inShape0[1];
      final modelW = isNchw ? inShape0[3] : inShape0[2];

      final resized = img.copyResize(work, width: modelW, height: modelH);
      final maskImg = _rasterizeMask(modelW, modelH, maskStrokes);

      final outTensor = interpreter.getOutputTensor(0);
      final outBuf = _allocateOutputBuffer(outTensor);

      final inputCount = interpreter.getInputTensors().length;
      if (inputCount >= 2) {
        final inTensor1 = interpreter.getInputTensor(1);
        final imgBuf = _imageToTensorBuffer(resized, inTensor0, isNchw: isNchw);
        final mBuf = _maskToTensorBuffer(maskImg, inTensor1);
        interpreter.runForMultipleInputs([imgBuf, mBuf], {0: outBuf});
      } else {
        final imgBuf = _imageToTensorBuffer(resized, inTensor0, isNchw: isNchw);
        interpreter.run(imgBuf, outBuf);
      }

      final outShape = outTensor.shape;
      final outIsNchw = outShape.length == 4 && outShape[1] == 3;
      final repairedSmall = _tensorBufferToImage(
        outBuf,
        outTensor,
        width: outIsNchw ? outShape[3] : outShape[2],
        height: outIsNchw ? outShape[2] : outShape[1],
        isNchw: outIsNchw,
      );

      final repairedFull = img.copyResize(
        repairedSmall,
        width: work.width,
        height: work.height,
        interpolation: img.Interpolation.linear,
      );
      final fullMask = _rasterizeMask(work.width, work.height, maskStrokes);
      final softMask = img.gaussianBlur(fullMask, radius: 4);

      for (int y = 0; y < work.height; y++) {
        for (int x = 0; x < work.width; x++) {
          final m = (softMask.getPixel(x, y).r / 255.0).clamp(0.0, 1.0);
          if (m <= 0.01) continue;
          final op = work.getPixel(x, y);
          final rp = repairedFull.getPixel(x, y);
          work.setPixelRgba(
            x,
            y,
            (op.r * (1 - m) + rp.r * m).round().clamp(0, 255),
            (op.g * (1 - m) + rp.g * m).round().clamp(0, 255),
            (op.b * (1 - m) + rp.b * m).round().clamp(0, 255),
            255,
          );
        }
      }

      final outPath = await _makeTempOutputPath('ai_erased', 'png');
      await File(outPath).writeAsBytes(img.encodePng(work), flush: true);
      return outPath;
    } finally {
      interpreter.close();
    }
  }

  /// DDColor Local TFLite Photo Colorization (B&W -> Color)
  Future<String> colorizeWithDdColor(
    String sourcePath,
    PerformanceConfig config,
  ) async {
    final interpreter = await _openVerifiedInterpreter(ddColorAsset, config);
    try {
      final rawBytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        throw const AiModelUnavailableException('Could not decode input image.');
      }
      final work = img.bakeOrientation(decoded).convert(numChannels: 4);

      final inTensor = interpreter.getInputTensor(0);
      final outTensor = interpreter.getOutputTensor(0);
      final inShape = inTensor.shape;
      final isNchw = inShape.length == 4 && inShape[1] == 3;
      final modelH = isNchw ? inShape[2] : inShape[1];
      final modelW = isNchw ? inShape[3] : inShape[2];

      final resized = img.copyResize(work, width: modelW, height: modelH);
      final inBuf = _imageToTensorBuffer(resized, inTensor, isNchw: isNchw);
      final outBuf = _allocateOutputBuffer(outTensor);
      interpreter.run(inBuf, outBuf);

      final outShape = outTensor.shape;
      final outIsNchw = outShape.length == 4 && outShape[1] == 3;
      final colorSmall = _tensorBufferToImage(
        outBuf,
        outTensor,
        width: outIsNchw ? outShape[3] : outShape[2],
        height: outIsNchw ? outShape[2] : outShape[1],
        isNchw: outIsNchw,
      );

      final colorFull = img.copyResize(
        colorSmall,
        width: work.width,
        height: work.height,
        interpolation: img.Interpolation.linear,
      );

      // Preserve crisp original B&W luminance while transferring AI predicted chrominance
      for (int y = 0; y < work.height; y++) {
        for (int x = 0; x < work.width; x++) {
          final op = work.getPixel(x, y);
          final cp = colorFull.getPixel(x, y);
          final origY = 0.299 * op.r + 0.587 * op.g + 0.114 * op.b;
          final predY = math.max(1.0, 0.299 * cp.r + 0.587 * cp.g + 0.114 * cp.b);
          final scale = origY / predY;
          work.setPixelRgba(
            x,
            y,
            (cp.r * scale).round().clamp(0, 255),
            (cp.g * scale).round().clamp(0, 255),
            (cp.b * scale).round().clamp(0, 255),
            255,
          );
        }
      }

      final outPath = await _makeTempOutputPath('ai_colorized', 'png');
      await File(outPath).writeAsBytes(img.encodePng(work), flush: true);
      return outPath;
    } finally {
      interpreter.close();
    }
  }

  img.Image _rasterizeMask(int width, int height, List<RetouchStroke> strokes) {
    final mask = img.Image(width: width, height: height, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));
    for (final s in strokes) {
      final radius = math.max(3, (s.brushSize * math.min(width, height)).round());
      final r2 = radius * radius;
      for (final pt in s.normalizedPoints) {
        final cx = (pt.dx * width).round();
        final cy = (pt.dy * height).round();
        for (int dy = -radius; dy <= radius; dy++) {
          final py = cy + dy;
          if (py < 0 || py >= height) continue;
          for (int dx = -radius; dx <= radius; dx++) {
            final px = cx + dx;
            if (px < 0 || px >= width) continue;
            if (dx * dx + dy * dy <= r2) {
              mask.setPixelRgba(px, py, 255, 255, 255, 255);
            }
          }
        }
      }
    }
    return mask;
  }

  ByteBuffer _imageToTensorBuffer(
    img.Image image,
    Tensor tensor, {
    required bool isNchw,
  }) {
    final h = image.height;
    final w = image.width;
    final count = 1 * h * w * 3;
    final scale = tensor.params.scale == 0 ? 1.0 : tensor.params.scale;
    final zp = tensor.params.zeroPoint;

    if (tensor.type == TensorType.uint8) {
      final list = Uint8List(count);
      int idx = 0;
      if (!isNchw) {
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final p = image.getPixel(x, y);
            list[idx++] = p.r.round().clamp(0, 255);
            list[idx++] = p.g.round().clamp(0, 255);
            list[idx++] = p.b.round().clamp(0, 255);
          }
        }
      } else {
        for (int c = 0; c < 3; c++) {
          for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
              final p = image.getPixel(x, y);
              final v = c == 0 ? p.r : (c == 1 ? p.g : p.b);
              list[idx++] = v.round().clamp(0, 255);
            }
          }
        }
      }
      return list.buffer;
    } else if (tensor.type == TensorType.int8) {
      final list = Int8List(count);
      int idx = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          list[idx++] = (((p.r / 255.0) / scale) + zp).round().clamp(-128, 127);
          list[idx++] = (((p.g / 255.0) / scale) + zp).round().clamp(-128, 127);
          list[idx++] = (((p.b / 255.0) / scale) + zp).round().clamp(-128, 127);
        }
      }
      return list.buffer;
    } else {
      final list = Float32List(count);
      int idx = 0;
      if (!isNchw) {
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final p = image.getPixel(x, y);
            list[idx++] = p.r / 255.0;
            list[idx++] = p.g / 255.0;
            list[idx++] = p.b / 255.0;
          }
        }
      } else {
        for (int c = 0; c < 3; c++) {
          for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
              final p = image.getPixel(x, y);
              final v = c == 0 ? p.r : (c == 1 ? p.g : p.b);
              list[idx++] = v / 255.0;
            }
          }
        }
      }
      return list.buffer;
    }
  }

  ByteBuffer _maskToTensorBuffer(img.Image mask, Tensor tensor) {
    final h = mask.height;
    final w = mask.width;
    final count = h * w;
    if (tensor.type == TensorType.uint8) {
      final list = Uint8List(count);
      int idx = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          list[idx++] = mask.getPixel(x, y).r.round().clamp(0, 255);
        }
      }
      return list.buffer;
    } else {
      final list = Float32List(count);
      int idx = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          list[idx++] = mask.getPixel(x, y).r > 127 ? 1.0 : 0.0;
        }
      }
      return list.buffer;
    }
  }

  ByteBuffer _allocateOutputBuffer(Tensor tensor) {
    final totalElements = tensor.shape.fold<int>(1, (a, b) => a * b);
    if (tensor.type == TensorType.uint8) return Uint8List(totalElements).buffer;
    if (tensor.type == TensorType.int8) return Int8List(totalElements).buffer;
    return Float32List(totalElements).buffer;
  }

  img.Image _tensorBufferToImage(
    ByteBuffer buffer,
    Tensor tensor, {
    required int width,
    required int height,
    required bool isNchw,
  }) {
    final out = img.Image(width: width, height: height, numChannels: 4);
    final scale = tensor.params.scale == 0 ? 1.0 : tensor.params.scale;
    final zp = tensor.params.zeroPoint;

    double readVal(int idx) {
      if (tensor.type == TensorType.uint8) {
        return buffer.asUint8List()[idx].toDouble();
      } else if (tensor.type == TensorType.int8) {
        return (buffer.asInt8List()[idx] - zp) * scale * 255.0;
      } else {
        final v = buffer.asFloat32List()[idx];
        return v <= 1.5 ? v * 255.0 : v;
      }
    }

    final hw = width * height;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pos = y * width + x;
        final double r, g, b;
        if (!isNchw) {
          r = readVal(pos * 3);
          g = readVal(pos * 3 + 1);
          b = readVal(pos * 3 + 2);
        } else {
          r = readVal(pos);
          g = readVal(hw + pos);
          b = readVal(2 * hw + pos);
        }
        out.setPixelRgba(
          x,
          y,
          r.round().clamp(0, 255),
          g.round().clamp(0, 255),
          b.round().clamp(0, 255),
          255,
        );
      }
    }
    return out;
  }
}
