import 'package:flutter/material.dart';

/// Beta 79 design system: Tidal Ink.
/// A notebook-first palette with cool paper, deep teal ink and coral actions.
/// The editor canvas remains responsible for its own paper templates.
class SnoteTheme {
  static const violet = Color(0xFF176B66); // Keep API name for saved theme compatibility.
  static const ink = Color(0xFF132A2A);
  static const canvas = Color(0xFFF1F5F3);
  static const panel = Color(0xFFFFFFFF);
  static const coral = Color(0xFFFF795C);
  static const mint = Color(0xFF9FE0D1);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: Brightness.light,
      surface: panel,
    ).copyWith(
      primary: violet,
      onPrimary: Colors.white,
      secondary: coral,
      onSecondary: Colors.white,
      surface: panel,
      onSurface: ink,
      surfaceContainerLowest: const Color(0xFFFCFDFC),
      surfaceContainerLow: const Color(0xFFF7FAF8),
      surfaceContainer: const Color(0xFFEDF3F0),
      outline: const Color(0xFFCBD8D3),
      outlineVariant: const Color(0xFFDDE6E1),
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD5E1DC)),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF1F5F3),
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        toolbarHeight: 64,
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
          side: const BorderSide(color: Color(0xFFE0E9E4)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFCFB),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: violet, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: panel,
        indicatorColor: Color(0xFFD5F0E9),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEAF3EF),
        selectedColor: const Color(0xFFD2EEE6),
        side: const BorderSide(color: Color(0xFFD6E4DD)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: violet,
          side: const BorderSide(color: Color(0xFFBDD3CA)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFDDE6E1),
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData dark() {
    const background = Color(0xFF0D191A);
    const surface = Color(0xFF152526);
    const text = Color(0xFFE5F0EB);
    const teal = Color(0xFF74DCC7);

    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(
      primary: teal,
      onPrimary: const Color(0xFF062B28),
      secondary: coral,
      onSecondary: const Color(0xFF2A100A),
      surface: surface,
      onSurface: text,
      surfaceContainerLowest: const Color(0xFF101E1F),
      surfaceContainerLow: const Color(0xFF1A2B2C),
      surfaceContainer: const Color(0xFF203435),
      outline: const Color(0xFF385251),
      outlineVariant: const Color(0xFF2A4241),
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
        toolbarHeight: 64,
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
          side: const BorderSide(color: Color(0xFF2A4241)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF101E1F),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2A4241)),
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
        indicatorColor: Color(0xFF244E48),
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
          foregroundColor: const Color(0xFF062B28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A4241),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
