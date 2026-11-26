import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../data/local_database/project_database.dart';
import '../../data/models/edit_state.dart';
import '../../data/models/project_model.dart';
import '../../services/ads_service/admob_service.dart';
import '../../services/image_service/photo_import_service.dart';
import '../collage/collage_maker_screen.dart';
import '../editor/editor_screen.dart';
import '../projects/projects_screen.dart';
import '../settings/settings_screen.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() =>
      _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  bool _importing = false;

  Future<void> _pickAndOpenEditor({
    EditorTab tab = EditorTab.adjust,
    String? aiTool,
  }) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final info = await PhotoImportService.instance.pickSinglePhoto();
      if (info == null) return;

      final now = DateTime.now();
      final project = PhotoProject(
        id: 'proj_${now.microsecondsSinceEpoch}',
        name: 'Edit ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        sourceImagePath: info.filePath,
        editState: const EditState(),
        width: info.width,
        height: info.height,
        fileSizeBytes: info.fileSizeBytes,
        isDraft: true,
        createdAt: now,
        updatedAt: now,
      );

      await ref.read(projectsProvider.notifier).saveProject(project);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            project: project,
            initialTab: tab,
            initialAiTool: aiTool,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _openAiToolsSheet(AppStrings s) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.aiTools,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.person_remove_outlined, size: 18),
                    label: Text(s.bgRemover),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickAndOpenEditor(
                        tab: EditorTab.ai,
                        aiTool: 'bg_remove',
                      );
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(s.enhancer),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickAndOpenEditor(tab: EditorTab.ai, aiTool: 'enhance');
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.face_retouching_natural, size: 18),
                    label: Text(s.faceRetouch),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickAndOpenEditor(tab: EditorTab.ai, aiTool: 'retouch');
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.blur_on, size: 18),
                    label: Text(s.portraitBlur),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickAndOpenEditor(
                        tab: EditorTab.ai,
                        aiTool: 'portrait_blur',
                      );
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.cleaning_services, size: 18),
                    label: Text(s.objectEraser),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickAndOpenEditor(
                        tab: EditorTab.retouch,
                        aiTool: 'object_eraser',
                      );
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.history_edu, size: 18),
                    label: const Text('Photo Restoration'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickAndOpenEditor(tab: EditorTab.ai, aiTool: 'restore');
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.palette_outlined, size: 18),
                    label: const Text('Photo Colorization'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickAndOpenEditor(tab: EditorTab.ai, aiTool: 'colorize');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final s = AppStrings(settings.languageCode);
    final projectsAsync = ref.watch(projectsProvider);

    final quickTools = <(String, IconData, Color, VoidCallback)>[
      (
        s.bgRemover,
        Icons.person_remove_outlined,
        AppTokens.accentCyan,
        () => _pickAndOpenEditor(tab: EditorTab.ai, aiTool: 'bg_remove'),
      ),
      (
        s.enhancer,
        Icons.auto_awesome,
        AppTokens.primaryBlue,
        () => _pickAndOpenEditor(tab: EditorTab.ai, aiTool: 'enhance'),
      ),
      (
        s.faceRetouch,
        Icons.face_retouching_natural,
        AppTokens.accentViolet,
        () => _pickAndOpenEditor(tab: EditorTab.ai, aiTool: 'retouch'),
      ),
      (
        s.portraitBlur,
        Icons.blur_on,
        const Color(0xFF38BDF8),
        () => _pickAndOpenEditor(tab: EditorTab.ai, aiTool: 'portrait_blur'),
      ),
      (
        s.objectEraser,
        Icons.cleaning_services,
        AppTokens.warningAmber,
        () => _pickAndOpenEditor(
          tab: EditorTab.retouch,
          aiTool: 'object_eraser',
        ),
      ),
      (
        s.filtersEffects,
        Icons.filter_vintage,
        const Color(0xFFF472B6),
        () => _pickAndOpenEditor(tab: EditorTab.filters),
      ),
      (
        s.collageMaker,
        Icons.grid_view_rounded,
        AppTokens.successGreen,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CollageMakerScreen()),
        ),
      ),
      (
        s.galleryImport,
        Icons.photo_library_outlined,
        const Color(0xFFA78BFA),
        () => _pickAndOpenEditor(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppTokens.brandGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_fix_high, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.appName,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    s.offlineBadge,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTokens.successGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_importing) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Primary Hero Actions: Edit Photo & AI Photo Tools
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickAndOpenEditor(),
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: AppTokens.brandGradient,
                            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.add_photo_alternate,
                                  color: Colors.white, size: 28),
                              const SizedBox(height: 12),
                              Text(
                                s.editPhoto,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'Pro Studio',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _openAiToolsSheet(s),
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: AppTokens.aiGradient,
                            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.psychology,
                                  color: Colors.white, size: 28),
                              const SizedBox(height: 12),
                              Text(
                                s.aiTools,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'On-Device ML',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.92,
                  children: [
                    for (final (title, icon, color, onTap) in quickTools)
                      InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icon, color: color, size: 24),
                                const SizedBox(height: 6),
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProjectsScreen(
                              initialTab: ProjectFilterTab.all,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.history),
                        label: Text(s.recentProjects),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProjectsScreen(
                              initialTab: ProjectFilterTab.favorites,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.favorite_border),
                        label: Text(s.favoriteEdits),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                projectsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (list) {
                    if (list.isEmpty) return const SizedBox.shrink();
                    final recent = list.take(6).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.recentProjects,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 108,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: recent.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 10),
                            itemBuilder: (_, i) {
                              final proj = recent[i];
                              final exists =
                                  File(proj.sourceImagePath).existsSync();
                              return GestureDetector(
                                onTap: exists
                                    ? () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                EditorScreen(project: proj),
                                          ),
                                        )
                                    : null,
                                child: SizedBox(
                                  width: 90,
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: exists
                                              ? Image.file(
                                                  File(proj.sourceImagePath),
                                                  width: 90,
                                                  fit: BoxFit.cover,
                                                  cacheWidth: 180,
                                                )
                                              : const ColoredBox(
                                                  color: Colors.black26,
                                                  child: Icon(Icons.broken_image),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        proj.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SafeBannerAdWidget(),
        ],
      ),
    );
  }
}
