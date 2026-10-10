import 'package:flutter/material.dart';
import '../design_tokens.dart';
import '../tone_theme.dart';

enum _SnackTone { success, error, info, warning }

/// Themed snackbars. One at a time: showing a new one replaces the old.
///
/// ```dart
/// FFSnack.success(context, 'Saved');
/// FFSnack.error(context, 'Could not save', actionLabel: 'Retry', onAction: save);
/// ```
class FFSnack {
  FFSnack._();

  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(context, _SnackTone.success, message, actionLabel, onAction);

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(context, _SnackTone.error, message, actionLabel, onAction);

  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(context, _SnackTone.info, message, actionLabel, onAction);

  static void warning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(context, _SnackTone.warning, message, actionLabel, onAction);

  static void _show(
    BuildContext context,
    _SnackTone tone,
    String message,
    String? actionLabel,
    VoidCallback? onAction,
  ) {
    final theme = Theme.of(context);
    final tones = FFToneTheme.of(context);
    final (IconData icon, FFToneColors c) = switch (tone) {
      _SnackTone.success => (Icons.check_circle_outline, tones.success),
      _SnackTone.error => (Icons.error_outline, tones.danger),
      _SnackTone.warning => (Icons.warning_amber_rounded, tones.warning),
      _SnackTone.info => (Icons.info_outline, tones.info),
    };
    final bg = c.bg;
    final fg = c.fg;
    final iconColor = c.fg;
    final border = c.border;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        elevation: 2,
        duration: Duration(seconds: tone == _SnackTone.error ? 6 : 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          side: BorderSide(color: border),
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: fg,
                onPressed: onAction,
              )
            : null,
        content: Semantics(
          liveRegion: true,
          container: true,
          child: Row(
            children: [
              ExcludeSemantics(child: Icon(icon, color: iconColor, size: 22)),
              const SizedBox(width: FFTokens.spacingSm + 4),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
