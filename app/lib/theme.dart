import 'package:material_ui/material_ui.dart';

/// Dark "void" theme — near-black background, violet neon accent,
/// matching the owner's other projects.
const Color kVoid = Color(0xFF07070D);
const Color kSurface = Color(0xFF10101A);
const Color kSurface2 = Color(0xFF171724);
const Color kAccent = Color(0xFF8B5CF6);
const Color kAccent2 = Color(0xFF22D3EE);
const Color kText = Color(0xFFEDEDF2);
const Color kMuted = Color(0xFF8A8A9E);

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
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurface,
      foregroundColor: kText,
      elevation: 0,
    ),
    cardColor: kSurface,
    dividerColor: const Color(0xFF23232F),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: kMuted),
      labelStyle: const TextStyle(color: kMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kAccent2),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kSurface,
      selectedItemColor: kAccent,
      unselectedItemColor: kMuted,
    ),
  );
}
