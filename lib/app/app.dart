import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_database/project_database.dart';
import '../features/home/home_dashboard_screen.dart';
import 'theme/app_theme.dart';

class MyPhotoEditorApp extends ConsumerWidget {
  const MyPhotoEditorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'My Photo Editor AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: Locale(settings.languageCode),
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeDashboardScreen(),
    );
  }
}
