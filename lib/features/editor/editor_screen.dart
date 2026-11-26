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
