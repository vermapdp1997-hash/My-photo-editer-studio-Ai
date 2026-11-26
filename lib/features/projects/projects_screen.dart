import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../data/local_database/project_database.dart';
import '../../data/models/project_model.dart';
import '../editor/editor_screen.dart';

enum ProjectFilterTab { all, drafts, favorites }

class ProjectsScreen extends ConsumerStatefulWidget {
  final ProjectFilterTab initialTab;
  const ProjectsScreen({super.key, this.initialTab = ProjectFilterTab.all});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  late ProjectFilterTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  Future<void> _renameDialog(PhotoProject project) async {
    final ctrl = TextEditingController(text: project.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Project'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.trim().isNotEmpty) {
      await ref.read(projectsProvider.notifier).renameProject(project, result);
    }
  }

  Future<void> _deleteDialog(PhotoProject project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: Text('Remove "${project.name}" from local projects?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(projectsProvider.notifier).deleteProject(project.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider);
    final lang = ref.watch(settingsProvider).languageCode;
    final strings = AppStrings(lang);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tab == ProjectFilterTab.favorites
              ? strings.favoriteEdits
              : strings.recentProjects,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<ProjectFilterTab>(
              segments: const [
                ButtonSegment(value: ProjectFilterTab.all, label: Text('All')),
                ButtonSegment(value: ProjectFilterTab.drafts, label: Text('Drafts')),
                ButtonSegment(
                  value: ProjectFilterTab.favorites,
                  label: Text('Favorites'),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (set) => setState(() => _tab = set.first),
            ),
          ),
          Expanded(
            child: projectsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading projects: $err')),
              data: (allProjects) {
                final filtered = allProjects.where((p) {
                  if (_tab == ProjectFilterTab.favorites) return p.isFavorite;
                  if (_tab == ProjectFilterTab.drafts) return p.isDraft;
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _tab == ProjectFilterTab.favorites
                                ? 'No favorite edits yet'
                                : 'No saved projects yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Import a photo from the home screen to start non-destructive editing.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final proj = filtered[i];
                    final sourceExists = File(proj.sourceImagePath).existsSync();
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(10),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 60,
                            height: 60,
                            child: sourceExists
                                ? Image.file(
                                    File(proj.sourceImagePath),
                                    fit: BoxFit.cover,
                                    cacheWidth: 160,
                                  )
                                : const ColoredBox(
                                    color: Colors.black26,
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                          ),
                        ),
                        title: Text(
                          proj.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${proj.width}x${proj.height} • ${proj.isDraft ? "Draft" : "Saved"}',
                        ),
                        onTap: () {
                          if (!sourceExists) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Original source file is missing.'),
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditorScreen(project: proj),
                            ),
                          );
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                proj.isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: proj.isFavorite
                                    ? AppTokens.errorRed
                                    : null,
                              ),
                              onPressed: () => ref
                                  .read(projectsProvider.notifier)
                                  .toggleFavorite(proj),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'edit' && sourceExists) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EditorScreen(project: proj),
                                    ),
                                  );
                                } else if (action == 'rename') {
                                  await _renameDialog(proj);
                                } else if (action == 'duplicate') {
                                  await ref
                                      .read(projectsProvider.notifier)
                                      .duplicateProject(proj);
                                } else if (action == 'delete') {
                                  await _deleteDialog(proj);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Continue Editing'),
                                ),
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename'),
                                ),
                                PopupMenuItem(
                                  value: 'duplicate',
                                  child: Text('Duplicate'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
