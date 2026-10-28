import 'package:flutter/material.dart';

/// Beta 79 design system: Tidal Ink.
/// A notebook-first palette with cool paper, deep teal ink and coral actions.
/// The editor canvas remains responsible for its own paper templates.
class SnoteTheme {
  static const violet = Color(0xFF5B5CE2); // Refreshed indigo-violet app accent.
  static const ink = Color(0xFF172033);
  static const canvas = Color(0xFFF5F6FC);
  static const panel = Color(0xFFFFFFFF);
  static const coral = Color(0xFF0F9D8A); // Refreshed mint-teal secondary accent.
  static const mint = Color(0xFFE5E7FF);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: Brightness.light,
      contrastLevel: 1.0,
      surface: panel,
    ).copyWith(
      primary: violet,
      onPrimary: Colors.white,
      secondary: coral,
      onSecondary: Colors.white,
      surface: panel,
      onSurface: ink,
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF8FAFD),
      surfaceContainer: const Color(0xFFEAF0F8),
      outline: const Color(0xFF68758A),
      outlineVariant: const Color(0xFF8793A5),
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF68758A)),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF4F6FA),
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        toolbarHeight: 56,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: panel,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: shape.copyWith(
          side: const BorderSide(color: Color(0xFF8793A5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFBFCFE),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: violet, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: panel,
        indicatorColor: Color(0xFFDCE7F7),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF1F4F9),
        selectedColor: const Color(0xFFDCE7F7),
        side: const BorderSide(color: Color(0xFF68758A)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: coral,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: violet,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: violet,
          side: const BorderSide(color: Color(0xFFBCCAE0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF8793A5),
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData dark() {
    const background = Color(0xFF10111B);
    const surface = Color(0xFF1A1B29);
    const text = Color(0xFFF0F0FA);
    const teal = Color(0xFFB7B5FF);

    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.dark,
      contrastLevel: 1.0,
      surface: surface,
    ).copyWith(
      primary: teal,
      onPrimary: const Color(0xFF0E1B32),
      secondary: const Color(0xFF62C7BB),
      onSecondary: const Color(0xFF082B2B),
      surface: surface,
      onSurface: text,
      surfaceContainerLowest: const Color(0xFF111A29),
      surfaceContainerLow: const Color(0xFF1C2738),
      surfaceContainer: const Color(0xFF222F43),
      outline: const Color(0xFF8292AA),
      outlineVariant: const Color(0xFF5D6E87),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF5D6E87)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111A29),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2B3B53)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: teal, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: Color(0xFF24457A),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: coral,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: teal,
          foregroundColor: const Color(0xFF0E1B32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF5D6E87),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
