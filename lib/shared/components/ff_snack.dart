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
    _present(
      ScaffoldMessenger.of(context),
      Theme.of(context),
      FFToneTheme.of(context),
      tone,
      message,
      actionLabel,
      onAction,
    );
  }

  /// Captures the messenger and the current theme now, for code that shows
  /// a snackbar after an `await` (when the context may no longer be safe to
  /// use).
  ///
  /// ```dart
  /// final snack = FFSnack.of(context);
  /// await save();
  /// snack.success('Saved');
  /// ```
  static FFSnackMessenger of(BuildContext context) => FFSnackMessenger._(
    ScaffoldMessenger.of(context),
    Theme.of(context),
    FFToneTheme.of(context),
  );

  static void _present(
    ScaffoldMessengerState messenger,
    ThemeData theme,
    FFToneTheme tones,
    _SnackTone tone,
    String message,
    String? actionLabel,
    VoidCallback? onAction,
  ) {
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

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        elevation: 2,
        duration: Duration(seconds: tone == _SnackTone.error ? 6 : 4),
        // A snackbar with an action would otherwise stay until dismissed
        // (Flutter's default) and follow the user to other screens.
        persist: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          side: BorderSide(color: border),
        ),
        // The action is drawn here rather than as a SnackBarAction, whose
        // button is 36dp tall on web/desktop: this one is 48x48 (AC-46).
        content: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(icon, color: iconColor, size: 22),
                    ),
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
            if (actionLabel != null && onAction != null)
              TextButton(
                key: const Key('ff-snack-action'),
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  minimumSize: const Size(48, 48),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  onAction();
                },
                child: Text(actionLabel),
              ),
          ],
        ),
      ),
    );
  }
}

/// A snackbar presenter that already holds its messenger and theme. See
/// [FFSnack.of].
class FFSnackMessenger {
  FFSnackMessenger._(this._messenger, this._theme, this._tones);

  final ScaffoldMessengerState _messenger;
  final ThemeData _theme;
  final FFToneTheme _tones;

  void success(String message, {String? actionLabel, VoidCallback? onAction}) =>
      FFSnack._present(
        _messenger,
        _theme,
        _tones,
        _SnackTone.success,
        message,
        actionLabel,
        onAction,
      );

  void error(String message, {String? actionLabel, VoidCallback? onAction}) =>
      FFSnack._present(
        _messenger,
        _theme,
        _tones,
        _SnackTone.error,
        message,
        actionLabel,
        onAction,
      );

  void info(String message, {String? actionLabel, VoidCallback? onAction}) =>
      FFSnack._present(
        _messenger,
        _theme,
        _tones,
        _SnackTone.info,
        message,
        actionLabel,
        onAction,
      );

  void warning(String message, {String? actionLabel, VoidCallback? onAction}) =>
      FFSnack._present(
        _messenger,
        _theme,
        _tones,
        _SnackTone.warning,
        message,
        actionLabel,
        onAction,
      );
}
