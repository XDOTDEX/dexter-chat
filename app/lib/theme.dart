import 'package:material_ui/material_ui.dart';

/// Dark "void" theme — near-black background, violet neon accent,
/// matching the owner's other projects. The premium 3D-depth look is
/// built purely from layered gradients and dual shadows (a soft top
/// edge-light plus a deep drop shadow) — see widgets.dart.
const Color kVoid = Color(0xFF07070D);
const Color kSurface = Color(0xFF10101A);
const Color kSurface2 = Color(0xFF171724);
const Color kAccent = Color(0xFF8B5CF6);
const Color kAccentDeep = Color(0xFF6D28D9);
const Color kAccentSoft = Color(0xFFA78BFA);
const Color kAccent2 = Color(0xFF22D3EE);
const Color kText = Color(0xFFEDEDF2);
const Color kMuted = Color(0xFF8A8A9E);

/// Glossy violet gradient for primary actions and hero surfaces.
const LinearGradient kAccentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kAccentSoft, kAccent, kAccentDeep],
  stops: [0.0, 0.45, 1.0],
);

/// Translucent white sheen laid over gradient surfaces — the glassy
/// top light that sells the 3D feel.
const LinearGradient kSheenGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x30FFFFFF), Color(0x00FFFFFF)],
  stops: [0.0, 0.55],
);

/// Raised-panel gradient: lighter at the top, like light catching the
/// upper edge of a physical card.
const LinearGradient kPanelGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF1C1C2B), Color(0xFF0F0F18)],
);

/// Ambient app backdrop: void black under a faint violet glow.
const LinearGradient kBackdropGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF0E0E1C), kVoid],
  stops: [0.0, 0.45],
);

/// Deep drop shadows shared by raised surfaces (scaled by [strength]).
List<BoxShadow> depthShadow({double strength = 1}) => [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.5 * strength),
        blurRadius: 18 * strength,
        offset: Offset(0, 9 * strength),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.35 * strength),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];

/// Bare decoration for text fields that sit inside a [DepthField] shell
/// (the shell provides the surface, border and shadow).
InputDecoration bareFieldDecoration({
  String? labelText,
  String? hintText,
  String? helperText,
  String? prefixText,
  Widget? prefixIcon,
}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    prefixText: prefixText,
    prefixIcon: prefixIcon,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    labelStyle: const TextStyle(color: kMuted),
    floatingLabelStyle: const TextStyle(color: kAccentSoft),
    hintStyle: const TextStyle(color: kMuted),
    helperStyle: const TextStyle(color: kMuted, fontSize: 11.5),
    prefixStyle: const TextStyle(color: kText, fontSize: 16),
  );
}

/// Gradient background for app bars — a raised strip with a hairline
/// of light along its bottom edge.
Widget gradientAppBarBackground() {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF171726), Color(0xFF0C0C15)],
      ),
      border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
    ),
  );
}

ThemeData buildDexterTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: Brightness.dark,
    surface: kSurface,
  ).copyWith(
    primary: kAccent,
    secondary: kAccent2,
    onSurface: kText,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: kVoid,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: kText,
          letterSpacing: -0.5),
      headlineSmall: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: kText),
      titleLarge: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: kText),
      titleMedium: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: kText),
      bodyLarge: TextStyle(fontSize: 16, color: kText),
      bodyMedium: TextStyle(fontSize: 14, color: kText),
      bodySmall: TextStyle(fontSize: 12.5, color: kMuted),
      labelSmall: TextStyle(fontSize: 11, color: kMuted),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurface,
      foregroundColor: kText,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: kText),
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x12FFFFFF)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      elevation: 24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kSurface2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: const TextStyle(color: kText),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kSurface2,
      side: const BorderSide(color: Color(0x14FFFFFF)),
      labelStyle: const TextStyle(color: kText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? kAccent.withValues(alpha: 0.30)
                : kSurface2),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : kMuted),
        side: const WidgetStatePropertyAll(
            BorderSide(color: Color(0x14FFFFFF))),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.white : kMuted),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? kAccent
              : kSurface2.withValues(alpha: 0.9)),
    ),
    dividerColor: const Color(0xFF23232F),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0x10FFFFFF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0x10FFFFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: kAccent.withValues(alpha: 0.65)),
      ),
      hintStyle: const TextStyle(color: kMuted),
      labelStyle: const TextStyle(color: kMuted),
      floatingLabelStyle: const TextStyle(color: kAccentSoft),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        elevation: 8,
        shadowColor: kAccent.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        side: const BorderSide(color: Color(0x26FFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kAccent2),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kSurface,
      selectedItemColor: kAccent,
      unselectedItemColor: kMuted,
      elevation: 0,
    ),
  );
}
