import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/performance/performance_profile.dart';
import '../../data/local_database/project_database.dart';
import '../../data/models/edit_state.dart';
import '../../data/models/project_model.dart';
import '../../services/ai_service/local_ai_service.dart';
import '../../services/image_service/image_pipeline_service.dart';
import '../../services/image_service/photo_import_service.dart';
import '../export/export_screen.dart';
import '../filters/filter_catalog.dart';

enum EditorTab {
  ai,
  adjust,
  filters,
  crop,
  retouch,
  effects,
  text,
  background,
  tools,
}

class EditorScreen extends ConsumerStatefulWidget {
  final PhotoProject project;
  final EditorTab initialTab;
  final String? initialAiTool;

  const EditorScreen({
    super.key,
    required this.project,
    this.initialTab = EditorTab.adjust,
    this.initialAiTool,
  });

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late PhotoProject _project;
  late EditState _state;
  final List<EditState> _history = [];
  int _historyIdx = 0;

  late EditorTab _activeTab;
  bool _advancedAdjust = false;
  FilterCategory? _selectedFilterCat;
  bool _showFavoriteFiltersOnly = false;

  Uint8List? _previewBytes;
  bool _rendering = false;
  bool _renderQueued = false;
  Timer? _debounce;

  bool _holdOriginal = false;
  bool _splitCompare = false;
  double _splitRatio = 0.5;

  bool _aiBusy = false;
  String _aiBusyMessage = '';
  bool _aiCancelled = false;

  RetouchToolType _retouchTool = RetouchToolType.healing;
  double _brushSize = 0.045;
  double _brushIntensity = 0.8;
  List<Offset> _activeStrokePts = [];

  final TransformationController _zoomCtrl = TransformationController();
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _state = widget.project.editState;
    _history.add(_state);
    _activeTab = widget.initialTab;
    _scheduleRender(immediate: true);

    if (widget.initialAiTool != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerInitialAiTool(widget.initialAiTool!);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _zoomCtrl.dispose();
    super.dispose();
  }

  void _triggerInitialAiTool(String tool) {
    switch (tool) {
      case 'bg_remove':
        _runAiBackgroundRemoval();
      case 'enhance':
        _runAiEnhancer(restoreMode: false);
      case 'retouch':
        _runAiFaceRetouch();
      case 'portrait_blur':
        _runAiPortraitBlur();
      case 'object_eraser':
        setState(() {
          _activeTab = EditorTab.retouch;
          _retouchTool = RetouchToolType.aiObjectMask;
        });
        _showInfo('Brush over unwanted objects, then tap "Erase with AI".');
      case 'restore':
        _runAiEnhancer(restoreMode: true);
      case 'colorize':
        _runAiColorize();
    }
  }

  void _commitState(EditState next, {bool recordHistory = true}) {
    setState(() {
      _state = next;
      if (recordHistory) {
        if (_historyIdx < _history.length - 1) {
          _history.removeRange(_historyIdx + 1, _history.length);
        }
        _history.add(next);
        if (_history.length > 30) {
          _history.removeAt(0);
        } else {
          _historyIdx = _history.length - 1;
        }
      }
    });
    _scheduleRender();
  }

  void _undo() {
    if (_historyIdx <= 0) return;
    setState(() {
      _historyIdx--;
      _state = _history[_historyIdx];
    });
    _scheduleRender(immediate: true);
  }

  void _redo() {
    if (_historyIdx >= _history.length - 1) return;
    setState(() {
      _historyIdx++;
      _state = _history[_historyIdx];
    });
    _scheduleRender(immediate: true);
  }

  void _scheduleRender({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      _renderPreview();
    } else {
      _debounce = Timer(const Duration(milliseconds: 80), _renderPreview);
    }
  }

  Future<void> _renderPreview() async {
    if (_rendering) {
      _renderQueued = true;
      return;
    }
    _rendering = true;
    try {
      final perf = PerformanceConfig.resolve(
        ref.read(settingsProvider).performanceMode,
      );
      final bytes = await ImagePipelineService.instance.renderPreviewPng(
        _project.sourceImagePath,
        _state,
        maxDimension: perf.previewMaxDimension,
      );
      if (mounted) {
        setState(() => _previewBytes = bytes);
      }
    } catch (e) {
      if (mounted) _showInfo('Preview error: $e');
    } finally {
      _rendering = false;
      if (_renderQueued) {
        _renderQueued = false;
        _renderPreview();
      }
    }
  }

  Future<void> _saveDraftSilently() async {
    final updated = _project.copyWith(
      editState: _state,
      updatedAt: DateTime.now(),
    );
    _project = updated;
    await ref.read(projectsProvider.notifier).saveProject(updated);
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _runAiBackgroundRemoval() async {
    setState(() {
      _aiBusy = true;
      _aiBusyMessage = 'Running on-device person segmentation...';
      _aiCancelled = false;
    });
    try {
      final maskPath = await LocalAiService.instance
          .generatePersonSegmentationMask(_project.sourceImagePath);
      if (_aiCancelled) return;
      _commitState(
        _state.copyWith(
          aiMaskPath: maskPath,
          bgReplacementType: BackgroundReplacementType.transparent,
        ),
      );
      setState(() => _activeTab = EditorTab.background);
    } catch (e) {
      _showInfo(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _runAiPortraitBlur() async {
    setState(() {
      _aiBusy = true;
      _aiBusyMessage = 'Detecting subject for portrait depth blur...';
      _aiCancelled = false;
    });
    try {
      final maskPath = _state.aiMaskPath ??
          await LocalAiService.instance
              .generatePersonSegmentationMask(_project.sourceImagePath);
      if (_aiCancelled) return;
      _commitState(
        _state.copyWith(
          aiMaskPath: maskPath,
          bgReplacementType: BackgroundReplacementType.none,
          portraitBlurIntensity:
              _state.portraitBlurIntensity > 0 ? _state.portraitBlurIntensity : 0.65,
        ),
      );
    } catch (e) {
      _showInfo(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _runAiFaceRetouch() async {
    setState(() {
      _aiBusy = true;
      _aiBusyMessage = 'Detecting faces locally via ML Kit...';
      _aiCancelled = false;
    });
    try {
      final outPath = await LocalAiService.instance.retouchFacesOnDevice(
        _state.aiProcessedImagePath ?? _project.sourceImagePath,
        intensity: 0.65,
      );
      if (_aiCancelled) return;
      _commitState(_state.copyWith(aiProcessedImagePath: outPath));
      _showInfo('On-device face retouch applied.');
    } catch (e) {
      _showInfo(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _runAiEnhancer({required bool restoreMode}) async {
    setState(() {
      _aiBusy = true;
      _aiBusyMessage = restoreMode
          ? 'Restoring photo via local Real-ESRGAN...'
          : 'Enhancing clarity via local Real-ESRGAN...';
      _aiCancelled = false;
    });
    try {
      final perf = PerformanceConfig.resolve(
        ref.read(settingsProvider).performanceMode,
      );
      final outPath = await LocalAiService.instance.enhanceOrRestoreWithRealEsrgan(
        _state.aiProcessedImagePath ?? _project.sourceImagePath,
        perf,
        restoreMode: restoreMode,
      );
      if (_aiCancelled) return;
      _commitState(_state.copyWith(aiProcessedImagePath: outPath));
      _showInfo(restoreMode ? 'Photo restored locally!' : 'AI Enhancement applied!');
    } catch (e) {
      _showInfo(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _runAiObjectErase() async {
    final maskStrokes = _state.retouchStrokes
        .where((s) => s.tool == RetouchToolType.aiObjectMask)
        .toList();
    if (maskStrokes.isEmpty) {
      _showInfo('Brush over the object you want to erase first.');
      return;
    }

    setState(() {
      _aiBusy = true;
      _aiBusyMessage = 'Running local AOT-GAN inpainting...';
      _aiCancelled = false;
    });
    try {
      final perf = PerformanceConfig.resolve(
        ref.read(settingsProvider).performanceMode,
      );
      final outPath = await LocalAiService.instance.eraseObjectWithAotGan(
        _state.aiProcessedImagePath ?? _project.sourceImagePath,
        maskStrokes,
        perf,
      );
      if (_aiCancelled) return;
      final remaining = _state.retouchStrokes
          .where((s) => s.tool != RetouchToolType.aiObjectMask)
          .toList();
      _commitState(
        _state.copyWith(
          aiProcessedImagePath: outPath,
          retouchStrokes: remaining,
        ),
      );
      _showInfo('Object erased locally!');
    } catch (e) {
      _showInfo(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _runAiColorize() async {
    setState(() {
      _aiBusy = true;
      _aiBusyMessage = 'Colorizing via local DDColor model...';
      _aiCancelled = false;
    });
    try {
      final perf = PerformanceConfig.resolve(
        ref.read(settingsProvider).performanceMode,
      );
      final outPath = await LocalAiService.instance.colorizeWithDdColor(
        _state.aiProcessedImagePath ?? _project.sourceImagePath,
        perf,
      );
      if (_aiCancelled) return;
      _commitState(_state.copyWith(aiProcessedImagePath: outPath));
      _showInfo('Photo colorized locally!');
    } catch (e) {
      _showInfo(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }
  void _onBrushStart(Offset localPos) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    if (size.width <= 0 || size.height <= 0) return;
    setState(() {
      _activeStrokePts = [
        Offset(
          (localPos.dx / size.width).clamp(0.0, 1.0),
          (localPos.dy / size.height).clamp(0.0, 1.0),
        ),
      ];
    });
  }

  void _onBrushUpdate(Offset localPos) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    if (size.width <= 0 || size.height <= 0) return;
    setState(() {
      _activeStrokePts.add(
        Offset(
          (localPos.dx / size.width).clamp(0.0, 1.0),
          (localPos.dy / size.height).clamp(0.0, 1.0),
        ),
      );
    });
  }

  void _onBrushEnd() {
    if (_activeStrokePts.isEmpty) return;
    final stroke = RetouchStroke(
      tool: _retouchTool,
      normalizedPoints: List.of(_activeStrokePts),
      brushSize: _brushSize,
      intensity: _brushIntensity,
    );
    _activeStrokePts = [];
    _commitState(
      _state.copyWith(retouchStrokes: [..._state.retouchStrokes, stroke]),
    );
  }

  Future<void> _showAddTextDialog() async {
    final ctrl = TextEditingController();
    int selectedColor = 0xFFFFFFFF;
    String fontFamily = 'Sans';
    bool hasShadow = true;
    double fontSize = 28;

    const palette = [
      0xFFFFFFFF,
      0xFF000000,
      0xFF4F8CFF,
      0xFF22D3EE,
      0xFFF59E0B,
      0xFFEF4444,
      0xFF22C55E,
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Add Text Layer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Enter text',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in palette)
                      GestureDetector(
                        onTap: () => setDlg(() => selectedColor = c),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(c),
                          child: selectedColor == c
                              ? const Icon(Icons.check, size: 16, color: Colors.grey)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Sans', label: Text('Sans')),
                    ButtonSegment(value: 'Serif', label: Text('Serif')),
                    ButtonSegment(value: 'Mono', label: Text('Mono')),
                  ],
                  selected: {fontFamily},
                  onSelectionChanged: (s) => setDlg(() => fontFamily = s.first),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Drop Shadow'),
                  value: hasShadow,
                  onChanged: (v) => setDlg(() => hasShadow = v),
                ),
                Slider(
                  value: fontSize,
                  min: 14,
                  max: 64,
                  onChanged: (v) => setDlg(() => fontSize = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    final textVal = ctrl.text.trim();
    ctrl.dispose();
    if (confirmed == true && textVal.isNotEmpty) {
      final layer = TextLayerItem(
        id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
        text: textVal,
        colorValue: selectedColor,
        fontFamily: fontFamily,
        hasShadow: hasShadow,
        fontSize: fontSize,
      );
      _commitState(
        _state.copyWith(textLayers: [..._state.textLayers, layer]),
      );
    }
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: const TextStyle(fontSize: 12.5)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Basic (11)')),
              ButtonSegment(value: true, label: Text('Advanced (21)')),
            ],
            selected: {_advancedAdjust},
            onSelectionChanged: (s) => setState(() => _advancedAdjust = s.first),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: !_advancedAdjust
                ? [
                    _buildSlider('Brightness', _state.brightness, -1, 1,
                        (v) => _commitState(_state.copyWith(brightness: v))),
                    _buildSlider('Contrast', _state.contrast, -0.8, 1,
                        (v) => _commitState(_state.copyWith(contrast: v))),
                    _buildSlider('Exposure', _state.exposure, -1.5, 1.5,
                        (v) => _commitState(_state.copyWith(exposure: v))),
                    _buildSlider('Saturation', _state.saturation, -1, 1,
                        (v) => _commitState(_state.copyWith(saturation: v))),
                    _buildSlider('Vibrance', _state.vibrance, -1, 1,
                        (v) => _commitState(_state.copyWith(vibrance: v))),
                    _buildSlider('Temperature', _state.temperature, -1, 1,
                        (v) => _commitState(_state.copyWith(temperature: v))),
                    _buildSlider('Tint', _state.tint, -1, 1,
                        (v) => _commitState(_state.copyWith(tint: v))),
                    _buildSlider('Highlights', _state.highlights, -1, 1,
                        (v) => _commitState(_state.copyWith(highlights: v))),
                    _buildSlider('Shadows', _state.shadows, -1, 1,
                        (v) => _commitState(_state.copyWith(shadows: v))),
                    _buildSlider('Whites', _state.whites, -1, 1,
                        (v) => _commitState(_state.copyWith(whites: v))),
                    _buildSlider('Blacks', _state.blacks, -1, 1,
                        (v) => _commitState(_state.copyWith(blacks: v))),
                  ]
                : [
                    _buildSlider('HSL Hue', _state.hslHue, -180, 180,
                        (v) => _commitState(_state.copyWith(hslHue: v))),
                    _buildSlider('HSL Sat', _state.hslSaturation, -1, 1,
                        (v) => _commitState(_state.copyWith(hslSaturation: v))),
                    _buildSlider('HSL Light', _state.hslLightness, -1, 1,
                        (v) => _commitState(_state.copyWith(hslLightness: v))),
                    _buildSlider('Red RGB', _state.redGain, -0.8, 0.8,
                        (v) => _commitState(_state.copyWith(redGain: v))),
                    _buildSlider('Green RGB', _state.greenGain, -0.8, 0.8,
                        (v) => _commitState(_state.copyWith(greenGain: v))),
                    _buildSlider('Blue RGB', _state.blueGain, -0.8, 0.8,
                        (v) => _commitState(_state.copyWith(blueGain: v))),
                    _buildSlider('Color Balance', _state.colorBalanceWarmth, -1, 1,
                        (v) => _commitState(_state.copyWith(colorBalanceWarmth: v))),
                    _buildSlider('Curve Shadows', _state.curveShadows, -0.5, 0.5,
                        (v) => _commitState(_state.copyWith(curveShadows: v))),
                    _buildSlider('Curve Mids', _state.curveMidtones, -0.5, 0.5,
                        (v) => _commitState(_state.copyWith(curveMidtones: v))),
                    _buildSlider('Curve Highs', _state.curveHighlights, -0.5, 0.5,
                        (v) => _commitState(_state.copyWith(curveHighlights: v))),
                    _buildSlider('Selective Color', _state.selectiveWarmShift, -1, 1,
                        (v) => _commitState(_state.copyWith(selectiveWarmShift: v))),
                    _buildSlider('Color Grading', _state.colorGradingTint, -1, 1,
                        (v) => _commitState(_state.copyWith(colorGradingTint: v))),
                    _buildSlider('Clarity', _state.clarity, 0, 1,
                        (v) => _commitState(_state.copyWith(clarity: v))),
                    _buildSlider('Sharpness', _state.sharpness, 0, 1,
                        (v) => _commitState(_state.copyWith(sharpness: v))),
                    _buildSlider('Noise Reduce', _state.noiseReduction, 0, 1,
                        (v) => _commitState(_state.copyWith(noiseReduction: v))),
                    _buildSlider('Vignette', _state.vignette, 0, 1,
                        (v) => _commitState(_state.copyWith(vignette: v))),
                    _buildSlider('Grain', _state.grain, 0, 1,
                        (v) => _commitState(_state.copyWith(grain: v))),
                    _buildSlider('Fade', _state.fade, 0, 0.7,
                        (v) => _commitState(_state.copyWith(fade: v))),
                    _buildSlider('Blur', _state.blur, 0, 1,
                        (v) => _commitState(_state.copyWith(blur: v))),
                    _buildSlider('Tilt X', _state.perspectiveX, -0.3, 0.3,
                        (v) => _commitState(_state.copyWith(perspectiveX: v))),
                    _buildSlider('Tilt Y', _state.perspectiveY, -0.3, 0.3,
                        (v) => _commitState(_state.copyWith(perspectiveY: v))),
                  ],
          ),
        ),
      ],
    );
  }

  Widget _buildFiltersPanel() {
    final favIds = ref.watch(favoriteFiltersProvider);
    final list = FilterCatalog.all.where((f) {
      if (_showFavoriteFiltersOnly && !favIds.contains(f.id)) return false;
      if (_selectedFilterCat != null && f.category != _selectedFilterCat) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All (105+)'),
                selected: _selectedFilterCat == null && !_showFavoriteFiltersOnly,
                onSelected: (_) => setState(() {
                  _selectedFilterCat = null;
                  _showFavoriteFiltersOnly = false;
                }),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Favorites'),
                selected: _showFavoriteFiltersOnly,
                onSelected: (_) => setState(() {
                  _showFavoriteFiltersOnly = !_showFavoriteFiltersOnly;
                  _selectedFilterCat = null;
                }),
              ),
              for (final c in FilterCategory.values) ...[
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(c.label),
                  selected: _selectedFilterCat == c && !_showFavoriteFiltersOnly,
                  onSelected: (_) => setState(() {
                    _selectedFilterCat = c;
                    _showFavoriteFiltersOnly = false;
                  }),
                ),
              ],
            ],
          ),
        ),
        if (_state.filterId != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _buildSlider(
              'Intensity',
              _state.filterIntensity,
              0,
              1,
              (v) => _commitState(_state.copyWith(filterIntensity: v)),
            ),
          ),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: list.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Original'),
                    selected: _state.filterId == null,
                    onSelected: (_) =>
                        _commitState(_state.copyWith(clearFilter: true)),
                  ),
                );
              }
              final f = list[i - 1];
              final isFav = favIds.contains(f.id);
              final isSelected = _state.filterId == f.id;
              return Container(
                width: 118,
                margin: const EdgeInsets.only(right: 8),
                child: Card(
                  color: isSelected
                      ? AppTokens.primaryBlue.withValues(alpha: 0.25)
                      : null,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _commitState(_state.copyWith(filterId: f.id)),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                f.category.label.split(' ').first,
                                style: const TextStyle(fontSize: 10),
                              ),
                              GestureDetector(
                                onTap: () => ref
                                    .read(favoriteFiltersProvider.notifier)
                                    .toggle(f.id),
                                child: Icon(
                                  isFav ? Icons.favorite : Icons.favorite_border,
                                  size: 16,
                                  color: isFav ? AppTokens.errorRed : null,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            f.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAiPanel() {
    final actions = <(String, IconData, VoidCallback)>[
      ('BG Remover', Icons.person_remove_outlined, _runAiBackgroundRemoval),
      ('Enhancer', Icons.auto_awesome, () => _runAiEnhancer(restoreMode: false)),
      ('Face Retouch', Icons.face_retouching_natural, _runAiFaceRetouch),
      ('Portrait Blur', Icons.blur_on, _runAiPortraitBlur),
      (
        'Object Eraser',
        Icons.cleaning_services,
        () {
          setState(() {
            _activeTab = EditorTab.retouch;
            _retouchTool = RetouchToolType.aiObjectMask;
          });
          _showInfo('Brush over object, then tap Erase with AI.');
        }
      ),
      ('Restore Old', Icons.history_edu, () => _runAiEnhancer(restoreMode: true)),
      ('Colorize B&W', Icons.palette_outlined, _runAiColorize),
      (
        'Reset AI',
        Icons.restart_alt,
        () => _commitState(_state.copyWith(clearAiProcessed: true))
      ),
    ];

    return GridView.count(
      crossAxisCount: 4,
      padding: const EdgeInsets.all(10),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.05,
      children: [
        for (final (label, icon, cb) in actions)
          InkWell(
            onTap: _aiBusy ? null : cb,
            borderRadius: BorderRadius.circular(14),
            child: Card(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: AppTokens.accentCyan, size: 22),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCropPanel() {
    void setAspect(String label, double? ratio) {
      if (ratio == null) {
        _commitState(
          _state.copyWith(
            cropLeft: 0,
            cropTop: 0,
            cropRight: 1,
            cropBottom: 1,
            aspectRatioLabel: 'Free',
          ),
        );
        return;
      }
      final imgRatio = _project.width / _project.height;
      double w = 1, h = 1;
      if (imgRatio > ratio) {
        w = (ratio / imgRatio).clamp(0.1, 1.0);
      } else {
        h = (imgRatio / ratio).clamp(0.1, 1.0);
      }
      final l = (1.0 - w) / 2.0;
      final t = (1.0 - h) / 2.0;
      _commitState(
        _state.copyWith(
          cropLeft: l,
          cropTop: t,
          cropRight: l + w,
          cropBottom: t + h,
          aspectRatioLabel: label,
        ),
      );
    }

    final ratios = <(String, double?)>[
      ('Free', null),
      ('1:1', 1.0),
      ('4:5', 4 / 5),
      ('3:4', 3 / 4),
      ('9:16', 9 / 16),
      ('16:9', 16 / 9),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final (lbl, r) in ratios)
              ChoiceChip(
                label: Text(lbl),
                selected: _state.aspectRatioLabel == lbl,
                onSelected: (_) => setAspect(lbl, r),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton.icon(
              onPressed: () => _commitState(
                _state.copyWith(
                  rotationQuarterTurns: (_state.rotationQuarterTurns + 1) % 4,
                ),
              ),
              icon: const Icon(Icons.rotate_right),
              label: const Text('Rotate 90°'),
            ),
            OutlinedButton.icon(
              onPressed: () => _commitState(
                _state.copyWith(flipHorizontal: !_state.flipHorizontal),
              ),
              icon: const Icon(Icons.flip),
              label: const Text('Flip H'),
            ),
            OutlinedButton.icon(
              onPressed: () => _commitState(
                _state.copyWith(flipVertical: !_state.flipVertical),
              ),
              icon: const Icon(Icons.swap_vert),
              label: const Text('Flip V'),
            ),
          ],
        ),
        _buildSlider(
          'Straighten',
          _state.straightenDegrees,
          -15,
          15,
          (v) => _commitState(_state.copyWith(straightenDegrees: v)),
        ),
      ],
    );
  }

  Widget _buildRetouchPanel() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final t in [
              (RetouchToolType.healing, 'Healing'),
              (RetouchToolType.spotRemoval, 'Spot Fix'),
              (RetouchToolType.manualEraser, 'Eraser'),
              (RetouchToolType.selectiveBlur, 'Blur Brush'),
              (RetouchToolType.aiObjectMask, 'AI Object Mask'),
            ])
              ChoiceChip(
                label: Text(t.$2),
                selected: _retouchTool == t.$1,
                onSelected: (_) => setState(() => _retouchTool = t.$1),
              ),
          ],
        ),
        _buildSlider('Brush Size', _brushSize, 0.015, 0.12,
            (v) => setState(() => _brushSize = v)),
        _buildSlider('Strength', _brushIntensity, 0.2, 1.0,
            (v) => setState(() => _brushIntensity = v)),
        Row(
          children: [
            if (_retouchTool == RetouchToolType.aiObjectMask)
              Expanded(
                child: FilledButton.icon(
                  onPressed: _aiBusy ? null : _runAiObjectErase,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Erase with AI'),
                ),
              ),
            if (_state.retouchStrokes.isNotEmpty) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  final list = [..._state.retouchStrokes]..removeLast();
                  _commitState(_state.copyWith(retouchStrokes: list));
                },
                child: const Text('Undo Stroke'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildEffectsPanel() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final o in ['none', 'bokeh', 'sunflare', 'dust', 'prism'])
              ChoiceChip(
                label: Text('Overlay: $o'),
                selected: _state.overlayStyle == o,
                onSelected: (_) =>
                    _commitState(_state.copyWith(overlayStyle: o)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final f in ['none', 'classic', 'polaroid', 'neon', 'film'])
              ChoiceChip(
                label: Text('Frame: $f'),
                selected: _state.frameStyle == f,
                onSelected: (_) => _commitState(_state.copyWith(frameStyle: f)),
              ),
          ],
        ),
        _buildSlider('Border Size', _state.borderWidth, 0, 1,
            (v) => _commitState(_state.copyWith(borderWidth: v))),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked =
                      await PhotoImportService.instance.pickSinglePhoto();
                  if (picked != null) {
                    _commitState(
                      _state.copyWith(doubleExposurePath: picked.filePath),
                    );
                  }
                },
                icon: const Icon(Icons.layers),
                label: const Text('Double Exposure'),
              ),
            ),
            if (_state.doubleExposurePath != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _commitState(
                  _state.copyWith(clearDoubleExposure: true),
                ),
              ),
            ],
          ],
        ),
        if (_state.doubleExposurePath != null)
          _buildSlider(
            'Blend Opacity',
            _state.doubleExposureOpacity,
            0.1,
            0.9,
            (v) => _commitState(_state.copyWith(doubleExposureOpacity: v)),
          ),
      ],
    );
  }

  Widget _buildTextAndStickersPanel() {
    const stickers = ['✨', '❤️', '🔥', '🌟', '🎉', '🌸', '😎', '👑', '📷', '🦋'];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: _showAddTextDialog,
              icon: const Icon(Icons.text_fields),
              label: const Text('Add Text'),
            ),
            const SizedBox(width: 10),
            if (_state.textLayers.isNotEmpty || _state.stickerLayers.isNotEmpty)
              OutlinedButton(
                onPressed: () => _commitState(
                  _state.copyWith(textLayers: [], stickerLayers: []),
                ),
                child: const Text('Clear Layers'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final s in stickers)
              ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 20)),
                onPressed: () {
                  final item = StickerLayerItem(
                    id: 'stk_${DateTime.now().microsecondsSinceEpoch}',
                    symbol: s,
                  );
                  _commitState(
                    _state.copyWith(
                      stickerLayers: [..._state.stickerLayers, item],
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Tip: Drag any text or sticker directly on the photo canvas.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildBackgroundPanel() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: _aiBusy ? null : _runAiBackgroundRemoval,
              child: const Text('Auto Cutout (ML Kit)'),
            ),
            ChoiceChip(
              label: const Text('Original'),
              selected:
                  _state.bgReplacementType == BackgroundReplacementType.none,
              onSelected: (_) => _commitState(
                _state.copyWith(
                  bgReplacementType: BackgroundReplacementType.none,
                ),
              ),
            ),
            ChoiceChip(
              label: const Text('Transparent PNG'),
              selected: _state.bgReplacementType ==
                  BackgroundReplacementType.transparent,
              onSelected: (_) => _commitState(
                _state.copyWith(
                  bgReplacementType: BackgroundReplacementType.transparent,
                ),
              ),
            ),
            ChoiceChip(
              label: const Text('Gradient'),
              selected:
                  _state.bgReplacementType == BackgroundReplacementType.gradient,
              onSelected: (_) => _commitState(
                _state.copyWith(
                  bgReplacementType: BackgroundReplacementType.gradient,
                ),
              ),
            ),
            ActionChip(
              label: const Text('Pick BG Photo'),
              onPressed: () async {
                final picked =
                    await PhotoImportService.instance.pickSinglePhoto();
                if (picked != null) {
                  _commitState(
                    _state.copyWith(
                      bgReplacementType: BackgroundReplacementType.image,
                      bgReplacementImagePath: picked.filePath,
                    ),
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final c in [0xFF0F172A, 0xFFFFFFFF, 0xFF4F8CFF, 0xFF10B981, 0xFFF59E0B])
              GestureDetector(
                onTap: () => _commitState(
                  _state.copyWith(
                    bgReplacementType: BackgroundReplacementType.solidColor,
                    bgReplacementColor: c,
                  ),
                ),
                child: Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54),
                  ),
                ),
              ),
          ],
        ),
        _buildSlider('Edge Feather', _state.aiEdgeFeather, 0, 0.9,
            (v) => _commitState(_state.copyWith(aiEdgeFeather: v))),
        _buildSlider(
          'Portrait Blur',
          _state.portraitBlurIntensity,
          0,
          1,
          (v) => _commitState(_state.copyWith(portraitBlurIntensity: v)),
        ),
      ],
    );
  }

  Widget _buildToolsPanel() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          leading: const Icon(Icons.fit_screen),
          title: const Text('Fit Photo to Screen'),
          onTap: () => _zoomCtrl.value = Matrix4.identity(),
        ),
        ListTile(
          leading: const Icon(Icons.save_outlined),
          title: const Text('Save Draft Locally'),
          onTap: () async {
            await _saveDraftSilently();
            _showInfo('Draft saved to local SQLite.');
          },
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Image Info'),
          subtitle: Text(
            '${_project.width}x${_project.height} • ${(_project.fileSizeBytes / 1024).toStringAsFixed(0)} KB',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Reset All Edits'),
          onTap: () => _commitState(const EditState()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabItems = <(EditorTab, IconData, String)>[
      (EditorTab.ai, Icons.auto_awesome, 'AI'),
      (EditorTab.adjust, Icons.tune, 'Adjust'),
      (EditorTab.filters, Icons.filter_vintage, 'Filters'),
      (EditorTab.crop, Icons.crop, 'Crop'),
      (EditorTab.retouch, Icons.healing, 'Retouch'),
      (EditorTab.effects, Icons.layers, 'Effects'),
      (EditorTab.text, Icons.text_fields, 'Text'),
      (EditorTab.background, Icons.wallpaper, 'BG'),
      (EditorTab.tools, Icons.build_outlined, 'Tools'),
    ];

    final brushActive = _activeTab == EditorTab.retouch;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, _) {
        _saveDraftSilently();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _saveDraftSilently();
              if (context.mounted) Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: _historyIdx > 0 ? _undo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo),
              onPressed: _historyIdx < _history.length - 1 ? _redo : null,
            ),
            GestureDetector(
              onLongPressStart: (_) => setState(() => _holdOriginal = true),
              onLongPressEnd: (_) => setState(() => _holdOriginal = false),
              child: IconButton(
                tooltip: 'Hold for Original',
                icon: Icon(
                  Icons.visibility,
                  color: _holdOriginal ? AppTokens.accentCyan : null,
                ),
                onPressed: () =>
                    _showInfo('Press and hold eye icon to view original.'),
              ),
            ),
            IconButton(
              tooltip: 'Split Compare',
              icon: Icon(
                Icons.compare,
                color: _splitCompare ? AppTokens.accentCyan : null,
              ),
              onPressed: () => setState(() => _splitCompare = !_splitCompare),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: () async {
                  await _saveDraftSilently();
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExportScreen(
                        project: _project,
                        editState: _state,
                      ),
                    ),
                  );
                },
                child: const Text('Export'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  InteractiveViewer(
                    transformationController: _zoomCtrl,
                    panEnabled: !brushActive,
                    scaleEnabled: !brushActive,
                    minScale: 0.7,
                    maxScale: 5.0,
                    child: Center(
                      child: LayoutBuilder(
                        builder: (ctx, constraints) {
                          return GestureDetector(
                            key: _canvasKey,
                            onPanStart: brushActive
                                ? (d) => _onBrushStart(d.localPosition)
                                : null,
                            onPanUpdate: brushActive
                                ? (d) => _onBrushUpdate(d.localPosition)
                                : null,
                            onPanEnd: brushActive ? (_) => _onBrushEnd() : null,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_holdOriginal || _previewBytes == null)
                                  Image.file(
                                    File(_project.sourceImagePath),
                                    fit: BoxFit.contain,
                                  )
                                else if (_splitCompare)
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Image.memory(
                                        _previewBytes!,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                      ),
                                      ClipRect(
                                        clipper: _SplitClipper(_splitRatio),
                                        child: Image.file(
                                          File(_project.sourceImagePath),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Image.memory(
                                    _previewBytes!,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),

                                // Interactive Text Layers
                                for (int i = 0; i < _state.textLayers.length; i++)
                                  Positioned.fill(
                                    child: LayoutBuilder(
                                      builder: (_, box) {
                                        final t = _state.textLayers[i];
                                        return Stack(
                                          children: [
                                            Positioned(
                                              left: t.normX * box.maxWidth - 60,
                                              top: t.normY * box.maxHeight - 20,
                                              child: GestureDetector(
                                                onPanUpdate: (d) {
                                                  final list = [..._state.textLayers];
                                                  list[i] = t.copyWith(
                                                    normX: (t.normX +
                                                            d.delta.dx / box.maxWidth)
                                                        .clamp(0.05, 0.95),
                                                    normY: (t.normY +
                                                            d.delta.dy / box.maxHeight)
                                                        .clamp(0.05, 0.95),
                                                  );
                                                  _commitState(
                                                    _state.copyWith(textLayers: list),
                                                    recordHistory: false,
                                                  );
                                                },
                                                child: Text(
                                                  t.text,
                                                  style: TextStyle(
                                                    color: Color(t.colorValue),
                                                    fontSize: t.fontSize,
                                                    fontWeight: FontWeight.bold,
                                                    shadows: t.hasShadow
                                                        ? const [
                                                            Shadow(
                                                              color: Colors.black87,
                                                              blurRadius: 6,
                                                            ),
                                                          ]
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),

                                // Interactive Sticker Layers
                                for (int i = 0; i < _state.stickerLayers.length; i++)
                                  Positioned.fill(
                                    child: LayoutBuilder(
                                      builder: (_, box) {
                                        final s = _state.stickerLayers[i];
                                        return Stack(
                                          children: [
                                            Positioned(
                                              left: s.normX * box.maxWidth - 22,
                                              top: s.normY * box.maxHeight - 22,
                                              child: GestureDetector(
                                                onPanUpdate: (d) {
                                                  final list = [..._state.stickerLayers];
                                                  list[i] = s.copyWith(
                                                    normX: (s.normX +
                                                            d.delta.dx / box.maxWidth)
                                                        .clamp(0.05, 0.95),
                                                    normY: (s.normY +
                                                            d.delta.dy / box.maxHeight)
                                                        .clamp(0.05, 0.95),
                                                  );
                                                  _commitState(
                                                    _state.copyWith(stickerLayers: list),
                                                    recordHistory: false,
                                                  );
                                                },
                                                child: Text(
                                                  s.symbol,
                                                  style: TextStyle(
                                                    fontSize: 40 * s.scale,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),

                                if (_activeStrokePts.isNotEmpty)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _BrushPreviewPainter(
                                        _activeStrokePts,
                                        _retouchTool == RetouchToolType.aiObjectMask
                                            ? AppTokens.errorRed
                                            : AppTokens.accentCyan,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_splitCompare)
                    Positioned(
                      bottom: 10,
                      left: 24,
                      right: 24,
                      child: Slider(
                        value: _splitRatio,
                        onChanged: (v) => setState(() => _splitRatio = v),
                      ),
                    ),
                  if (_aiBusy)
                    ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 12),
                                Text(_aiBusyMessage),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _aiCancelled = true),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              height: 225,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              child: switch (_activeTab) {
                EditorTab.ai => _buildAiPanel(),
                EditorTab.adjust => _buildAdjustPanel(),
                EditorTab.filters => _buildFiltersPanel(),
                EditorTab.crop => _buildCropPanel(),
                EditorTab.retouch => _buildRetouchPanel(),
                EditorTab.effects => _buildEffectsPanel(),
                EditorTab.text => _buildTextAndStickersPanel(),
                EditorTab.background => _buildBackgroundPanel(),
                EditorTab.tools => _buildToolsPanel(),
              },
            ),
            Container(
              height: 62,
              color: Theme.of(context).colorScheme.surface,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final (tab, icon, label) in tabItems)
                    InkWell(
                      onTap: () => setState(() => _activeTab = tab),
                      child: Container(
                        width: 68,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 20,
                              color: _activeTab == tab
                                  ? AppTokens.primaryBlue
                                  : null,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: _activeTab == tab
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _activeTab == tab
                                    ? AppTokens.primaryBlue
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double ratio;
  const _SplitClipper(this.ratio);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * ratio.clamp(0.0, 1.0), size.height);

  @override
  bool shouldReclip(_SplitClipper old) => old.ratio != ratio;
}

class _BrushPreviewPainter extends CustomPainter {
  final List<Offset> normalizedPoints;
  final Color color;
  const _BrushPreviewPainter(this.normalizedPoints, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < normalizedPoints.length - 1; i++) {
      final a = Offset(
        normalizedPoints[i].dx * size.width,
        normalizedPoints[i].dy * size.height,
      );
      final b = Offset(
        normalizedPoints[i + 1].dx * size.width,
        normalizedPoints[i + 1].dy * size.height,
      );
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(_BrushPreviewPainter old) => true;
}
