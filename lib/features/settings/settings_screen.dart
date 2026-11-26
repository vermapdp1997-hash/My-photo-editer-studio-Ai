import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/performance/performance_profile.dart';
import '../../data/local_database/project_database.dart';
import '../../data/models/project_model.dart';
import '../../services/ai_service/local_ai_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _cacheBytes = 0;
  List<AiModelStatus> _models = [];
  bool _loadingInfo = true;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    final cache = await ref.read(projectsProvider.notifier).calculateCacheBytes();
    final models = await LocalAiService.instance.inspectAllModels();
    if (mounted) {
      setState(() {
        _cacheBytes = cache;
        _models = models;
        _loadingInfo = false;
      });
    }
  }

  Future<void> _showLicensesDialog() async {
    String text;
    try {
      text = await rootBundle.loadString('assets/licenses/MODEL_LICENSES.txt');
    } catch (_) {
      text = 'Real-ESRGAN (BSD-3-Clause), AOT-GAN (MIT), DDColor (Apache-2.0), Google ML Kit.';
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI Model Licenses & Attribution'),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'My Photo Editor AI processes 100% of your photos locally on your Android device.\n\n'
            '• No account or login required.\n'
            '• Zero cloud servers or remote photo uploads.\n'
            '• Core editing and on-device AI work in Airplane Mode.\n'
            '• Optional Google AdMob ads never receive your photos or editing data.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final strings = AppStrings(settings.languageCode);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Appearance & Language',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => notifier.setThemeMode(s.first),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('English')),
                      ButtonSegment(value: 'hi', label: Text('हिन्दी')),
                    ],
                    selected: {settings.languageCode},
                    onSelectionChanged: (s) => notifier.setLanguage(s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Performance Profile',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in PerformanceMode.values)
                        ChoiceChip(
                          label: Text(m.name.toUpperCase()),
                          selected: settings.performanceMode == m,
                          onSelected: (_) => notifier.setPerformanceMode(m),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text('Default Export Quality: ${settings.exportQuality}%'),
                  Slider(
                    value: settings.exportQuality.toDouble(),
                    min: 50,
                    max: 100,
                    divisions: 50,
                    onChanged: (v) => notifier.setExportQuality(v.round()),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<ExportFormat>(
                    segments: const [
                      ButtonSegment(value: ExportFormat.jpg, label: Text('JPG')),
                      ButtonSegment(value: ExportFormat.png, label: Text('PNG')),
                      ButtonSegment(value: ExportFormat.webp, label: Text('WebP')),
                    ],
                    selected: {settings.defaultFormat},
                    onSelectionChanged: (s) => notifier.setDefaultFormat(s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Local AI Model Management',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: _showLicensesDialog,
                        child: const Text('Licenses'),
                      ),
                    ],
                  ),
                  if (_loadingInfo)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    )
                  else
                    for (final m in _models)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          m.available ? Icons.verified : Icons.warning_amber,
                          color: m.available
                              ? AppTokens.successGreen
                              : AppTokens.warningAmber,
                        ),
                        title: Text(m.title),
                        subtitle: Text(
                          '${m.license} • ${m.sizeBytes > 0 ? "${(m.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB" : m.sha256Short}',
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Clear Temporary Cache'),
                  subtitle: Text(
                    'Using ${(_cacheBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                  ),
                  onTap: () async {
                    await ref
                        .read(projectsProvider.notifier)
                        .clearTemporaryCache();
                    await _loadDiagnostics();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Temporary cache cleared.')),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  onTap: _showPrivacyDialog,
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('About My Photo Editor AI'),
                  subtitle: Text('Version 1.0.0 • 100% Offline Local Processing'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
