import 'package:flutter/material.dart';

/// FitFlex design tokens — keep in sync with `fitflex-portal/app/globals.css`.
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
  static const Color accent = Color(0xFFFF9800);

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
  static const Color warning500 = Color(0xFFFF9800);
  static const Color warning700 = Color(0xFFB54708);

  // ── Foreground / text ── (dark-mode values)
  static const Color fgPrimary = Color(0xFFF1F5F9);
  static const Color fgSecondary = Color(0xFFCBD5E1);
  static const Color fgTertiary = Color(0xFFAAB4C4);
  static const Color fgQuaternary = Color(0xFF94A3B8);
  static const Color fgDisabled = Color(0xFF55677A);
  static const Color fgBrand = Color(0xFF00B67A);

  // Legacy aliases
  static const Color text = fgPrimary;
  static const Color textMuted = fgQuaternary;

  // ── Background / surface ── (dark-mode values)
  static const Color bgPrimary = Color(0xFF020617);
  static const Color bgSecondary = Color(0xFF0F172A);
  static const Color bgTertiary = Color(0xFF0F172A);

  // Legacy aliases
  static const Color surface = bgPrimary;
  static const Color surface2 = bgSecondary;

  // ── Borders ── (dark-mode values)
  static const Color borderPrimary = Color(0xFF1E293B);
  static const Color borderSecondary = Color(0xFF1E293B);

  // Legacy alias
  static const Color border = borderSecondary;

  // ── Gray scale ── (dark-mode values)
  static const Color gray100 = Color(0xFF162438);
  static const Color gray200 = Color(0xFF1F3350);
  static const Color gray500 = Color(0xFF8899AA);
  static const Color gray700 = Color(0xFFCDD5DF);

  // ── Radii ──
  static const double radiusXs = 6;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusFull = 999;

  // ── Spacing ──
  static const double spacing2xs = 2;
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;
  static const double spacing2xl = 48;

  // ── Icon sizes ──
  static const double iconXs = 14;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;

  /// Standard square container that wraps a leading icon.
  static const double iconBox = 40;

  // ── Type families (bundled in assets/fonts) ──
  static const String fontSans = 'Inter';
  static const String fontMono = 'JetBrains Mono';

  /// UPPERCASE, wide-tracked "telemetry" label: section eyebrows, data
  /// tags, field labels. Never for sentences.
  static TextStyle monoLabel(Color color, {double size = 11}) => TextStyle(
    fontFamily: fontMono,
    fontSize: size,
    fontWeight: FontWeight.w500,
    letterSpacing: size * 0.12,
    color: color,
  );

  // ── Motion (durations + curves) ──
  static const Duration motionFast = Duration(milliseconds: 100);
  static const Duration motionMedium = Duration(milliseconds: 200);
  static const Duration motionSlow = Duration(milliseconds: 400);
  static const Curve motionCurve = Curves.easeInOut;
  static const Curve motionEmphasized = Curves.easeOutCubic;

  // ── Shadows ──
  static List<BoxShadow> get shadowXs => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.18),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowSm => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  // ── Dark mode surfaces (login-flow screens) ──
  // FitFlex Africa design system: slate-950 canvas, slate-900 cards,
  // slate-800 hairline borders.
  static const Color darkBg = Color(0xFF020617);
  static const Color darkSurface = Color(0xFF0F172A);
  static const Color darkBorder = Color(0xFF1E293B);

  // ── Vibrant brand green (dark-mode CTA + selection state) ──
  static const Color brandVibrant = Color(0xFF00B67A);

  // ── On-dark text ──
  static const Color darkFgPrimary = Color(0xFFF1F5F9); // slate-100
  static const Color darkFgSecondary = Color(0xFFCBD5E1); // slate-300
  static const Color darkFgMuted = Color(0xFF94A3B8); // slate-400

  // ── Role-card accent icon colors ──
  static const Color iconAccentGreen = Color(0xFF00B67A);
  static const Color accentOrange = Color(0xFFFF9800);
  static const Color accentIndigo = Color(0xFF6366F1);
}

ThemeData buildDarkTheme() {
  const bg = FFTokens.darkBg;
  const surface = FFTokens.darkSurface;
  const onSurface = FFTokens.darkFgPrimary;
  const primary = FFTokens.brandVibrant;
  const bord = FFTokens.darkBorder;

  return ThemeData(
    useMaterial3: true,
    fontFamily: FFTokens.fontSans,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.black,
      secondary: primary,
      onSecondary: Colors.black,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surface,
      surfaceContainerLow: Color(0xFF0F1E2E),
      outlineVariant: Color(0xFF1E293B),
      outline: bord,
      error: FFTokens.danger,
      onError: Colors.white,
    ),
    // ── Text ──────────────────────────────────────────────────────────────────
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 57,
        fontWeight: FontWeight.w400,
      ),
      displayMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 45,
        fontWeight: FontWeight.w400,
      ),
      displaySmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 36,
        fontWeight: FontWeight.w400,
      ),
      headlineLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      headlineMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
    // ── App bar ───────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: onSurface),
    ),
    // ── Bottom navigation ─────────────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primary.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primary);
        }
        return const IconThemeData(color: FFTokens.darkFgMuted);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontFamily: FFTokens.fontSans,
            color: primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );
        }
        return const TextStyle(
          fontFamily: FFTokens.fontSans,
          color: FFTokens.darkFgMuted,
          fontSize: 11,
        );
      }),
    ),
    // ── Card ──────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        side: const BorderSide(color: bord),
      ),
    ),
    // ── Buttons ───────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.black,
        disabledBackgroundColor: surface,
        disabledForegroundColor: FFTokens.darkFgMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(
          fontFamily: FFTokens.fontSans,
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 0.5,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: FFTokens.darkFgSecondary,
        side: const BorderSide(color: bord),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),
    // ── Input ─────────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      labelStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
        fontSize: 14,
      ),
      hintStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
      ),
      suffixIconColor: FFTokens.darkFgMuted,
      prefixIconColor: FFTokens.darkFgMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: bord),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: bord),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.danger, width: 2),
      ),
    ),
    // ── Misc ──────────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(color: bord, thickness: 1),
    // Tracks must contrast with cards (surfaceContainerHighest is the card
    // colour), so an empty bar still reads as a bar.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: Color(0xFF334155),
    ),
    iconTheme: const IconThemeData(color: FFTokens.darkFgMuted),
    listTileTheme: const ListTileThemeData(
      textColor: onSurface,
      iconColor: FFTokens.darkFgMuted,
      tileColor: surface,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: primary.withValues(alpha: 0.18),
      side: const BorderSide(color: bord),
      labelStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
      ),
      checkmarkColor: primary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
      ),
      actionTextColor: primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FFTokens.radiusXl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgSecondary,
        fontSize: 14,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.black),
      side: const BorderSide(color: bord, width: 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.black;
        return FFTokens.darkFgMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return bord;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return bord;
      }),
    ),
  );
}

ThemeData buildTheme() {
  // ── Light-mode palette ──
  const bg = Color(0xFFEEF2F7);
  const surface = Colors.white;
  const onSurface = Color(0xFF0F172A);
  // Deep emerald keeps contrast on white.
  const primary = Color(0xFF009366);
  const onPrimary = Colors.white;
  const bord = Color(0xFFE2E8F0);
  const muted = Color(0xFF64748B);

  return ThemeData(
    useMaterial3: true,
    fontFamily: FFTokens.fontSans,
    brightness: Brightness.light,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surface,
      surfaceContainerLow: Color(0xFFF2F4F7),
      outlineVariant: Color(0xFFE2E8F0),
      outline: bord,
      error: FFTokens.danger,
      onError: Colors.white,
    ),
    // ── Text ──────────────────────────────────────────────────────────────────
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 57,
        fontWeight: FontWeight.w400,
      ),
      displayMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 45,
        fontWeight: FontWeight.w400,
      ),
      displaySmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 36,
        fontWeight: FontWeight.w400,
      ),
      headlineLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      headlineMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
    // ── App bar ───────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: onSurface),
    ),
    // ── Bottom navigation ─────────────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: FFTokens.brand50,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primary);
        }
        return const IconThemeData(color: muted);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontFamily: FFTokens.fontSans,
            color: primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );
        }
        return const TextStyle(
          fontFamily: FFTokens.fontSans,
          color: muted,
          fontSize: 11,
        );
      }),
    ),
    // ── Card ──────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        side: const BorderSide(color: bord),
      ),
    ),
    // ── Buttons ───────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        disabledBackgroundColor: const Color(0xFFE4E7EC),
        disabledForegroundColor: muted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(
          fontFamily: FFTokens.fontSans,
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 0.5,
          color: onPrimary,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: const BorderSide(color: bord),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),
    // ── Input ─────────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      labelStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 14,
      ),
      hintStyle: const TextStyle(fontFamily: FFTokens.fontSans, color: muted),
      suffixIconColor: muted,
      prefixIconColor: muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: bord),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: bord),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.danger, width: 2),
      ),
    ),
    // ── Misc ──────────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(color: bord, thickness: 1),
    // Tracks must contrast with cards (surfaceContainerHighest is the card
    // colour), so an empty bar still reads as a bar.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: Color(0xFFCBD5E1),
    ),
    iconTheme: const IconThemeData(color: muted),
    listTileTheme: const ListTileThemeData(
      textColor: onSurface,
      iconColor: muted,
      tileColor: surface,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: FFTokens.brand50,
      side: const BorderSide(color: bord),
      labelStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
      ),
      checkmarkColor: primary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: onSurface,
      contentTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: Colors.white,
      ),
      actionTextColor: FFTokens.brand200,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FFTokens.radiusXl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 14,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: bord, width: 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return muted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return bord;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return bord;
      }),
    ),
  );
}
