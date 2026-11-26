import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'services/ads_service/admob_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ProviderScope(
      child: MyPhotoEditorApp(),
    ),
  );

  // Initialize optional AdMob in background so it never blocks or crashes app launch
  unawaited(AdMobService.instance.initialize());
}
