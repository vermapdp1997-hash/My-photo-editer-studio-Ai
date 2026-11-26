import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../data/local_database/project_database.dart';
import '../../data/models/edit_state.dart';
import '../../data/models/project_model.dart';
import '../../services/ads_service/admob_service.dart';
import '../../services/export_service/export_service.dart';

class ExportScreen extends ConsumerStatefulWidget {
  final PhotoProject project;
  final EditState editState;

  const ExportScreen({
    super.key,
    required this.project,
    required this.editState,
  });

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  late ExportFormat _format;
  ExportResolutionPreset _preset = ExportResolutionPreset.original;
  late int _quality;
  final _customWCtrl = TextEditingController(text: '1920');
  final _customHCtrl = TextEditingController(text: '1080');
  bool _busy = false;
  ExportResult? _lastResult;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _format = widget.editState.bgReplacementType ==
            BackgroundReplacementType.transparent
        ? ExportFormat.png
        : settings.defaultFormat;
    _quality = settings.exportQuality;
  }

  @override
  void dispose() {
    _customWCtrl.dispose();
    _customHCtrl.dispose();
    super.dispose();
  }

  Future<void> _runExport({required bool shareAfter}) async {
    setState(() => _busy = true);
    try {
      final cw = int.tryParse(_customWCtrl.text.trim());
      final ch = int.tryParse(_customHCtrl.text.trim());

      final res = await ExportService.instance.renderExportFile(
        sourcePath: widget.project.sourceImagePath,
        state: widget.editState,
        format: _format,
        preset: _preset,
        quality: _quality,
        customWidth: cw,
        customHeight: ch,
        saveToGallery: !shareAfter,
      );

      // Mark project saved (non-draft)
      await ref.read(projectsProvider.notifier).saveProject(
            widget.project.copyWith(
              editState: widget.editState,
              isDraft: false,
              updatedAt: DateTime.now(),
            ),
          );

      if (mounted) setState(() => _lastResult = res);

      if (shareAfter) {
        await ExportService.instance.shareExportedFile(res.filePath);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Saved (${res.width}x${res.height}, ${(res.fileSizeBytes / 1024).toStringAsFixed(0)} KB) to Gallery!',
              ),
            ),
          );
        }
        await AdMobService.instance.showPostExportInterstitialIfReady();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTransparent = widget.editState.bgReplacementType ==
        BackgroundReplacementType.transparent;

    return Scaffold(
      appBar: AppBar(title: const Text('Export Photo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Output Format',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ExportFormat>(
                    segments: const [
                      ButtonSegment(value: ExportFormat.jpg, label: Text('JPG')),
                      ButtonSegment(value: ExportFormat.png, label: Text('PNG')),
                      ButtonSegment(value: ExportFormat.webp, label: Text('WebP')),
                    ],
                    selected: {_format},
                    onSelectionChanged: (s) =>
                        setState(() => _format = s.first),
                  ),
                  if (isTransparent && _format != ExportFormat.png)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Tip: Choose PNG to preserve transparent background.',
                        style: TextStyle(color: AppTokens.warningAmber),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resolution (${widget.project.width}x${widget.project.height} Original)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in ExportResolutionPreset.values)
                        ChoiceChip(
                          label: Text(switch (p) {
                            ExportResolutionPreset.original => 'Original',
                            ExportResolutionPreset.p1080 => '1080p',
                            ExportResolutionPreset.p2k => '2K',
                            ExportResolutionPreset.p4k => '4K',
                            ExportResolutionPreset.custom => 'Custom',
                          }),
                          selected: _preset == p,
                          onSelected: (_) => setState(() => _preset = p),
                        ),
                    ],
                  ),
                  if (_preset == ExportResolutionPreset.custom) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customWCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Width (px)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _customHCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Height (px)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_format != ExportFormat.png) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Compression Quality: $_quality%',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Slider(
                      value: _quality.toDouble(),
                      min: 50,
                      max: 100,
                      divisions: 50,
                      onChanged: (v) => setState(() => _quality = v.round()),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_lastResult != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.check_circle,
                  color: AppTokens.successGreen,
                ),
                title: Text(
                  'Last Export: ${_lastResult!.width}x${_lastResult!.height}',
                ),
                subtitle: Text(
                  'Size: ${(_lastResult!.fileSizeBytes / 1024).toStringAsFixed(1)} KB',
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : () => _runExport(shareAfter: false),
            icon: const Icon(Icons.save_alt),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Save to Gallery'),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _runExport(shareAfter: true),
            icon: const Icon(Icons.share),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Share Photo'),
            ),
          ),
        ],
      ),
    );
  }
}
