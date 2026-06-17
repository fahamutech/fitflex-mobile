import 'package:flutter/material.dart';

/// FitFlex Af design tokens — keep in sync with `fitflex-portal/app/globals.css`.
class FFTokens {
  FFTokens._();

  // ── Brand scale (maps to --color-brand-*) ──
  static const Color brand50 = Color(0xFFE7F4EC);
  static const Color brand100 = Color(0xFFC4E3CF);
  static const Color brand200 = Color(0xFF9ED1AF);
  static const Color brand500 = Color(0xFF1F7A3A);
  static const Color brand600 = Color(0xFF1A6B32);
  static const Color brand700 = Color(0xFF155A2A);
  static const Color brand800 = Color(0xFF104921);

  // Legacy aliases
  static const Color brand = brand500;
  static const Color brandDark = brand700;
  static const Color brandLight = brand50;

  // ── Semantic colors ──
  static const Color accent = Color(0xFFF59E0B);

  static const Color error50 = Color(0xFFFEF3F2);
  static const Color error200 = Color(0xFFFECDCA);
  static const Color error500 = Color(0xFFDC2626);
  static const Color error600 = Color(0xFFD92D20);
  static const Color error700 = Color(0xFFB42318);
  static const Color danger = error500;

  static const Color success50 = Color(0xFFECFDF3);
  static const Color success200 = Color(0xFFABEFC6);
  static const Color success500 = Color(0xFF16A34A);
  static const Color success600 = Color(0xFF099250);
  static const Color success700 = Color(0xFF067647);
  static const Color success = success500;

  static const Color warning50 = Color(0xFFFFFBEB);
  static const Color warning200 = Color(0xFFFEDF89);
  static const Color warning500 = Color(0xFFF59E0B);
  static const Color warning700 = Color(0xFFB54708);

  // ── Foreground / text ──
  static const Color fgPrimary = Color(0xFF0F172A);
  static const Color fgSecondary = Color(0xFF344054);
  static const Color fgTertiary = Color(0xFF475467);
  static const Color fgQuaternary = Color(0xFF667085);
  static const Color fgDisabled = Color(0xFF98A2B3);
  static const Color fgBrand = brand600;

  // Legacy aliases
  static const Color text = fgPrimary;
  static const Color textMuted = fgQuaternary;

  // ── Background / surface ──
  static const Color bgPrimary = Color(0xFFFFFFFF);
  static const Color bgSecondary = Color(0xFFF9FAFB);
  static const Color bgTertiary = Color(0xFFF2F4F7);

  // Legacy aliases
  static const Color surface = bgPrimary;
  static const Color surface2 = bgSecondary;

  // ── Borders ──
  static const Color borderPrimary = Color(0xFFD0D5DD);
  static const Color borderSecondary = Color(0xFFE4E7EC);

  // Legacy alias
  static const Color border = borderSecondary;

  // ── Gray scale ──
  static const Color gray100 = Color(0xFFF2F4F7);
  static const Color gray200 = Color(0xFFE4E7EC);
  static const Color gray500 = Color(0xFF667085);
  static const Color gray700 = Color(0xFF344054);

  // ── Radii ──
  static const double radiusXs = 4;
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusFull = 999;

  // ── Spacing ──
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;

  // ── Shadows ──
  static List<BoxShadow> get shadowXs => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get shadowSm => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.10),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: FFTokens.brand,
      primary: FFTokens.brand,
      surface: FFTokens.surface,
    ),
    scaffoldBackgroundColor: FFTokens.bgSecondary,
    appBarTheme: const AppBarTheme(
      backgroundColor: FFTokens.bgPrimary,
      foregroundColor: FFTokens.fgPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FFTokens.brand600,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: FFTokens.fgSecondary,
        side: const BorderSide(color: FFTokens.borderPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: FFTokens.brand700),
    ),
    cardTheme: CardThemeData(
      color: FFTokens.bgPrimary,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: FFTokens.borderSecondary),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FFTokens.bgPrimary,
      labelStyle: const TextStyle(
        color: FFTokens.fgSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: const TextStyle(color: FFTokens.fgQuaternary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.borderPrimary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.borderPrimary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.brand500, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.error500),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: FFTokens.bgPrimary,
      indicatorColor: FFTokens.brand50,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: FFTokens.brand700,
          );
        }
        return const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: FFTokens.fgQuaternary,
        );
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: FFTokens.borderSecondary,
      thickness: 1,
    ),
  );
}
