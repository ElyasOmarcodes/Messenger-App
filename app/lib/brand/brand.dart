import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Everything that makes Paigham look like Paigham lives here.
/// Change the name, colours or font in this one file and the whole app follows.
class Brand {
  Brand._();

  static const String nameLatin = 'Paigham';
  static const String nameNative = 'پیغام';
  static const String version = '0.17.1';

  /// The app's own font. Turned off for a test: null = the phone's system
  /// font (plain text). To bring Vazirmatn back, set this to [vazirmatn].
  static const String? fontFamily = null;
  static const String vazirmatn = 'Vazirmatn';

  // ── Paigham Blue ─────────────────────────────────────────────────────────
  static const Color blue = Color(0xFF3390EC); // primary: buttons, links, unread badges
  static const Color blueDeep = Color(0xFF2470C2); // pressed states, read ticks on light
  static const Color blueBright = Color(0xFF5EB5F7); // accent on dark backgrounds
  static const Color blueMist = Color(0xFFE5F1FD); // selected rows, chips

  // Older names kept so every screen follows the new palette.
  static const Color lapis = blue;
  static const Color lapisDeep = blueDeep;
  static const Color lapisBright = blueBright;
  static const Color lapisMist = blueMist;
  static const Color accent = blue;
  static const Color accentDeep = blueDeep;
  static const Color accentMist = blueMist;

  static const Color pomegranate = Color(0xFFE5484D); // errors, delete, end call
  static const Color green = Color(0xFF31B545); // online, accept call

  // ── Light theme ──────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF0F1419);
  static const Color slate = Color(0xFF707579);
  static const Color paper = Colors.white;
  static const Color lightChatBg = Color(0xFFD3E4F0);
  static const Color bubbleOutLight = Color(0xFFDDEEFE);
  static const Color bubbleInLight = Colors.white;

  // ── Night theme (navy, easy on the eyes) ─────────────────────────────────
  static const Color night = Color(0xFF17212B); // page background
  static const Color nightSurface = Color(0xFF1E2C3A); // bars, cards
  static const Color nightRaised = Color(0xFF242F3D); // inputs, sheets
  static const Color nightChatBg = Color(0xFF0F1A28);
  static const Color bubbleOutDark = Color(0xFF2B5278);
  static const Color bubbleInDark = Color(0xFF182533);

  /// Avatar colours, picked by hashing a user id.
  static const List<Color> avatarColors = [
    Color(0xFFE17076), // coral
    Color(0xFFF5A64B), // apricot
    Color(0xFFA695E7), // violet
    Color(0xFF7BC862), // green
    Color(0xFF6EC9CB), // teal
    Color(0xFF65AADD), // sky
    Color(0xFFEE7AAE), // pink
    Color(0xFF5B8DEF), // blue
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
    final bg = dark ? night : paper;
    final surface = dark ? nightSurface : Colors.white;
    final onSurface = dark ? const Color(0xFFF5F5F5) : ink;
    final muted = dark ? const Color(0xFF8B9BAA) : slate;
    final primary = dark ? blueBright : blue;

    final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: brightness).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: dark ? const Color(0xFF2B5278) : blueMist,
      onPrimaryContainer: dark ? Colors.white : blueDeep,
      secondary: primary,
      onSecondary: Colors.white,
      secondaryContainer: dark ? const Color(0xFF2B5278) : blueMist,
      onSecondaryContainer: dark ? Colors.white : blueDeep,
      error: pomegranate,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      surfaceContainerLowest: bg,
      surfaceContainerLow: dark ? nightRaised : const Color(0xFFF4F4F5),
      surfaceContainer: dark ? nightRaised : const Color(0xFFEFEFF0),
      surfaceContainerHigh: dark ? const Color(0xFF2C3846) : const Color(0xFFE7E8EA),
      outlineVariant: dark ? const Color(0xFF101921) : const Color(0xFFE4E6E8),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: bg,
      // Native behaviour for each phone, like WhatsApp: on Android the
      // Android scroll (stops at the edge with a stretch, no rubber-band
      // bounce), Android page transitions and the system back gesture; on
      // iPhone the iPhone ones. (Forcing iPhone physics on Android felt like
      // a web page.) A plain, cheap ripple on touch.
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      cupertinoOverrideTheme: CupertinoThemeData(primaryColor: primary, brightness: brightness),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: Colors.black26,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w700, color: onSurface),
        iconTheme: IconThemeData(color: dark ? const Color(0xFFB8C4D0) : const Color(0xFF5E6368)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          // iOS 27 buttons are capsules
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        labelStyle: TextStyle(color: muted),
        floatingLabelStyle: TextStyle(color: primary),
        border: UnderlineInputBorder(borderSide: BorderSide(color: dark ? const Color(0xFF2E3D4C) : const Color(0xFFDADCE0))),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: dark ? const Color(0xFF2E3D4C) : const Color(0xFFDADCE0))),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: primary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(iconColor: muted),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 0.6, space: 0.6),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? nightRaised : const Color(0xE6232D36),
        contentTextStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // iOS sheets: big rounded top, grabber, grouped background
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF1C2530) : const Color(0xFFF2F2F7),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: dark ? const Color(0x66FFFFFF) : const Color(0x33000000),
        dragHandleSize: const Size(36, 5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xFF252D38) : const Color(0xFFF2F2F7),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 17, fontWeight: FontWeight.w600, color: onSurface),
      ),
      // iOS pull-down menus: rounded 14, a light shadow, roomy rows
      popupMenuTheme: PopupMenuThemeData(
        color: dark ? const Color(0xF2252D38) : const Color(0xF7FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black38,
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        textStyle: TextStyle(fontFamily: fontFamily, fontSize: 16, color: onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      switchTheme: SwitchThemeData(
        // the iOS switch: green track when on
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? const Color(0xFF34C759) : (dark ? const Color(0xFF39393D) : const Color(0xFFE9E9EA)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: dark ? nightRaised : const Color(0xFFF1F2F4),
        selectedColor: dark ? const Color(0xFF2B5278) : blueMist,
        labelStyle: TextStyle(fontFamily: fontFamily, color: onSurface, fontWeight: FontWeight.w600),
      ),
    );
  }
}
