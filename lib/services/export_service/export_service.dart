import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/edit_state.dart';
import '../../data/models/project_model.dart';
import '../image_service/image_pipeline_service.dart';

class ExportResult {
  final String filePath;
  final int width;
  final int height;
  final int fileSizeBytes;

  const ExportResult({
    required this.filePath,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
  });
}

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  Future<ExportResult> renderExportFile({
    required String sourcePath,
    required EditState state,
    required ExportFormat format,
    required ExportResolutionPreset preset,
    required int quality,
    int? customWidth,
    int? customHeight,
    bool saveToGallery = false,
  }) async {
    final maxDim = switch (preset) {
      ExportResolutionPreset.original => 0,
      ExportResolutionPreset.p1080 => 1920,
      ExportResolutionPreset.p2k => 2560,
      ExportResolutionPreset.p4k => 3840,
      ExportResolutionPreset.custom => 0,
    };

    img.Image rendered = await ImagePipelineService.instance.renderForExport(
      sourcePath,
      state,
      maxDimension: maxDim,
    );

    if (preset == ExportResolutionPreset.custom &&
        customWidth != null &&
        customHeight != null &&
        customWidth > 16 &&
        customHeight > 16) {
      rendered = img.copyResize(
        rendered,
        width: customWidth.clamp(16, 4096),
        height: customHeight.clamp(16, 4096),
        interpolation: img.Interpolation.cubic,
      );
    } else if (maxDim > 0 && math.max(rendered.width, rendered.height) > maxDim) {
      final scale = maxDim / math.max(rendered.width, rendered.height);
      rendered = img.copyResize(
        rendered,
        width: math.max(1, (rendered.width * scale).round()),
        height: math.max(1, (rendered.height * scale).round()),
        interpolation: img.Interpolation.cubic,
      );
    }

    // Paint vector Text & Sticker layers crisp on top
    if (state.textLayers.isNotEmpty || state.stickerLayers.isNotEmpty) {
      rendered = await _compositeVectorLayers(rendered, state);
    }

    final Uint8List encodedBytes;
    final String ext;
    switch (format) {
      case ExportFormat.png:
        encodedBytes = Uint8List.fromList(img.encodePng(rendered));
        ext = 'png';
      case ExportFormat.webp:
        encodedBytes = Uint8List.fromList(
          img.encodeWebP(rendered, quality: quality.toDouble()),
        );
        ext = 'webp';
      case ExportFormat.jpg:
        encodedBytes = Uint8List.fromList(
          img.encodeJpg(rendered, quality: quality),
        );
        ext = 'jpg';
    }

    final dir = await getTemporaryDirectory();
    final outPath = p.join(
      dir.path,
      'MyPhotoEditorAI_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    final file = File(outPath);
    await file.writeAsBytes(encodedBytes, flush: true);

    if (saveToGallery) {
      final hasPerm = await Gal.hasAccess(toAlbum: true);
      if (!hasPerm) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          throw StateError('Gallery save permission was denied.');
        }
      }
      await Gal.putImage(outPath, album: 'My Photo Editor AI');
    }

    return ExportResult(
      filePath: outPath,
      width: rendered.width,
      height: rendered.height,
      fileSizeBytes: encodedBytes.length,
    );
  }

  Future<void> shareExportedFile(String filePath) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath)],
        text: 'Edited with My Photo Editor AI',
      ),
    );
  }

  Future<img.Image> _compositeVectorLayers(
    img.Image base,
    EditState state,
  ) async {
    final pngBytes = Uint8List.fromList(img.encodePng(base));
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final uiBase = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = uiBase.width.toDouble();
    final h = uiBase.height.toDouble();

    canvas.drawImage(uiBase, Offset.zero, Paint());

    final scaleUnit = math.min(w, h) / 400.0;

    for (final txt in state.textLayers) {
      final tp = TextPainter(
        text: TextSpan(
          text: txt.text,
          style: TextStyle(
            color: Color(txt.colorValue),
            fontSize: txt.fontSize * scaleUnit,
            fontWeight: FontWeight.bold,
            fontFamily: txt.fontFamily == 'Serif'
                ? 'serif'
                : (txt.fontFamily == 'Mono' ? 'monospace' : null),
            shadows: txt.hasShadow
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 6 * scaleUnit,
                      offset: Offset(2 * scaleUnit, 2 * scaleUnit),
                    ),
                  ]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(txt.normX * w, txt.normY * h);
      canvas.rotate(txt.rotation);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    for (final stk in state.stickerLayers) {
      final tp = TextPainter(
        text: TextSpan(
          text: stk.symbol,
          style: TextStyle(fontSize: 44 * stk.scale * scaleUnit),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(stk.normX * w, stk.normY * h);
      canvas.rotate(stk.rotation);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    final outUi = await recorder.endRecording().toImage(base.width, base.height);
    final outBd = await outUi.toByteData(format: ui.ImageByteFormat.png);
    uiBase.dispose();
    outUi.dispose();
    codec.dispose();

    if (outBd == null) return base;
    return img.decodePng(outBd.buffer.asUint8List()) ?? base;
  }
}
