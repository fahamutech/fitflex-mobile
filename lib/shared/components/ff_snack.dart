import 'package:flutter/material.dart';
import '../design_tokens.dart';

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
    final dark = theme.brightness == Brightness.dark;
    final (
      IconData icon,
      Color s50,
      Color s200,
      Color s500,
      Color s700,
    ) = switch (tone) {
      _SnackTone.success => (
        Icons.check_circle_outline,
        FFTokens.success50,
        FFTokens.success200,
        FFTokens.success500,
        FFTokens.success700,
      ),
      _SnackTone.error => (
        Icons.error_outline,
        FFTokens.error50,
        FFTokens.error200,
        FFTokens.error500,
        FFTokens.error700,
      ),
      _SnackTone.warning => (
        Icons.warning_amber_rounded,
        FFTokens.warning50,
        FFTokens.warning200,
        FFTokens.warning500,
        FFTokens.warning700,
      ),
      _SnackTone.info => (
        Icons.info_outline,
        FFTokens.brand50,
        FFTokens.brand200,
        FFTokens.brand500,
        FFTokens.brand800,
      ),
    };
    // Light: pale tint with dark text. Dark: the tone tinted over the
    // surface with normal on-surface text and a light icon.
    final bg = dark
        ? Color.alphaBlend(
            s500.withValues(alpha: 0.22),
            theme.colorScheme.surface,
          )
        : s50;
    final fg = dark ? theme.colorScheme.onSurface : s700;
    final iconColor = dark ? s200 : s700;
    final border = dark ? s500.withValues(alpha: 0.5) : s200;

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
