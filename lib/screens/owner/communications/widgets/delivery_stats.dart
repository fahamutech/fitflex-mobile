import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../data/communication_models.dart';
import 'comms_format.dart';

/// Per channel: how many messages are waiting, sent, delivered, read or
/// failed, and how many members were skipped. Only real ledger counts are
/// shown — a status with no messages is left out rather than shown as 0.
class DeliveryStats extends StatelessWidget {
  const DeliveryStats({
    super.key,
    required this.progress,
    this.skipped = const {},
  });

  final Map<CommChannel, Map<String, int>> progress;

  /// Why members were skipped (from the send), e.g. { no_device: 12 }.
  final Map<String, int> skipped;

  static const _order = [
    'queued',
    'sending',
    'sent',
    'delivered',
    'read',
    'clicked',
    'failed',
    'skipped',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (progress.isEmpty) {
      return Text(
        context.tr('comms.detail.noDeliveries'),
        style: theme.textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in progress.entries) ...[
          Row(
            children: [
              Icon(
                channelIcon(entry.key),
                size: FFTokens.iconSm,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: FFTokens.spacingXs),
              Text(
                channelLabel(context, entry.key),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Wrap(
            spacing: FFTokens.spacingXs,
            runSpacing: FFTokens.spacingXs,
            children: [
              for (final status in _order)
                if ((entry.value[status] ?? 0) > 0)
                  FFPill(
                    label:
                        '${context.tr('comms.msgStatus.$status')} ${entry.value[status]}',
                  ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
        ],
        if (skipped.isNotEmpty) ...[
          Text(
            context.tr('comms.detail.whySkipped'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          for (final e in skipped.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacing2xs),
              child: Text(
                '${skipReasonLabel(context, e.key)}: ${e.value}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}
