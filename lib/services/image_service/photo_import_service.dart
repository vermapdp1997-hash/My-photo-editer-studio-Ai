import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImportedPhotoInfo {
  final String filePath;
  final int width;
  final int height;
  final int fileSizeBytes;
  final String extensionName;

  const ImportedPhotoInfo({
    required this.filePath,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.extensionName,
  });
}

class PhotoImportException implements Exception {
  final String message;
  const PhotoImportException(this.message);
  @override
  String toString() => message;
}

class PhotoImportService {
  PhotoImportService._();
  static final PhotoImportService instance = PhotoImportService._();

  final ImagePicker _picker = ImagePicker();

  static const Set<String> supportedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  };

  Future<ImportedPhotoInfo?> pickSinglePhoto() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    return validateAndPrepare(picked.path);
  }

  Future<List<ImportedPhotoInfo>> pickMultiplePhotos({int limit = 6}) async {
    final List<XFile> picked = await _picker.pickMultiImage(
      limit: limit,
      requestFullMetadata: false,
    );
    if (picked.isEmpty) return [];

    final results = <ImportedPhotoInfo>[];
    for (final file in picked) {
      try {
        results.add(await validateAndPrepare(file.path));
      } catch (_) {
        // Skip unreadable individual files while keeping valid ones
      }
    }
    if (results.isEmpty) {
      throw const PhotoImportException(
        'None of the selected files could be decoded as valid images.',
      );
    }
    return results;
  }

  Future<ImportedPhotoInfo> validateAndPrepare(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const PhotoImportException('Selected image file does not exist.');
    }

    final ext = p.extension(path).toLowerCase();
    if (ext.isNotEmpty && !supportedExtensions.contains(ext)) {
      throw PhotoImportException(
        'Unsupported format ($ext). Please choose JPG, PNG, WebP, or HEIC.',
      );
    }

    final fileSize = await file.length();
    if (fileSize <= 0) {
      throw const PhotoImportException('The selected image file is empty or corrupted.');
    }

    final Uint8List bytes = await file.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);

    String usablePath = path;

    // Native Android Skia/ImageDecoder fallback for HEIC / HEIF or tricky streams
    if (decoded == null) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final uiImage = frame.image;
        final bd = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        uiImage.dispose();
        codec.dispose();
        if (bd != null) {
          final pngBytes = bd.buffer.asUint8List();
          decoded = img.decodePng(pngBytes);
          if (decoded != null) {
            final dir = await getApplicationSupportDirectory();
            final importsDir = Directory(p.join(dir.path, 'imported_sources'));
            if (!await importsDir.exists()) {
              await importsDir.create(recursive: true);
            }
            usablePath = p.join(
              importsDir.path,
              'img_${DateTime.now().microsecondsSinceEpoch}.png',
            );
            await File(usablePath).writeAsBytes(pngBytes, flush: true);
          }
        }
      } catch (_) {
        decoded = null;
      }
    }

    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw const PhotoImportException(
        'Corrupted or unreadable image file. Please select another photo.',
      );
    }

    // Copy to app-private source storage so Android temporary picker cache cannot expire
    if (usablePath == path) {
      final dir = await getApplicationSupportDirectory();
      final importsDir = Directory(p.join(dir.path, 'imported_sources'));
      if (!await importsDir.exists()) {
        await importsDir.create(recursive: true);
      }
      final safeExt = ext.isEmpty ? '.jpg' : ext;
      usablePath = p.join(
        importsDir.path,
        'src_${DateTime.now().microsecondsSinceEpoch}$safeExt',
      );
      await file.copy(usablePath);
    }

    return ImportedPhotoInfo(
      filePath: usablePath,
      width: decoded.width,
      height: decoded.height,
      fileSizeBytes: fileSize,
      extensionName: ext.isEmpty ? 'IMG' : ext.replaceFirst('.', '').toUpperCase(),
    );
  }
}
