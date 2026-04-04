import 'package:flutter/material.dart';
import 'package:openreef/settings/app_settings.dart';

class ReefPalette {
  static const Color coral = Color(0xFFFF7F6A);
  static const Color darkBackground = Color(0xFF0C0F10);
  static const Color darkSurface = Color(0xFF13191B);
  static const Color darkPanel = Color(0xFF1B2326);
  static const Color darkBorder = Color(0xFF2D3A3F);
  static const Color darkText = Color(0xFFF4F1EA);
  static const Color darkMuted = Color(0xFF8C9A9F);
  static const Color darkSuccess = Color(0xFF57C084);

  static const Color lightBackground = Color(0xFFF5EEE6);
  static const Color lightSurface = Color(0xFFFFFBF7);
  static const Color lightPanel = Color(0xFFF0E5DA);
  static const Color lightBorder = Color(0xFFD9C3B2);
  static const Color lightText = Color(0xFF1C1714);
  static const Color lightMuted = Color(0xFF6E6156);
}

ThemeMode mapThemeMode(ReefThemeMode mode) {
  switch (mode) {
    case ReefThemeMode.dark:
      return ThemeMode.dark;
    case ReefThemeMode.light:
      return ThemeMode.light;
    case ReefThemeMode.system:
      return ThemeMode.system;
  }
}

ThemeData buildReefTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final background =
      isDark ? ReefPalette.darkBackground : ReefPalette.lightBackground;
  final surface = isDark ? ReefPalette.darkSurface : ReefPalette.lightSurface;
  final panel = isDark ? ReefPalette.darkPanel : ReefPalette.lightPanel;
  final border = isDark ? ReefPalette.darkBorder : ReefPalette.lightBorder;
  final foreground = isDark ? ReefPalette.darkText : ReefPalette.lightText;
  final muted = isDark ? ReefPalette.darkMuted : ReefPalette.lightMuted;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: ReefPalette.coral,
    onPrimary: Colors.black,
    secondary: ReefPalette.coral,
    onSecondary: Colors.black,
    error: const Color(0xFFFF6F61),
    onError: Colors.black,
    surface: surface,
    onSurface: foreground,
    tertiary: ReefPalette.darkSuccess,
    onTertiary: Colors.black,
    outline: border,
    shadow: Colors.black,
    inverseSurface: foreground,
    onInverseSurface: background,
    inversePrimary: ReefPalette.coral,
    primaryContainer: panel,
    onPrimaryContainer: foreground,
    secondaryContainer: panel,
    onSecondaryContainer: foreground,
    surfaceContainerHighest: panel,
    onSurfaceVariant: muted,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'JetBrainsMono',
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    textTheme: Typography.material2021(platform: TargetPlatform.android)
        .white
        .apply(
          bodyColor: foreground,
          displayColor: foreground,
          fontFamily: 'JetBrainsMono',
        ),
    dividerColor: border,
  );

  return base.copyWith(
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border),
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: ReefPalette.coral.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? ReefPalette.coral
              : muted,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      backgroundColor: background,
      foregroundColor: foreground,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ReefPalette.coral, width: 1.2),
      ),
      hintStyle: base.textTheme.bodyMedium?.copyWith(color: muted),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: ReefPalette.coral,
      inactiveTrackColor: border,
      thumbColor: ReefPalette.coral,
      overlayColor: ReefPalette.coral.withValues(alpha: 0.12),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ReefPalette.coral
            : muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ReefPalette.coral.withValues(alpha: 0.35)
            : border,
      ),
    ),
  );
}
