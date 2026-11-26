import 'dart:io';
import 'dart:math' as math;

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
import 'tflite_tensor_utils.dart';

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
      '65882cbcd2e9b973dc6a12beda3be51ab8539533ba7688a938a4f94ca17be669';

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
    if (!await aiDir.exists()) await aiDir.create(recursive: true);
    return p.join(
      aiDir.path,
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
  }

  Future<String> generatePersonSegmentationMask(String sourcePath) async {
    final segmenter = SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: false,
    );
    try {
      final mask = await segmenter.processImage(
        InputImage.fromFilePath(sourcePath),
      );
      if (mask == null || mask.confidences.isEmpty) {
        throw const AiModelUnavailableException(
          'No subject segmentation mask could be generated.',
        );
      }
      final maskImg = img.Image(
        width: mask.width,
        height: mask.height,
        numChannels: 4,
      );
      for (int y = 0; y < mask.height; y++) {
        for (int x = 0; x < mask.width; x++) {
          final v = (mask.confidences[y * mask.width + x].clamp(0.0, 1.0) * 255)
              .round();
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

  Future<String> retouchFacesOnDevice(
    String sourcePath, {
    double intensity = 0.6,
  }) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
    );
    try {
      final faces = await detector.processImage(
        InputImage.fromFilePath(sourcePath),
      );
      if (faces.isEmpty) {
        throw const AiModelUnavailableException(
          'No faces detected by on-device ML Kit Face Detector.',
        );
      }
      final decoded = img.decodeImage(await File(sourcePath).readAsBytes());
      if (decoded == null) {
        throw const AiModelUnavailableException('Could not decode photo.');
      }
      final work = img.bakeOrientation(decoded).convert(numChannels: 4);
      final smooth = img.gaussianBlur(img.Image.from(work), radius: 5);
      final amount = intensity.clamp(0.1, 1.0);

      for (final face in faces) {
        final box = face.boundingBox;
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
            final sp = smooth.getPixel(x, y);
            final diff = ((op.r - sp.r).abs() +
                    (op.g - sp.g).abs() +
                    (op.b - sp.b).abs()) /
                3.0;
            final edge = (1.0 - (diff / 34.0)).clamp(0.0, 1.0);
            final radial = (1.0 - ellip).clamp(0.0, 1.0);
            final blend = amount * 0.65 * edge * radial;
            final lift = 1.0 + (amount * 0.06 * radial);
            work.setPixelRgba(
              x,
              y,
              ((op.r * (1 - blend) + sp.r * blend) * lift).clamp(0, 255).round(),
              ((op.g * (1 - blend) + sp.g * blend) * lift).clamp(0, 255).round(),
              ((op.b * (1 - blend) + sp.b * blend) * lift).clamp(0, 255).round(),
              op.a.round(),
            );
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
    final ByteData data;
    try {
      data = await rootBundle.load(assetPath);
    } catch (_) {
      throw AiModelUnavailableException(
        'On-device AI model ($assetPath) is unavailable.',
      );
    }
    final bytes = data.buffer.asUint8List();
    if (bytes.length < 1024) {
      throw AiModelUnavailableException('Model ($assetPath) is incomplete.');
    }
    if (expectedSha != null && sha256.convert(bytes).toString() != expectedSha) {
      throw AiModelUnavailableException('Checksum mismatch for $assetPath.');
    }
    final options = InterpreterOptions()..threads = config.interpreterThreads;
    return Interpreter.fromAsset(assetPath, options: options);
  }

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
      final decoded = img.decodeImage(await File(sourcePath).readAsBytes());
      if (decoded == null) {
        throw const AiModelUnavailableException('Could not decode image.');
      }
      final work = img.bakeOrientation(decoded).convert(numChannels: 4);
      final inTensor = interpreter.getInputTensor(0);
      final outTensor = interpreter.getOutputTensor(0);
      final inShape = inTensor.shape;
      final isNchw = inShape.length == 4 && inShape[1] == 3;
      final resizedIn = img.copyResize(
        work,
        width: isNchw ? inShape[3] : inShape[2],
        height: isNchw ? inShape[2] : inShape[1],
      );
      final inBuf = TfliteTensorUtils.imageToTensorBuffer(
        resizedIn,
        inTensor,
        isNchw: isNchw,
      );
      final outBuf = TfliteTensorUtils.allocateOutputBuffer(outTensor);
      interpreter.run(inBuf, outBuf);

      final outShape = outTensor.shape;
      final outNchw = outShape.length == 4 && outShape[1] == 3;
      final patch = TfliteTensorUtils.tensorBufferToImage(
        outBuf,
        outTensor,
        width: outNchw ? outShape[3] : outShape[2],
        height: outNchw ? outShape[2] : outShape[1],
        isNchw: outNchw,
      );

      final targetMax = math.min(
        config.aiInputMaxDimension * 2,
        math.max(work.width, work.height),
      );
      final scale = targetMax / math.max(work.width, work.height);
      final finalW = scale < 1.0 ? (work.width * scale).round() : work.width;
      final finalH = scale < 1.0 ? (work.height * scale).round() : work.height;
      final aiUp = img.copyResize(patch, width: finalW, height: finalH);
      final base = img.copyResize(work, width: finalW, height: finalH);

      for (int y = 0; y < finalH; y++) {
        for (int x = 0; x < finalW; x++) {
          final ap = aiUp.getPixel(x, y);
          final bp = base.getPixel(x, y);
          base.setPixelRgba(
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
      await File(outPath).writeAsBytes(img.encodePng(base), flush: true);
      return outPath;
    } finally {
      interpreter.close();
    }
  }

  Future<String> eraseObjectWithAotGan(
    String sourcePath,
    List<RetouchStroke> maskStrokes,
    PerformanceConfig config,
  ) async {
    if (maskStrokes.isEmpty) {
      throw const AiModelUnavailableException('Brush over an object first.');
    }
    final interpreter = await _openVerifiedInterpreter(
      aotGanAsset,
      config,
      expectedSha: aotGanExpectedSha256,
    );
    try {
      final decoded = img.decodeImage(await File(sourcePath).readAsBytes());
      if (decoded == null) {
        throw const AiModelUnavailableException('Could not decode image.');
      }
      final work = img.bakeOrientation(decoded).convert(numChannels: 4);
      final inTensor0 = interpreter.getInputTensor(0);
      final s0 = inTensor0.shape;
      final isNchw = s0.length == 4 && (s0[1] == 3 || s0[1] == 4);
      final modelH = isNchw ? s0[2] : s0[1];
      final modelW = isNchw ? s0[3] : s0[2];
      final resized = img.copyResize(work, width: modelW, height: modelH);
      final maskImg = TfliteTensorUtils.rasterizeMask(
        modelW,
        modelH,
        maskStrokes,
      );
      final outTensor = interpreter.getOutputTensor(0);
      final outBuf = TfliteTensorUtils.allocateOutputBuffer(outTensor);

      if (interpreter.getInputTensors().length >= 2) {
        final in1 = interpreter.getInputTensor(1);
        interpreter.runForMultipleInputs(
          [
            TfliteTensorUtils.imageToTensorBuffer(
              resized,
              inTensor0,
              isNchw: isNchw,
            ),
            TfliteTensorUtils.maskToTensorBuffer(maskImg, in1),
          ],
          {0: outBuf},
        );
      } else {
        interpreter.run(
          TfliteTensorUtils.imageToTensorBuffer(
            resized,
            inTensor0,
            isNchw: isNchw,
          ),
          outBuf,
        );
      }

      final os = outTensor.shape;
      final outNchw = os.length == 4 && os[1] == 3;
      final small = TfliteTensorUtils.tensorBufferToImage(
        outBuf,
        outTensor,
        width: outNchw ? os[3] : os[2],
        height: outNchw ? os[2] : os[1],
        isNchw: outNchw,
      );
      final repaired =
          img.copyResize(small, width: work.width, height: work.height);
      final softMask = img.gaussianBlur(
        TfliteTensorUtils.rasterizeMask(work.width, work.height, maskStrokes),
        radius: 4,
      );

      for (int y = 0; y < work.height; y++) {
        for (int x = 0; x < work.width; x++) {
          final m = (softMask.getPixel(x, y).r / 255.0).clamp(0.0, 1.0);
          if (m <= 0.01) continue;
          final op = work.getPixel(x, y);
          final rp = repaired.getPixel(x, y);
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

  Future<String> colorizeWithDdColor(
    String sourcePath,
    PerformanceConfig config,
  ) async {
    final interpreter = await _openVerifiedInterpreter(ddColorAsset, config);
    try {
      final decoded = img.decodeImage(await File(sourcePath).readAsBytes());
      if (decoded == null) {
        throw const AiModelUnavailableException('Could not decode image.');
      }
      final work = img.bakeOrientation(decoded).convert(numChannels: 4);
      final inT = interpreter.getInputTensor(0);
      final outT = interpreter.getOutputTensor(0);
      final isNchw = inT.shape.length == 4 && inT.shape[1] == 3;
      final resized = img.copyResize(
        work,
        width: isNchw ? inT.shape[3] : inT.shape[2],
        height: isNchw ? inT.shape[2] : inT.shape[1],
      );
      final outBuf = TfliteTensorUtils.allocateOutputBuffer(outT);
      interpreter.run(
        TfliteTensorUtils.imageToTensorBuffer(resized, inT, isNchw: isNchw),
        outBuf,
      );

      final os = outT.shape;
      final outNchw = os.length == 4 && os[1] == 3;
      final colorFull = img.copyResize(
        TfliteTensorUtils.tensorBufferToImage(
          outBuf,
          outT,
          width: outNchw ? os[3] : os[2],
          height: outNchw ? os[2] : os[1],
          isNchw: outNchw,
        ),
        width: work.width,
        height: work.height,
      );
      for (int y = 0; y < work.height; y++) {
        for (int x = 0; x < work.width; x++) {
          final op = work.getPixel(x, y);
          final cp = colorFull.getPixel(x, y);
          final oy = 0.299 * op.r + 0.587 * op.g + 0.114 * op.b;
          final py =
              math.max(1.0, 0.299 * cp.r + 0.587 * cp.g + 0.114 * cp.b);
          final s = oy / py;
          work.setPixelRgba(
            x,
            y,
            (cp.r * s).round().clamp(0, 255),
            (cp.g * s).round().clamp(0, 255),
            (cp.b * s).round().clamp(0, 255),
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
}
