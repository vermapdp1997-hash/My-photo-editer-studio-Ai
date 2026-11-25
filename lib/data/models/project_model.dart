import 'package:flutter/material.dart';
import '../../core/performance/performance_profile.dart';
import 'edit_state.dart';

enum ExportFormat { jpg, png, webp }

enum ExportResolutionPreset { original, p1080, p2k, p4k, custom }

class PhotoProject {
  final String id;
  final String name;
  final String sourceImagePath;
  final String? thumbnailPath;
  final EditState editState;
  final int width;
  final int height;
  final int fileSizeBytes;
  final bool isFavorite;
  final bool isDraft;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PhotoProject({
    required this.id,
    required this.name,
    required this.sourceImagePath,
    this.thumbnailPath,
    required this.editState,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    this.isFavorite = false,
    this.isDraft = true,
    required this.createdAt,
    required this.updatedAt,
  });

  PhotoProject copyWith({
    String? name,
    String? sourceImagePath,
    String? thumbnailPath,
    EditState? editState,
    int? width,
    int? height,
    int? fileSizeBytes,
    bool? isFavorite,
    bool? isDraft,
    DateTime? updatedAt,
  }) {
    return PhotoProject(
      id: id,
      name: name ?? this.name,
      sourceImagePath: sourceImagePath ?? this.sourceImagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      editState: editState ?? this.editState,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      isFavorite: isFavorite ?? this.isFavorite,
      isDraft: isDraft ?? this.isDraft,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
        'source_image_path': sourceImagePath,
        'thumbnail_path': thumbnailPath,
        'edit_state_json': editState.toJsonString(),
        'width': width,
        'height': height,
        'file_size_bytes': fileSizeBytes,
        'is_favorite': isFavorite ? 1 : 0,
        'is_draft': isDraft ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory PhotoProject.fromDbMap(Map<String, dynamic> map) {
    return PhotoProject(
      id: map['id'] as String,
      name: map['name'] as String,
      sourceImagePath: map['source_image_path'] as String,
      thumbnailPath: map['thumbnail_path'] as String?,
      editState: EditState.fromJsonString(map['edit_state_json'] as String),
      width: (map['width'] as num).toInt(),
      height: (map['height'] as num).toInt(),
      fileSizeBytes: (map['file_size_bytes'] as num).toInt(),
      isFavorite: (map['is_favorite'] as int) == 1,
      isDraft: (map['is_draft'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] as num).toInt(),
      ),
    );
  }
}

class AppSettings {
  final ThemeMode themeMode;
  final String languageCode; // 'en' or 'hi'
  final int exportQuality; // 50 - 100
  final ExportFormat defaultFormat;
  final PerformanceMode performanceMode;

  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.languageCode = 'en',
    this.exportQuality = 92,
    this.defaultFormat = ExportFormat.jpg,
    this.performanceMode = PerformanceMode.auto,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? languageCode,
    int? exportQuality,
    ExportFormat? defaultFormat,
    PerformanceMode? performanceMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      exportQuality: exportQuality ?? this.exportQuality,
      defaultFormat: defaultFormat ?? this.defaultFormat,
      performanceMode: performanceMode ?? this.performanceMode,
    );
  }
}

class AppStrings {
  final String lang;
  const AppStrings(this.lang);

  bool get isHindi => lang == 'hi';

  String get appName => 'My Photo Editor AI';
  String get offlineBadge =>
      isHindi ? '100% ऑफलाइन और प्राइवेट' : '100% Offline & Private';
  String get editPhoto => isHindi ? 'फोटो एडिट करें' : 'Edit Photo';
  String get aiTools => isHindi ? 'AI फोटो टूल्स' : 'AI Photo Tools';
  String get bgRemover => isHindi ? 'बैकग्राउंड हटाएं' : 'Background Remover';
  String get enhancer => isHindi ? 'फोटो एन्हांसर' : 'Photo Enhancer';
  String get faceRetouch => isHindi ? 'फेस रीटच' : 'Face Retouch';
  String get portraitBlur => isHindi ? 'पोर्ट्रेट ब्लर' : 'Portrait Blur';
  String get objectEraser => isHindi ? 'ऑब्जेक्ट इरेज़र' : 'Object Eraser';
  String get filtersEffects =>
      isHindi ? 'फ़िल्टर्स और इफेक्ट्स' : 'Filters & Effects';
  String get collageMaker => isHindi ? 'कोलाज मेकर' : 'Collage Maker';
  String get recentProjects => isHindi ? 'हाल के प्रोजेक्ट्स' : 'Recent Projects';
  String get favoriteEdits => isHindi ? 'पसंदीदा एडिट्स' : 'Favorite Edits';
  String get galleryImport => isHindi ? 'गैलरी से चुनें' : 'Gallery Import';
  String get settings => isHindi ? 'सेटिंग्स' : 'Settings';
  String get export => isHindi ? 'एक्सपोर्ट' : 'Export';
}
