import 'package:flutter/material.dart';
import '../i18n.dart';
import 'ff_button.dart';

/// Yes/no dialog. Resolves `true` only when confirmed; dismissing counts as
/// cancel. Labels default to the shared Cancel / Confirm strings. [title] may
/// be omitted for a one-line question; [confirmKey] and [cancelKey] let tests
/// and integrations find the buttons.
Future<bool> showFFConfirmDialog(
  BuildContext context, {
  String? title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  bool barrierDismissible = true,
  Key? confirmKey,
  Key? cancelKey,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AlertDialog(
      title: title == null ? null : Text(title),
      content: message == null ? null : Text(message),
      actions: [
        FFButton(
          key: cancelKey,
          label: cancelLabel ?? ctx.tr('common.cancel'),
          variant: FFButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        FFButton(
          key: confirmKey,
          label: confirmLabel ?? ctx.tr('common.confirm'),
          variant: destructive
              ? FFButtonVariant.destructive
              : FFButtonVariant.primary,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// The sign-in error dialog shared by Sign in, Sign up and email sign-in:
/// a translated title, the [message] and a translated Close button.
/// [onClose] runs after the dialog is closed with the button.
Future<void> showFFAuthErrorDialog(
  BuildContext context,
  String message, {
  VoidCallback? onClose,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('auth-error-dialog'),
      title: Text(ctx.tr('auth.errorDialog.title')),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('auth-error-close'),
          onPressed: () {
            Navigator.of(ctx).pop();
            onClose?.call();
          },
          child: Text(ctx.tr('common.close')),
        ),
      ],
    ),
  );
}
