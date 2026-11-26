import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'services/ads_service/admob_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdMobService.instance.initialize();
  runApp(
    const ProviderScope(
      child: MyPhotoEditorApp(),
    ),
  );
}
