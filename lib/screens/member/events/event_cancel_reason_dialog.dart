import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_order.dart';
import '../../../shared/i18n.dart';

/// "Cancel this order?" / "Remove {name}?" with the closed set of reasons
/// (events S3 spec §3.8, §5.7, §5.9). Resolves with the chosen reason, or
/// null when dismissed.
Future<String?> showEventCancelReasonDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) =>
        _ReasonDialog(title: title, body: body, confirmLabel: confirmLabel),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final String title;
  final String body;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  String _reason = memberCancelReasons.first;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('event-cancel-dialog'),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.body, style: tt.bodyMedium),
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('events.order.cancel.reason'),
              style: tt.titleSmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            for (final r in memberCancelReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: FFChoiceTile(
                  key: Key('cancel-reason-$r'),
                  title: context.tr('events.order.cancel.reason.$r'),
                  selected: _reason == r,
                  minHeight: 48,
                  onSelected: () => setState(() => _reason = r),
                ),
              ),
          ],
        ),
      ),
      actions: [
        FFButton(
          key: const Key('event-cancel-dismiss'),
          label: context.tr('common.close'),
          variant: FFButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        FFButton(
          key: const Key('event-cancel-confirm'),
          label: widget.confirmLabel,
          variant: FFButtonVariant.destructive,
          onPressed: () => Navigator.of(context).pop(_reason),
        ),
      ],
    );
  }
}
