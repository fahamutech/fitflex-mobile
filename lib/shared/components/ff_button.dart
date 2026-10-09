import 'package:flutter/material.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import 'ff_spinner.dart';

/// Visual weight of an [FFButton].
enum FFButtonVariant { primary, secondary, ghost, destructive }

/// Height step of an [FFButton]. `sm` is 40dp tall but still has a 48dp hit
/// area; `md` and `lg` are 48 and 52dp.
enum FFButtonSize { sm, md, lg }

/// The standard button. Wraps the themed Filled / Outlined / Text buttons so
/// it looks like the rest of the app in light and dark.
class FFButton extends StatelessWidget {
  const FFButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = FFButtonVariant.primary,
    this.size = FFButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final FFButtonVariant variant;
  final FFButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;

  /// Shows a spinner in place of the content, ignores taps and keeps the
  /// button the same width.
  final bool loading;
  final bool fullWidth;
  final String? tooltip;

  double get _minHeight => switch (size) {
    FFButtonSize.sm => 40,
    FFButtonSize.md => 48,
    FFButtonSize.lg => 52,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sm = size == FFButtonSize.sm;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(sm ? 64 : 88, _minHeight)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: sm ? FFTokens.spacingMd : 20,
          vertical: sm ? FFTokens.spacingSm : FFTokens.spacingSm + 4,
        ),
      ),
      // Keeps a 48dp hit area around the smaller button.
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    final destructiveStyle = variant == FFButtonVariant.destructive
        ? style.merge(
            FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
          )
        : style;

    // While loading the callback stays non-null so the button keeps its
    // enabled colours, but it does nothing.
    final VoidCallback? handler = onPressed == null
        ? null
        : (loading ? () {} : onPressed);

    final content = Builder(
      builder: (ctx) {
        final fg = DefaultTextStyle.of(ctx).style.color;
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: FFTokens.iconMd),
              const SizedBox(width: FFTokens.spacingSm),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: FFTokens.spacingSm),
              Icon(trailingIcon, size: FFTokens.iconMd),
            ],
          ],
        );
        if (!loading) return row;
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(opacity: 0, child: row),
            FFSpinner(size: FFTokens.iconMd, color: fg),
          ],
        );
      },
    );

    Widget button = switch (variant) {
      FFButtonVariant.primary => FilledButton(
        onPressed: handler,
        style: style,
        child: content,
      ),
      FFButtonVariant.destructive => FilledButton(
        onPressed: handler,
        style: destructiveStyle,
        child: content,
      ),
      FFButtonVariant.secondary => OutlinedButton(
        onPressed: handler,
        style: style,
        child: content,
      ),
      FFButtonVariant.ghost => TextButton(
        onPressed: handler,
        style: style,
        child: content,
      ),
    };

    button = Semantics(
      container: true,
      button: true,
      enabled: handler != null,
      label: label,
      value: loading ? context.tr('common.loading') : null,
      excludeSemantics: true,
      onTap: handler,
      child: button,
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    if (fullWidth) {
      button = SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
