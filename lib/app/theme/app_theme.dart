import 'package:flutter/material.dart';

class AppTokens {
  AppTokens._();

  // Dark Navy & Charcoal Palette
  static const Color navyBackground = Color(0xFF0A0F1E);
  static const Color charcoalSurface = Color(0xFF12182B);
  static const Color charcoalCard = Color(0xFF19223B);
  static const Color charcoalElevated = Color(0xFF222D4D);
  static const Color borderSubtle = Color(0xFF2B375B);

  // Brand Accents
  static const Color primaryBlue = Color(0xFF4F8CFF);
  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color accentViolet = Color(0xFF8B5CF6);
  static const Color successGreen = Color(0xFF22C55E);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);

  // Light Palette
  static const Color lightBackground = Color(0xFFF4F6FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFEDF1F9);

  // Spacing & Radius Tokens
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;

  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;

  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryBlue, accentCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient aiGradient = LinearGradient(
    colors: [accentViolet, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppTokens.primaryBlue,
      onPrimary: Colors.white,
      secondary: AppTokens.accentCyan,
      onSecondary: Color(0xFF061320),
      tertiary: AppTokens.accentViolet,
      surface: AppTokens.charcoalSurface,
      onSurface: Color(0xFFF1F5F9),
      surfaceContainerHighest: AppTokens.charcoalElevated,
      outline: AppTokens.borderSubtle,
      error: AppTokens.errorRed,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppTokens.navyBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.navyBackground,
        foregroundColor: Color(0xFFF1F5F9),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppTokens.charcoalCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          side: const BorderSide(color: AppTokens.borderSubtle, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppTokens.charcoalSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppTokens.primaryBlue,
        inactiveTrackColor: AppTokens.borderSubtle,
        thumbColor: Colors.white,
        overlayColor: AppTokens.primaryBlue.withValues(alpha: 0.2),
        trackHeight: 3.5,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTokens.charcoalElevated,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: Color(0xFF2563EB),
      onPrimary: Colors.white,
      secondary: Color(0xFF0891B2),
      onSecondary: Colors.white,
      tertiary: AppTokens.accentViolet,
      surface: AppTokens.lightSurface,
      onSurface: Color(0xFF0F172A),
      surfaceContainerHighest: AppTokens.lightCard,
      outline: Color(0xFFD5DEEE),
      error: AppTokens.errorRed,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppTokens.lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.lightBackground,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppTokens.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppTokens.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),
    );
  }
}
