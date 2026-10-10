import 'package:flutter/material.dart';
import '../design_tokens.dart';
import '../tone_theme.dart';

/// Alert tone matching portal's AlertTone.
enum FFAlertTone { info, success, warning, error }

/// Inline feedback banner — matches portal's Alert component.
class FFAlert extends StatelessWidget {
  const FFAlert({
    super.key,
    required this.message,
    this.tone = FFAlertTone.info,
  });

  final String message;
  final FFAlertTone tone;

  @override
  Widget build(BuildContext context) {
    final tones = FFToneTheme.of(context);
    final c = switch (tone) {
      FFAlertTone.info => tones.info,
      FFAlertTone.success => tones.success,
      FFAlertTone.warning => tones.warning,
      FFAlertTone.error => tones.danger,
    };
    final (bg, border, fg) = (c.bg, c.border, c.fg);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingMd,
        vertical: FFTokens.spacingSm + 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
      ),
    );
  }
}
