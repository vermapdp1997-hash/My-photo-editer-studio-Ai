import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/performance/performance_profile.dart';
import '../models/project_model.dart';

class ProjectDatabase {
  ProjectDatabase._();
  static final ProjectDatabase instance = ProjectDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, 'my_photo_editor_ai.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            source_image_path TEXT NOT NULL,
            thumbnail_path TEXT,
            edit_state_json TEXT NOT NULL,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL,
            file_size_bytes INTEGER NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            is_draft INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE favorite_filters (
            filter_id TEXT PRIMARY KEY
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<PhotoProject>> fetchProjects() async {
    final db = await database;
    final rows = await db.query(
      'projects',
      orderBy: 'updated_at DESC',
    );
    return rows.map(PhotoProject.fromDbMap).toList();
  }

  Future<void> upsertProject(PhotoProject project) async {
    final db = await database;
    await db.insert(
      'projects',
      project.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProject(String id) async {
    final db = await database;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  Future<Set<String>> fetchFavoriteFilterIds() async {
    final db = await database;
    final rows = await db.query('favorite_filters');
    return rows.map((e) => e['filter_id'] as String).toSet();
  }

  Future<void> toggleFavoriteFilter(String filterId, bool add) async {
    final db = await database;
    if (add) {
      await db.insert(
        'favorite_filters',
        {'filter_id': filterId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await db.delete(
        'favorite_filters',
        where: 'filter_id = ?',
        whereArgs: [filterId],
      );
    }
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode') ?? ThemeMode.dark.index;
    final lang = prefs.getString('lang') ?? 'en';
    final quality = prefs.getInt('export_quality') ?? 92;
    final fmtIndex = prefs.getInt('default_format') ?? ExportFormat.jpg.index;
    final perfIndex =
        prefs.getInt('perf_mode') ?? PerformanceMode.auto.index;

    state = AppSettings(
      themeMode: ThemeMode.values[themeIndex.clamp(0, 2)],
      languageCode: lang,
      exportQuality: quality.clamp(50, 100),
      defaultFormat: ExportFormat.values[fmtIndex.clamp(0, 2)],
      performanceMode: PerformanceMode.values[perfIndex.clamp(0, 3)],
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  Future<void> setLanguage(String code) async {
    state = state.copyWith(languageCode: code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', code);
  }

  Future<void> setExportQuality(int quality) async {
    state = state.copyWith(exportQuality: quality.clamp(50, 100));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('export_quality', quality.clamp(50, 100));
  }

  Future<void> setDefaultFormat(ExportFormat format) async {
    state = state.copyWith(defaultFormat: format);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_format', format.index);
  }

  Future<void> setPerformanceMode(PerformanceMode mode) async {
    state = state.copyWith(performanceMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('perf_mode', mode.index);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(),
);

class ProjectsNotifier extends StateNotifier<AsyncValue<List<PhotoProject>>> {
  ProjectsNotifier() : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final list = await ProjectDatabase.instance.fetchProjects();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveProject(PhotoProject project) async {
    await ProjectDatabase.instance.upsertProject(project);
    await refresh();
  }

  Future<void> renameProject(PhotoProject project, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    await ProjectDatabase.instance.upsertProject(
      project.copyWith(name: trimmed, updatedAt: DateTime.now()),
    );
    await refresh();
  }

  Future<void> toggleFavorite(PhotoProject project) async {
    await ProjectDatabase.instance.upsertProject(
      project.copyWith(
        isFavorite: !project.isFavorite,
        updatedAt: DateTime.now(),
      ),
    );
    await refresh();
  }

  Future<void> duplicateProject(PhotoProject project) async {
    final now = DateTime.now();
    final copy = PhotoProject(
      id: 'proj_${now.microsecondsSinceEpoch}',
      name: '${project.name} (Copy)',
      sourceImagePath: project.sourceImagePath,
      thumbnailPath: project.thumbnailPath,
      editState: project.editState,
      width: project.width,
      height: project.height,
      fileSizeBytes: project.fileSizeBytes,
      isFavorite: false,
      isDraft: project.isDraft,
      createdAt: now,
      updatedAt: now,
    );
    await ProjectDatabase.instance.upsertProject(copy);
    await refresh();
  }

  Future<void> deleteProject(String id) async {
    await ProjectDatabase.instance.deleteProject(id);
    await refresh();
  }

  Future<int> calculateCacheBytes() async {
    final tempDir = await getTemporaryDirectory();
    int total = 0;
    if (await tempDir.exists()) {
      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    }
    return total;
  }

  Future<void> clearTemporaryCache() async {
    final tempDir = await getTemporaryDirectory();
    if (await tempDir.exists()) {
      await for (final entity in tempDir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}

final projectsProvider =
    StateNotifierProvider<ProjectsNotifier, AsyncValue<List<PhotoProject>>>(
  (ref) => ProjectsNotifier(),
);

final favoriteFiltersProvider =
    StateNotifierProvider<FavoriteFiltersNotifier, Set<String>>(
  (ref) => FavoriteFiltersNotifier(),
);

class FavoriteFiltersNotifier extends StateNotifier<Set<String>> {
  FavoriteFiltersNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    state = await ProjectDatabase.instance.fetchFavoriteFilterIds();
  }

  Future<void> toggle(String filterId) async {
    final exists = state.contains(filterId);
    final updated = {...state};
    if (exists) {
      updated.remove(filterId);
    } else {
      updated.add(filterId);
    }
    state = updated;
    await ProjectDatabase.instance.toggleFavoriteFilter(filterId, !exists);
  }
}
