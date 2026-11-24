import 'package:flutter/material.dart';

/// Everything that makes Paigham look like Paigham lives here.
/// Change the name, colours or font in this one file and the whole app follows.
class Brand {
  Brand._();

  /// Product name. Latin form is used for store listings and file names.
  static const String nameLatin = 'Paigham';

  /// Native form (identical in Pashto and Dari).
  static const String nameNative = 'پیغام';

  static const String version = '0.1.0';

  static const String fontFamily = 'Vazirmatn';

  // ── Core palette ──────────────────────────────────────────────────────────
  // Lapis lazuli: the deep blue stone mined in Badakhshan for 6,000 years.
  static const Color lapis = Color(0xFF1F3F9E);
  static const Color lapisDeep = Color(0xFF142A6B);
  static const Color lapisBright = Color(0xFF3D63D6);
  static const Color lapisMist = Color(0xFFE6ECFA);

  // Saffron: Herat saffron gold, used for actions and highlights.
  static const Color saffron = Color(0xFFF2A516);
  static const Color saffronDeep = Color(0xFFD98A00);
  static const Color saffronMist = Color(0xFFFFF3D9);

  // Pomegranate: Kandahar red, used for errors and destructive actions.
  static const Color pomegranate = Color(0xFFC6303E);

  // Neutrals
  static const Color ink = Color(0xFF141A2E);
  static const Color slate = Color(0xFF5B6478);
  static const Color paper = Color(0xFFF5F7FC);

  // Dark mode surfaces
  static const Color night = Color(0xFF0C1222);
  static const Color nightSurface = Color(0xFF141C31);
  static const Color nightRaised = Color(0xFF1C2640);

  // Chat bubbles
  static const Color bubbleOutLight = Color(0xFFDCE5FF);
  static const Color bubbleInLight = Colors.white;
  static const Color bubbleOutDark = Color(0xFF2A428C);
  static const Color bubbleInDark = Color(0xFF1C2640);

  /// Avatar colours, picked by hashing a user id.
  static const List<Color> avatarColors = [
    Color(0xFF1F3F9E), // lapis
    Color(0xFFD98A00), // saffron
    Color(0xFF1E8C6E), // turquoise (Nishapur/Herat tiles)
    Color(0xFFC6303E), // pomegranate
    Color(0xFF6A3FA0), // grape
    Color(0xFF0F7FA8), // Band-e-Amir blue
    Color(0xFF8A5A2B), // walnut
    Color(0xFF3B7D2E), // pistachio leaf
  ];

  static Color avatarColor(String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return avatarColors[h % avatarColors.length];
  }

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: lapis,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFF8FA8FF) : lapis,
      onPrimary: dark ? night : Colors.white,
      primaryContainer: dark ? const Color(0xFF233A80) : lapisMist,
      onPrimaryContainer: dark ? Colors.white : lapisDeep,
      secondary: saffron,
      onSecondary: ink,
      secondaryContainer: dark ? const Color(0xFF4A3608) : saffronMist,
      onSecondaryContainer: dark ? saffron : const Color(0xFF5A3A00),
      error: pomegranate,
      surface: dark ? nightSurface : Colors.white,
      onSurface: dark ? const Color(0xFFE7EAF3) : ink,
      onSurfaceVariant: dark ? const Color(0xFFA4ACC2) : slate,
      surfaceContainerLowest: dark ? night : paper,
      surfaceContainerLow: dark ? nightSurface : const Color(0xFFF0F3FA),
      surfaceContainer: dark ? nightRaised : const Color(0xFFEAEEF7),
      surfaceContainerHigh: dark ? const Color(0xFF222D4A) : const Color(0xFFE3E8F4),
      outlineVariant: dark ? const Color(0xFF2A3452) : const Color(0xFFDDE2EE),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: dark ? night : paper,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? nightSurface : lapis,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: saffron,
        foregroundColor: ink,
        elevation: 3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? nightSurface : Colors.white,
        indicatorColor: dark ? const Color(0xFF233A80) : lapisMist,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark ? nightSurface : Colors.white,
        indicatorColor: dark ? const Color(0xFF233A80) : lapisMist,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? const Color(0xFF8FA8FF) : lapis,
          foregroundColor: dark ? night : Colors.white,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? nightRaised : const Color(0xFFF0F3FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? nightSurface : Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? nightRaised : ink,
        contentTextStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white),
      ),
    );
  }
}
