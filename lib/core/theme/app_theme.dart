import 'package:flutter/material.dart';

/// Dark mode is the primary design target; light mode is supported but
/// secondary. Kept intentionally minimal here — full visual language
/// (typography scale, motion curves, custom components) is a design
/// pass on top of this scaffold, not part of the architecture itself.
class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0B0F),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.light,
        ),
      );
}
