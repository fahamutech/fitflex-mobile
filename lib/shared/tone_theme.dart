import 'package:flutter/material.dart';

/// Colours for one semantic tone (badge, alert, trend chip, ...).
@immutable
class FFToneColors {
  const FFToneColors({
    required this.bg,
    required this.fg,
    required this.border,
    required this.dot,
  });

  final Color bg;
  final Color fg;
  final Color border;
  final Color dot;

  static FFToneColors lerp(FFToneColors a, FFToneColors b, double t) =>
      FFToneColors(
        bg: Color.lerp(a.bg, b.bg, t)!,
        fg: Color.lerp(a.fg, b.fg, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        dot: Color.lerp(a.dot, b.dot, t)!,
      );
}

/// Theme-aware tone palette. Light mode uses pale tints with dark text; dark
/// mode uses the tone blended at ~16% over the dark surface with light text,
/// so badges and alerts no longer glow as pastel blocks on the dark canvas.
/// Every fg/bg pair is >= 4.5:1.
///
/// Read with `FFToneTheme.of(context)`; falls back to the palette for the
/// current brightness when the extension is not installed (bare MaterialApp).
@immutable
class FFToneTheme extends ThemeExtension<FFToneTheme> {
  const FFToneTheme({
    required this.neutral,
    required this.gray,
    required this.brand,
    required this.success,
    required this.danger,
    required this.warning,
    required this.info,
  });

  final FFToneColors neutral;
  final FFToneColors gray;
  final FFToneColors brand;
  final FFToneColors success;
  final FFToneColors danger;
  final FFToneColors warning;
  final FFToneColors info;

  static const light = FFToneTheme(
    neutral: FFToneColors(
      bg: Color(0xFFF2F4F7),
      fg: Color(0xFF475467),
      border: Color(0xFFEAECF0),
      dot: Color(0xFF98A2B3),
    ),
    gray: FFToneColors(
      bg: Color(0xFFF2F4F7),
      fg: Color(0xFF344054),
      border: Color(0xFFEAECF0),
      dot: Color(0xFF667085),
    ),
    brand: FFToneColors(
      bg: Color(0xFFEDFDF3),
      fg: Color(0xFF085D3A),
      border: Color(0xFFAAF4CF),
      dot: Color(0xFF067647),
    ),
    success: FFToneColors(
      bg: Color(0xFFF0FDF9),
      fg: Color(0xFF125D56),
      border: Color(0xFF99F6E0),
      dot: Color(0xFF0E9384),
    ),
    danger: FFToneColors(
      bg: Color(0xFFFEF3F2),
      fg: Color(0xFFB42318),
      border: Color(0xFFFECDCA),
      dot: Color(0xFFDC2626),
    ),
    warning: FFToneColors(
      bg: Color(0xFFFFFAEB),
      fg: Color(0xFFB54708),
      border: Color(0xFFFEDF89),
      dot: Color(0xFFF79009),
    ),
    info: FFToneColors(
      bg: Color(0xFFEFF8FF),
      fg: Color(0xFF175CD3),
      border: Color(0xFFB2DDFF),
      dot: Color(0xFF1570EF),
    ),
  );

  static const dark = FFToneTheme(
    neutral: FFToneColors(
      bg: Color(0xFF1E293B),
      fg: Color(0xFFCBD5E1),
      border: Color(0xFF334155),
      dot: Color(0xFF94A3B8),
    ),
    gray: FFToneColors(
      bg: Color(0xFF162438),
      fg: Color(0xFFCDD5DF),
      border: Color(0xFF1F3350),
      dot: Color(0xFF8899AA),
    ),
    brand: FFToneColors(
      bg: Color(0xFF103034),
      fg: Color(0xFF75E7B3),
      border: Color(0xFF12493E),
      dot: Color(0xFF17B26A),
    ),
    success: FFToneColors(
      bg: Color(0xFF0F2B38),
      fg: Color(0xFF5FE9D0),
      border: Color(0xFF0F3F47),
      dot: Color(0xFF15B79E),
    ),
    danger: FFToneColors(
      bg: Color(0xFF331E2C),
      fg: Color(0xFFFDA29B),
      border: Color(0xFF57252E),
      dot: Color(0xFFF97066),
    ),
    warning: FFToneColors(
      bg: Color(0xFF342A25),
      fg: Color(0xFFFEC84B),
      border: Color(0xFF593E20),
      dot: Color(0xFFF79009),
    ),
    info: FFToneColors(
      bg: Color(0xFF142A4B),
      fg: Color(0xFF84CAFF),
      border: Color(0xFF193E6C),
      dot: Color(0xFF2E90FA),
    ),
  );

  static FFToneTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<FFToneTheme>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  FFToneTheme copyWith({
    FFToneColors? neutral,
    FFToneColors? gray,
    FFToneColors? brand,
    FFToneColors? success,
    FFToneColors? danger,
    FFToneColors? warning,
    FFToneColors? info,
  }) => FFToneTheme(
    neutral: neutral ?? this.neutral,
    gray: gray ?? this.gray,
    brand: brand ?? this.brand,
    success: success ?? this.success,
    danger: danger ?? this.danger,
    warning: warning ?? this.warning,
    info: info ?? this.info,
  );

  @override
  FFToneTheme lerp(ThemeExtension<FFToneTheme>? other, double t) {
    if (other is! FFToneTheme) return this;
    return FFToneTheme(
      neutral: FFToneColors.lerp(neutral, other.neutral, t),
      gray: FFToneColors.lerp(gray, other.gray, t),
      brand: FFToneColors.lerp(brand, other.brand, t),
      success: FFToneColors.lerp(success, other.success, t),
      danger: FFToneColors.lerp(danger, other.danger, t),
      warning: FFToneColors.lerp(warning, other.warning, t),
      info: FFToneColors.lerp(info, other.info, t),
    );
  }
}
