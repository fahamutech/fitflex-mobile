import 'package:flutter/material.dart';
import '../i18n.dart';
import 'ff_button.dart';

/// Yes/no dialog. Resolves `true` only when confirmed; dismissing counts as
/// cancel. Labels default to the shared Cancel / Confirm strings.
Future<bool> showFFConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  bool barrierDismissible = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        FFButton(
          label: cancelLabel ?? ctx.tr('common.cancel'),
          variant: FFButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        FFButton(
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
