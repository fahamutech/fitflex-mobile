import 'package:flutter/material.dart';

import 'tone_theme.dart';

/// FitFlex design tokens — mirror `fitflex-portal/app/globals.css`.
///
/// Brand ramp: the portal ramp (brand-25…950) is canonical. 400–500 are the
/// bright "energy" greens (dark-surface accents, charts); 600+ are AA-safe with
/// white (white on brand-600 = 5.7:1).
/// Legacy mobile names are kept and now map one portal step up so existing
/// call sites keep their contrast: brand500 = portal 600, brand600 = portal
/// 700, brand700 = portal 800, brand800 = portal 900.
class FFTokens {
  FFTokens._();

  // ── Brand scale (maps to --color-brand-*) ──
  static const Color brand50 = Color(0xFFEDFDF3);
  static const Color brand100 = Color(0xFFD3FAE5);
  static const Color brand200 = Color(0xFFAAF4CF);
  static const Color brand300 = Color(0xFF75E7B3);
  static const Color brand400 = Color(0xFF3DD98E);
  // Portal-parity names for the bright greens.
  static const Color brandBright = Color(0xFF17B26A); // portal brand-500
  static const Color brand500 = Color(0xFF067647); // portal brand-600
  static const Color brand600 = Color(0xFF085D3A); // portal brand-700
  static const Color brand700 = Color(0xFF074D31); // portal brand-800
  static const Color brand800 = Color(0xFF053321); // portal brand-900

  // Legacy aliases
  static const Color brand = brand500;
  static const Color brandDark = brand700;
  static const Color brandLight = brand50;

  // ── Semantic colors ──
  static const Color accent = Color(0xFFEAAA08); // gold: fills/graphics only
  static const Color accent50 = Color(0xFFFEFDF0);
  static const Color accent700 = Color(0xFF854A0E);

  static const Color info50 = Color(0xFFEFF8FF);
  static const Color info200 = Color(0xFFB2DDFF);
  static const Color info600 = Color(0xFF1570EF);
  static const Color info700 = Color(0xFF175CD3);

  static const Color error50 = Color(0xFFFEF3F2);
  static const Color error200 = Color(0xFFFECDCA);
  static const Color error500 = Color(0xFFDC2626);
  static const Color error600 = Color(0xFFD92D20);
  static const Color error700 = Color(0xFFB42318);

  /// Error foreground on dark surfaces (>= 4.5:1 on slate-900/950).
  static const Color errorOnDark = Color(0xFFF97066);
  static const Color danger = error500;

  // Success is teal-leaning so it is distinct from the brand green.
  static const Color success50 = Color(0xFFF0FDF9);
  static const Color success200 = Color(0xFF99F6E0);
  static const Color success500 = Color(0xFF0E9384);
  static const Color success600 = Color(0xFF107569);
  static const Color success700 = Color(0xFF125D56);
  static const Color success = success500;

  static const Color warning50 = Color(0xFFFFFBEB);
  static const Color warning200 = Color(0xFFFEDF89);
  static const Color warning500 = Color(0xFFF79009);
  static const Color warning700 = Color(0xFFB54708);

  // ── Foreground / text ── (dark-mode values)
  static const Color fgPrimary = Color(0xFFF1F5F9);
  static const Color fgSecondary = Color(0xFFCBD5E1);
  static const Color fgTertiary = Color(0xFFAAB4C4);
  static const Color fgQuaternary = Color(0xFF94A3B8);
  static const Color fgDisabled = Color(0xFF55677A);
  static const Color fgBrand = Color(0xFF17B26A);

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

  // Form-control boundaries, >= 3:1 against their surface (WCAG 1.4.11).
  static const Color inputBorderLight = Color(0xFF858D9D);
  static const Color inputBorderDark = Color(0xFF64748B);

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
  static const Color brandVibrant = Color(0xFF17B26A);

  // ── V2 accents (Design System V2, approved) ──
  // Volt is the member-app accent on the Pulse (dark) theme: primary CTAs,
  // selection and focus. Always pair it with [onVolt] text (15.4:1).
  static const Color volt = Color(0xFFC8F04A);
  static const Color onVolt = Color(0xFF020617);
  // Fuel is the warm "act soon" accent (expiring passes, streak heat).
  // [fuel] for light surfaces, [fuelOnDark] for text/icons on dark.
  static const Color fuel = Color(0xFFB8452C);
  static const Color fuelOnDark = Color(0xFFFF8A6B);
  static const Color fuel50 = Color(0xFFFFF4EE);
  static const Color fuel200 = Color(0xFFFBD9CC);
  // Calm is the warm light canvas used by operator (portal) surfaces.
  static const Color calmGround = Color(0xFFF7F5F0);
  static const Color calmBorder = Color(0xFFEBE7DE);

  // ── Scannable codes ──
  // QR modules/eyes are always this fixed dark ink on white, whatever the
  // theme, so scanners get maximum contrast (never the theme primary).
  static const Color qrInk = Color(0xFF020617);
  static const Color qrBackground = Color(0xFFFFFFFF);

  // ── Map markers ──
  // Pins sit on light map tiles in both themes; brand-600 green (#067647)
  // is >= 5:1 on white/near-white tiles. Paired with a white halo.
  static const Color mapPin = brand500;
  static const Color mapPinHalo = Color(0xFFFFFFFF);

  // ── On-dark text ──
  static const Color darkFgPrimary = Color(0xFFF1F5F9); // slate-100
  static const Color darkFgSecondary = Color(0xFFCBD5E1); // slate-300
  static const Color darkFgMuted = Color(0xFF94A3B8); // slate-400

  // ── Photo hero (docs/design/photo-hero-screens.md §3.3, §5) ──
  // The hero is an always-dark island: a photo under a slate-950 scrim with
  // light text, in both themes. Contrast is guaranteed against a pure-white
  // photo pixel, so it holds for any photo. Owner 2026-10-20 ("lighter"):
  // the scrim is local. A band behind the status bar and app bar, the photo
  // clear in between, and a ramp into a dark zone that holds all text.
  static const Color heroScrim = darkBg;

  /// Behind the status bar, app bar icons and logo (no other text): held
  /// over the bar, then faded out. 0.46 is the lowest value that keeps
  /// [heroText] icons at 3:1 over a pure-white pixel (3.04:1).
  static const double heroScrimTop = 0.46;

  /// Where the bar band has faded to 0, as a share of the hero's height
  /// (never above the bar's bottom edge plus [heroScrimBarFade]).
  static const double heroScrimTopFade = 0.16;

  /// The bar band's fade below the bar, in logical px.
  static const double heroScrimBarFade = 32;

  /// Minimum under any text, chip or button (13.2:1 for [heroText] over
  /// pure white), from the first line of text down to the bottom edge.
  static const double heroScrimText = 0.86;

  /// The ramp up to [heroScrimText]: a soft lead-in from 0 to
  /// [heroScrimLeadIn] over [heroScrimLeadInLength] px, then the steep part
  /// from there to [heroScrimText] over the 24px above the first line of
  /// text (the text zone's top padding).
  static const double heroScrimLeadIn = 0.40;
  static const double heroScrimLeadInLength = 48;
  static const double heroScrimRampLength = spacingLg;

  /// Dark theme bottom edge: seamless into the page ground.
  static const double heroScrimGround = 1.00;

  /// Taller heroes (owner 2026-10-20, spec §5.3): on phones at least
  /// [heroTallMinViewport] tall, the clear photo between the bar band and
  /// the ramp's lead-in aims for this share of the viewport height, clamped
  /// to [heroTallClearMin] .. [heroTallClearMax] at 1.0x text (divided by
  /// the text scale above it). A page may cap the hero so its first control
  /// stays on screen; the clear photo then shrinks, never the text.
  static const double heroTallClearShare = 0.19;
  static const double heroTallClearMin = 120;
  static const double heroTallClearMax = 200;
  static const double heroTallMinViewport = 760;

  /// Band heroes (owner 2026-10-22, "too dark"): the clear photo a band
  /// keeps above its text on phones from [heroTallMinViewport] tall, at
  /// 1.0x text (divided by the text scale above it). A screen caps its band
  /// so its first control stays above [heroBandControlShare] of the screen
  /// (FFHeroBand.maxHeightAt844); the clear photo then gives way. The bar
  /// band and the scrim under the text are unchanged.
  static const double heroBandClearPhoto = 100;

  /// How far down the screen a band screen's first control may sit (its top
  /// edge, as a share of the viewport height).
  static const double heroBandControlShare = 0.55;

  /// The least clear photo a capped band grows for; with less it keeps
  /// today's height.
  static const double heroBandMinClearPhoto = 24;

  /// Horizontal (panel / wide banner) scrim: the text column's leading edge
  /// and the far edge. The text column itself stays at >= [heroScrimText].
  static const double heroScrimPanelLead = 0.92;
  static const double heroScrimPanelTail = 0.15;

  /// Photo footer (spec §33, owner 2026-10-20): the band's height is this
  /// share of the viewport height, clamped to [footerMinHeight] ..
  /// [footerMaxHeight]; larger text makes it taller still.
  static const double footerViewportShare = 0.48;
  static const double footerMinHeight = 320;
  static const double footerMaxHeight = 440;

  /// The photo the footer always keeps clear above its lockup zone.
  static const double footerClearMin = 140;

  /// The page ground fading into the footer photo at its top edge.
  static const double footerTopFade = 40;

  /// The footer lockup zone's bottom edge (top edge is [heroScrimText]).
  static const double footerScrimBottom = 0.92;

  static const Color heroText = Color(0xFFF1F5F9);

  /// Subline and body text on a hero. Never slate-400 (#94A3B8) on a hero.
  static const Color heroTextBody = Color(0xFFCBD5E1);

  /// Accent word: Volt in the dark theme; brand-500 in light (large only).
  static const Color heroAccentDark = volt;
  static const Color heroAccentLight = fgBrand;

  /// Fuel state chip on the hero. The border is 3.6:1 against the 86% zone
  /// over pure white (0.6 gave 2.9:1).
  static const Color heroChipFuelText = fuelOnDark;
  static Color get heroChipFuelBorder => fuelOnDark.withValues(alpha: 0.7);
  static Color get heroChipFuelFill => heroScrim.withValues(alpha: 0.4);

  /// Shown before the photo decodes, under high contrast and on failure.
  static const Color heroPlaceholder = Color(0xFF0B192C);

  /// Partner logo plate on a band (spec §40.2): 40 tall, at most 120 wide,
  /// 6px side padding, the logo inside 108 x 28.
  static const double logoPlateHeight = 40;
  static const double logoPlateMaxWidth = 120;
  static const double logoPlateMinWidth = 40;
  static const double logoPlatePad = 6;
  static const double logoPlateLogoMaxWidth = 108;
  static const double logoPlateLogoMaxHeight = 28;

  /// The phone band keeps this much from its top edge to the top of the
  /// eyebrow while a plate shows (16 + 40 + 12).
  static const double logoPlateReserve = 68;

  /// Light plate (dark or coloured logos): white with a 12% slate-950 edge.
  static const Color logoPlateLight = Color(0xFFFFFFFF);
  static Color get logoPlateLightBorder =>
      const Color(0xFF020617).withValues(alpha: 0.12);

  /// Dark plate (light or white logos): the navy ground with a 40% edge
  /// (full opacity under high contrast).
  static const Color logoPlateDark = heroPlaceholder;
  static const Color logoPlateDarkBorderStrong = Color(0xFFF1F5F9);
  static Color get logoPlateDarkBorder =>
      logoPlateDarkBorderStrong.withValues(alpha: 0.4);

  /// Light theme: the content sheet overlaps the hero by this much.
  static const double heroSheetOverlap = 24;
  static const double heroSheetRadius = radiusXl;

  /// Headline size / line height: 34/36 from 375 wide, 30/32 below.
  static const double heroDisplaySize = 34;
  static const double heroDisplayLine = 36;
  static const double heroDisplaySizeSmall = 30;
  static const double heroDisplayLineSmall = 32;

  /// Panel variant (>= 1024 wide): canon h1.
  static const double heroDisplaySizeWide = 48;
  static const double heroDisplayLineWide = 52;

  /// Hero eyebrow: uppercase mono label, tracking 0.18em.
  static TextStyle heroEyebrow({Color color = heroText}) =>
      monoLabel(color, size: 11).copyWith(letterSpacing: 11 * 0.18);

  // ── Canon role colours (photo hero role tiles, F-6) ──
  static const Color roleMemberLight = Color(0xFF1F7A3A);
  static const Color roleMemberDark = Color(0xFF17B26A);
  static const Color roleTrainer = Color(0xFF3B82F6);
  static const Color roleVendor = Color(0xFFA855F7);

  // ── Muted text on light grounds ──
  // slate-600: 7.0:1 on the #EEF2F7 page, 7.6:1 on white.
  static const Color lightFgMuted = Color(0xFF475569);

  /// Muted secondary text (struck-through prices, hints) for the current
  /// theme: slate-600 on light, slate-400 on dark (6.96:1 on slate-900).
  /// The themes leave `onSurfaceVariant` unset, so it falls back to the
  /// full-strength text colour; use this instead.
  static Color mutedText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkFgMuted
      : lightFgMuted;

  // ── Role-card accent icon colors ──
  static const Color iconAccentGreen = Color(0xFF17B26A);
  static const Color accentOrange = Color(0xFFF79009);
  static const Color accentIndigo = Color(0xFF6366F1);
}

/// Keyboard focus ring for filled controls: a 2px ring drawn *outside* the
/// button so it sits on the page ground, not on the fill. Material's default
/// focus cue (a 10% overlay) is ~1.25:1 on Volt and practically invisible.
/// [color] must contrast >= 3:1 with the page ground.
WidgetStateProperty<BorderSide?> ffFocusRing(Color color) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused) &&
          !states.contains(WidgetState.disabled)) {
        return BorderSide(
          color: color,
          width: 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        );
      }
      return null;
    });

/// Focus ring colour on the dark ground (slate-100 on slate-950: 17:1).
const Color ffFocusRingDark = FFTokens.darkFgPrimary;

/// Focus ring colour on the light ground (slate-900 on #EEF2F7: 15:1).
const Color ffFocusRingLight = Color(0xFF0F172A);

ThemeData buildDarkTheme() {
  const bg = FFTokens.darkBg;
  const surface = FFTokens.darkSurface;
  const onSurface = FFTokens.darkFgPrimary;
  const primary = FFTokens.volt;
  const bord = FFTokens.darkBorder;

  return ThemeData(
    useMaterial3: true,
    fontFamily: FFTokens.fontSans,
    brightness: Brightness.dark,
    extensions: const <ThemeExtension<dynamic>>[FFToneTheme.dark],
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: FFTokens.onVolt,
      secondary: primary,
      onSecondary: FFTokens.onVolt,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surface,
      surfaceContainerLow: Color(0xFF0F1E2E),
      outlineVariant: Color(0xFF1E293B),
      outline: bord,
      error: FFTokens.errorOnDark,
      onError: Colors.black,
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
        foregroundColor: FFTokens.onVolt,
        // Disabled sits on the card colour, never grey-on-Volt.
        disabledBackgroundColor: surface,
        disabledForegroundColor: FFTokens.darkFgMuted,
        // No colour tween: otherwise the label fades grey -> onVolt over
        // Volt for 200ms when a button becomes enabled.
        animationDuration: Duration.zero,
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
      ).copyWith(side: ffFocusRing(ffFocusRingDark)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(side: ffFocusRing(ffFocusRingDark)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(side: ffFocusRing(ffFocusRingDark)),
    ),
    // FABs default to the Volt fill; a 45% onVolt overlay gives >= 3:1
    // between the focused and unfocused fill.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      focusColor: FFTokens.onVolt.withValues(alpha: 0.45),
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
        borderSide: const BorderSide(color: FFTokens.inputBorderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.inputBorderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.errorOnDark),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.errorOnDark, width: 2),
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
      checkColor: WidgetStateProperty.all(FFTokens.onVolt),
      side: const BorderSide(color: bord, width: 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return FFTokens.onVolt;
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
  const primary = FFTokens.brand500; // #067647, 5.7:1 on white
  const onPrimary = Colors.white;
  const bord = Color(0xFFE2E8F0);
  const muted = Color(0xFF64748B);

  return ThemeData(
    useMaterial3: true,
    fontFamily: FFTokens.fontSans,
    brightness: Brightness.light,
    extensions: const <ThemeExtension<dynamic>>[FFToneTheme.light],
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
      ).copyWith(side: ffFocusRing(ffFocusRingLight)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(side: ffFocusRing(ffFocusRingLight)),
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
        borderSide: const BorderSide(color: FFTokens.inputBorderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.inputBorderLight),
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
