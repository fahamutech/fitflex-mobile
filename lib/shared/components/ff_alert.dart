import 'package:flutter/material.dart';
import '../design_tokens.dart';

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
    final (Color bg, Color border, Color fg) = switch (tone) {
      FFAlertTone.info => (
        FFTokens.brand50,
        FFTokens.brand200,
        FFTokens.brand800,
      ),
      FFAlertTone.success => (
        FFTokens.success50,
        FFTokens.success200,
        FFTokens.success700,
      ),
      FFAlertTone.warning => (
        FFTokens.warning50,
        FFTokens.warning200,
        FFTokens.warning700,
      ),
      FFAlertTone.error => (
        FFTokens.error50,
        FFTokens.error200,
        FFTokens.error700,
      ),
    };

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
