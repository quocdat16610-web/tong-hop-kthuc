import 'dart:io';

import 'package:flutter/material.dart';

final String monoFont = Platform.isWindows ? 'Consolas' : (Platform.isMacOS ? 'Menlo' : Platform.isLinux ? 'DejaVu Sans Mono' : 'monospace');

const _accent = Color(0xFF0B63CE);
const _accentDark = Color(0xFF5EA2F5);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: b,
    primary: dark ? _accentDark : _accent,
    surface: dark ? const Color(0xFF1E1F22) : Colors.white,
    surfaceContainerLowest: dark ? const Color(0xFF17181B) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF1B1C1F) : const Color(0xFFF8F9FA),
    surfaceContainer: dark ? const Color(0xFF232428) : const Color(0xFFF3F4F6),
    surfaceContainerHigh: dark ? const Color(0xFF2B2D31) : const Color(0xFFECEEF1),
    surfaceContainerHighest: dark ? const Color(0xFF313338) : const Color(0xFFE6E8EB),
    outline: dark ? const Color(0xFF3B3F46) : const Color(0xFFCFD4DA),
    outlineVariant: dark ? const Color(0xFF2D3036) : const Color(0xFFE3E6EA),
  );
  final radius = BorderRadius.circular(4);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    visualDensity: Platform.isAndroid ? VisualDensity.standard : VisualDensity.compact,
    scaffoldBackgroundColor: scheme.surface,
    dividerColor: scheme.outlineVariant,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(backgroundColor: scheme.surfaceContainerLow, elevation: 0, scrolledUnderElevation: 0, foregroundColor: scheme.onSurface),
    cardTheme: CardThemeData(elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: scheme.outlineVariant))),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outline)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius), side: BorderSide(color: scheme.outline))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius))),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    menuTheme: MenuThemeData(style: MenuStyle(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)))),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, width: 420),
  );
}

extension Pal on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  bool get compact => MediaQuery.sizeOf(this).width < 900;
}

const okColor = Color(0xFF1A7F37);
const okColorDark = Color(0xFF4AC26B);
const warnColor = Color(0xFF9A6700);
