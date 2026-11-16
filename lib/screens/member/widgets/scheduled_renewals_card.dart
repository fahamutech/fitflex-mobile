import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';

/// The line for one renewal waiting to start: the pass tier, or the gym when
/// its name is known (else a generic gym-plan line).
String scheduledRenewalText(
  BuildContext context,
  ScheduledRenewal renewal, {
  List<Gym> gyms = const [],
}) {
  final date = context.localDate(renewal.startsAt);
  if (renewal.isGymPlan) {
    final gym = gyms.where((g) => g.id == renewal.homeGymId).firstOrNull;
    final name = gym?.name.trim() ?? '';
    if (name.isEmpty) {
      return context
          .tr('renewal.nextGymPlanGeneric')
          .replaceFirst('{date}', date);
    }
    return context
        .tr('renewal.nextGymPlan')
        .replaceFirst('{gym}', name)
        .replaceFirst('{date}', date);
  }
  final tier = renewal.tier ?? '';
  return context
      .tr('renewal.nextPass')
      .replaceFirst('{tier}', tier.isEmpty ? '' : context.tr('pass.$tier'))
      .replaceFirst('{date}', date);
}

/// "Your next plan starts on …", one card per renewal waiting for the current
/// plan to end (SCHEDULED_RENEWALS). Nothing when there are none.
class ScheduledRenewalsCards extends StatelessWidget {
  const ScheduledRenewalsCards({
    super.key,
    required this.renewals,
    this.gyms = const [],
  });

  final List<ScheduledRenewal> renewals;
  final List<Gym> gyms;

  @override
  Widget build(BuildContext context) {
    if (renewals.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in renewals)
          FFCard(
            key: Key('scheduled-renewal-${r.id}'),
            child: Row(
              children: [
                Icon(
                  Icons.event_repeat_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: Text(
                    scheduledRenewalText(context, r, gyms: gyms),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
