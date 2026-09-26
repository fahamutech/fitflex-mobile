import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../data/communication_models.dart';
import 'comms_format.dart';

/// Status badge for a campaign.
class CampaignStatusPill extends StatelessWidget {
  const CampaignStatusPill(this.status, {super.key});

  final CampaignStatus status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      CampaignStatus.draft => FFBadgeTone.gray,
      CampaignStatus.scheduled => FFBadgeTone.warning,
      CampaignStatus.sending => FFBadgeTone.brand,
      CampaignStatus.sent => FFBadgeTone.success,
      CampaignStatus.partiallyFailed => FFBadgeTone.warning,
      CampaignStatus.failed => FFBadgeTone.danger,
      CampaignStatus.cancelled => FFBadgeTone.gray,
    };
    return FFBadge(
      label: context.tr('comms.status.${status.wire}'),
      tone: tone,
      dot: status == CampaignStatus.sending,
    );
  }
}

/// One campaign in a list: title, purpose, when, status and reach.
class CampaignTile extends StatelessWidget {
  const CampaignTile({super.key, required this.campaign, required this.onTap});

  final Campaign campaign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = campaign;
    final when = switch (c.status) {
      CampaignStatus.scheduled when c.scheduledAt != null =>
        context
            .tr('comms.scheduledFor')
            .replaceFirst('{when}', formatWhen(context, c.scheduledAt!)),
      _ when c.sentAt != null => formatWhen(context, c.sentAt!),
      _ when c.createdAt != null => formatWhen(context, c.createdAt!),
      _ => '',
    };
    final reached = c.counts?.targeted;
    return FFCard(
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: InkWell(
        key: Key('campaign-${c.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.displayTitle.isEmpty
                        ? context.tr('comms.untitled')
                        : c.displayTitle,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: FFTokens.spacing2xs),
                  Text(
                    [
                      if (c.purpose != null)
                        context.tr('comms.purpose.${c.purpose!.name}'),
                      if (when.isNotEmpty) when,
                      if (reached != null)
                        context
                            .tr('comms.membersCount')
                            .replaceFirst('{n}', '$reached'),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            CampaignStatusPill(c.status),
          ],
        ),
      ),
    );
  }
}
