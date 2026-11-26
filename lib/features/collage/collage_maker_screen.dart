import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/app_theme.dart';
import '../../services/image_service/photo_import_service.dart';

enum CollageLayout { twoSide, twoStack, threeGrid, fourGrid, sixGrid }

class CollageMakerScreen extends StatefulWidget {
  const CollageMakerScreen({super.key});

  @override
  State<CollageMakerScreen> createState() => _CollageMakerScreenState();
}

class _CollageMakerScreenState extends State<CollageMakerScreen> {
  final List<String> _imagePaths = [];
  CollageLayout _layout = CollageLayout.fourGrid;
  double _spacing = 8;
  double _cornerRadius = 12;
  Color _bgColor = const Color(0xFF0A0F1E);
  bool _exporting = false;

  int get _slotCount => switch (_layout) {
        CollageLayout.twoSide || CollageLayout.twoStack => 2,
        CollageLayout.threeGrid => 3,
        CollageLayout.fourGrid => 4,
        CollageLayout.sixGrid => 6,
      };

  Future<void> _pickPhotos() async {
    try {
      final picked = await PhotoImportService.instance.pickMultiplePhotos(
        limit: 6,
      );
      if (picked.isEmpty) return;
      setState(() {
        _imagePaths
          ..clear()
          ..addAll(picked.map((e) => e.filePath));
        if (_imagePaths.length <= 2) {
          _layout = CollageLayout.twoSide;
        } else if (_imagePaths.length == 3) {
          _layout = CollageLayout.threeGrid;
        } else if (_imagePaths.length <= 4) {
          _layout = CollageLayout.fourGrid;
        } else {
          _layout = CollageLayout.sixGrid;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _replaceSlot(int index) async {
    try {
      final picked = await PhotoImportService.instance.pickSinglePhoto();
      if (picked == null) return;
      setState(() {
        if (index < _imagePaths.length) {
          _imagePaths[index] = picked.filePath;
        } else {
          _imagePaths.add(picked.filePath);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _exportCollage({required bool share}) async {
    if (_imagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select photos first.')),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final paths = List<String>.from(_imagePaths);
      final layout = _layout;
      final spacing = _spacing.round() * 2;
      final bgInt = _bgColor.toARGB32();

      final jpgBytes = await Isolate.run(() async {
        const size = 1600;
        final canvas = img.Image(width: size, height: size, numChannels: 4);
        final r = (bgInt >> 16) & 0xFF;
        final g = (bgInt >> 8) & 0xFF;
        final b = bgInt & 0xFF;
        img.fill(canvas, color: img.ColorRgba8(r, g, b, 255));

        final rects = _computeRects(layout, size, spacing);
        for (int i = 0; i < rects.length; i++) {
          final rect = rects[i];
          final srcPath = paths[i % paths.length];
          final raw = img.decodeImage(await File(srcPath).readAsBytes());
          if (raw == null) continue;
          final fitted = _coverFit(
            img.bakeOrientation(raw),
            rect.width,
            rect.height,
          );
          img.compositeImage(canvas, fitted, dstX: rect.left, dstY: rect.top);
        }
        return img.encodeJpg(canvas, quality: 94);
      });

      final dir = await getTemporaryDirectory();
      final outPath = p.join(
        dir.path,
        'Collage_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(outPath).writeAsBytes(jpgBytes, flush: true);

      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(outPath)],
            text: 'Created with My Photo Editor AI Collage Maker',
          ),
        );
      } else {
        final ok = await Gal.hasAccess(toAlbum: true) ||
            await Gal.requestAccess(toAlbum: true);
        if (!ok) throw StateError('Gallery permission denied.');
        await Gal.putImage(outPath, album: 'My Photo Editor AI');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Collage saved to Gallery!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Collage export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static List<math.Rectangle<int>> _computeRects(
    CollageLayout layout,
    int size,
    int gap,
  ) {
    switch (layout) {
      case CollageLayout.twoSide:
        final w = (size - gap * 3) ~/ 2;
        final h = size - gap * 2;
        return [
          math.Rectangle(gap, gap, w, h),
          math.Rectangle(gap * 2 + w, gap, w, h),
        ];
      case CollageLayout.twoStack:
        final w = size - gap * 2;
        final h = (size - gap * 3) ~/ 2;
        return [
          math.Rectangle(gap, gap, w, h),
          math.Rectangle(gap, gap * 2 + h, w, h),
        ];
      case CollageLayout.threeGrid:
        final w = (size - gap * 3) ~/ 2;
        final hFull = size - gap * 2;
        final hHalf = (size - gap * 3) ~/ 2;
        return [
          math.Rectangle(gap, gap, w, hFull),
          math.Rectangle(gap * 2 + w, gap, w, hHalf),
          math.Rectangle(gap * 2 + w, gap * 2 + hHalf, w, hHalf),
        ];
      case CollageLayout.fourGrid:
        final w = (size - gap * 3) ~/ 2;
        final h = (size - gap * 3) ~/ 2;
        return [
          math.Rectangle(gap, gap, w, h),
          math.Rectangle(gap * 2 + w, gap, w, h),
          math.Rectangle(gap, gap * 2 + h, w, h),
          math.Rectangle(gap * 2 + w, gap * 2 + h, w, h),
        ];
      case CollageLayout.sixGrid:
        final w = (size - gap * 3) ~/ 2;
        final h = (size - gap * 4) ~/ 3;
        return [
          for (int row = 0; row < 3; row++)
            for (int col = 0; col < 2; col++)
              math.Rectangle(
                gap + col * (w + gap),
                gap + row * (h + gap),
                w,
                h,
              ),
        ];
    }
  }

  static img.Image _coverFit(img.Image src, int targetW, int targetH) {
    final srcRatio = src.width / src.height;
    final dstRatio = targetW / targetH;
    int cropW = src.width;
    int cropH = src.height;
    int ox = 0;
    int oy = 0;
    if (srcRatio > dstRatio) {
      cropW = (src.height * dstRatio).round();
      ox = ((src.width - cropW) / 2).round();
    } else {
      cropH = (src.width / dstRatio).round();
      oy = ((src.height - cropH) / 2).round();
    }
    final cropped = img.copyCrop(src, x: ox, y: oy, width: cropW, height: cropH);
    return img.copyResize(
      cropped,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.linear,
    );
  }

  Widget _buildSlot(int index) {
    final hasImage = index < _imagePaths.length;
    return GestureDetector(
      onTap: () => _replaceSlot(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_cornerRadius),
        child: Container(
          color: AppTokens.charcoalElevated,
          child: hasImage
              ? Image.file(
                  File(_imagePaths[index]),
                  fit: BoxFit.cover,
                  cacheWidth: 480,
                )
              : const Center(
                  child: Icon(Icons.add_photo_alternate_outlined, size: 32),
                ),
        ),
      ),
    );
  }

  Widget _buildCollagePreview() {
    switch (_layout) {
      case CollageLayout.twoSide:
        return Row(
          children: [
            Expanded(child: _buildSlot(0)),
            SizedBox(width: _spacing),
            Expanded(child: _buildSlot(1)),
          ],
        );
      case CollageLayout.twoStack:
        return Column(
          children: [
            Expanded(child: _buildSlot(0)),
            SizedBox(height: _spacing),
            Expanded(child: _buildSlot(1)),
          ],
        );
      case CollageLayout.threeGrid:
        return Row(
          children: [
            Expanded(child: _buildSlot(0)),
            SizedBox(width: _spacing),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _buildSlot(1)),
                  SizedBox(height: _spacing),
                  Expanded(child: _buildSlot(2)),
                ],
              ),
            ),
          ],
        );
      case CollageLayout.fourGrid:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildSlot(0)),
                  SizedBox(width: _spacing),
                  Expanded(child: _buildSlot(1)),
                ],
              ),
            ),
            SizedBox(height: _spacing),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildSlot(2)),
                  SizedBox(width: _spacing),
                  Expanded(child: _buildSlot(3)),
                ],
              ),
            ),
          ],
        );
      case CollageLayout.sixGrid:
        return Column(
          children: [
            for (int r = 0; r < 3; r++) ...[
              if (r > 0) SizedBox(height: _spacing),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildSlot(r * 2)),
                    SizedBox(width: _spacing),
                    Expanded(child: _buildSlot(r * 2 + 1)),
                  ],
                ),
              ),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    const bgSwatches = [
      Color(0xFF0A0F1E),
      Color(0xFFFFFFFF),
      Color(0xFF1E293B),
      Color(0xFF4F8CFF),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collage Maker'),
        actions: [
          IconButton(
            tooltip: 'Pick Photos',
            icon: const Icon(Icons.add_photo_alternate),
            onPressed: _pickPhotos,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: _exporting ? null : () => _exportCollage(share: true),
          ),
          TextButton.icon(
            onPressed: _exporting ? null : () => _exportCollage(share: false),
            icon: const Icon(Icons.save_alt),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_exporting) const LinearProgressIndicator(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    padding: EdgeInsets.all(_spacing),
                    decoration: BoxDecoration(
                      color: _bgColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _buildCollagePreview(),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final l in CollageLayout.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(l.name.toUpperCase()),
                            selected: _layout == l,
                            onSelected: (_) => setState(() => _layout = l),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Gap'),
                    Expanded(
                      child: Slider(
                        value: _spacing,
                        min: 0,
                        max: 24,
                        onChanged: (v) => setState(() => _spacing = v),
                      ),
                    ),
                    const Text('Radius'),
                    Expanded(
                      child: Slider(
                        value: _cornerRadius,
                        min: 0,
                        max: 28,
                        onChanged: (v) => setState(() => _cornerRadius = v),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        for (final c in bgSwatches)
                          GestureDetector(
                            onTap: () => setState(() => _bgColor = c),
                            child: Container(
                              width: 26,
                              height: 26,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _bgColor == c
                                      ? AppTokens.primaryBlue
                                      : Colors.white30,
                                  width: _bgColor == c ? 2.5 : 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: _pickPhotos,
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text('Select (${_imagePaths.length}/$_slotCount)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
