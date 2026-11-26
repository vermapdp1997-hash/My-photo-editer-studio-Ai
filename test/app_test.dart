import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_photo_editor_ai/app/app.dart';
import 'package:my_photo_editor_ai/core/performance/performance_profile.dart';
import 'package:my_photo_editor_ai/data/models/edit_state.dart';
import 'package:my_photo_editor_ai/features/filters/filter_catalog.dart';
import 'package:my_photo_editor_ai/services/image_service/image_pipeline_service.dart';

void main() {
  test('FilterCatalog provides at least 100 unique filters without duplicates', () {
    final all = FilterCatalog.all;
    expect(all.length, greaterThanOrEqualTo(100));
    expect(all.map((e) => e.id).toSet().length, equals(all.length));
    expect(all.map((e) => e.name).toSet().length, equals(all.length));
  });

  test('EditState serializes and restores non-destructive edits cleanly', () {
    const original = EditState(
      brightness: 0.25,
      contrast: 0.15,
      filterId: 'flt_cinematic_0',
      filterIntensity: 0.85,
      rotationQuarterTurns: 1,
      flipHorizontal: true,
      textLayers: [TextLayerItem(id: 't1', text: 'Studio')],
    );
    final roundTrip = EditState.fromJsonString(original.toJsonString());
    expect(roundTrip.brightness, closeTo(0.25, 0.001));
    expect(roundTrip.contrast, closeTo(0.15, 0.001));
    expect(roundTrip.filterId, equals('flt_cinematic_0'));
    expect(roundTrip.rotationQuarterTurns, equals(1));
    expect(roundTrip.flipHorizontal, isTrue);
    expect(roundTrip.textLayers.length, equals(1));
  });

  test('PerformanceConfig resolves valid budgets across all modes', () {
    final low = PerformanceConfig.resolve(PerformanceMode.low);
    final bal = PerformanceConfig.resolve(PerformanceMode.balanced);
    final high = PerformanceConfig.resolve(PerformanceMode.high);
    expect(low.previewMaxDimension, lessThan(bal.previewMaxDimension));
    expect(bal.previewMaxDimension, lessThan(high.previewMaxDimension));
  });

  test('ImagePipelineService processes adjustments, crop and filter offline', () async {
    final tempDir = await Directory.systemTemp.createTemp('mpe_test_');
    try {
      final src = img.Image(width: 64, height: 48, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(120, 140, 160, 255));
      final srcFile = File('${tempDir.path}/sample.png');
      await srcFile.writeAsBytes(img.encodePng(src));

      const state = EditState(
        brightness: 0.2,
        contrast: 0.1,
        filterId: 'flt_warm_0',
        rotationQuarterTurns: 1,
      );
      final outBytes = await ImagePipelineService.instance.renderPreviewPng(
        srcFile.path,
        state,
        maxDimension: 128,
      );
      final decoded = img.decodePng(outBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(48));
      expect(decoded.height, equals(64));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('MyPhotoEditorApp renders home dashboard cleanly', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MyPhotoEditorApp()),
    );
    await tester.pump();
    expect(find.text('My Photo Editor AI'), findsOneWidget);
  });
}
