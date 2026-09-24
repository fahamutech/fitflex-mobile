import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../home_feed.dart';
import '../member_log_activity_page.dart' show openLogActivity;
import 'gym_card.dart';
import 'trainer_card.dart';

/// Streak worth mentioning today: about to break, a milestone, a personal
/// best, or one that just ended.
class HomeStreakCard extends StatelessWidget {
  const HomeStreakCard({super.key, required this.pick});

  final HomeCardPick pick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = pick.streak!;
    final ended = pick.reason == HomeReason.streakEnded;
    final n = ended ? s.endedLength ?? 0 : s.current;
    final key = switch (pick.reason) {
      HomeReason.streakAtRisk => 'atRisk',
      HomeReason.streakMilestone => 'milestone',
      HomeReason.streakBest => 'best',
      _ => 'ended',
    };
    return FFCard(
      key: const Key('home-streak'),
      child: Row(
        children: [
          Icon(
            ended ? Icons.restart_alt : Icons.local_fire_department,
            size: 36,
            color: ended
                ? theme.colorScheme.onSurfaceVariant
                : FFTokens.warning500,
          ),
          const SizedBox(width: FFTokens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context
                      .tr(
                        ended ? 'home.streak.endedTitle' : 'home.streak.title',
                      )
                      .replaceAll('{n}', '$n'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  context.tr('home.streak.$key'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('home-streak-open'),
            tooltip: context.tr('activity.view'),
            // At risk or just ended: straight to logging, which is what
            // keeps (or restarts) it.
            onPressed: () =>
                pick.reason == HomeReason.streakAtRisk ||
                    pick.reason == HomeReason.streakEnded
                ? openLogActivity(context)
                : context.go(AppRoutes.memberActivity),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// One gym or trainer, with the reason it's suggested.
class HomeRecommendation extends StatelessWidget {
  const HomeRecommendation({super.key, required this.pick, this.distanceKm});

  final HomeCardPick pick;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gym = pick.gym;
    final trainer = pick.trainer;
    final why = switch (pick.reason) {
      HomeReason.gymUsePass => 'home.why.gymUsePass',
      HomeReason.gymTryNew => 'home.why.gymTryNew',
      HomeReason.trainerRegular => 'home.why.trainerRegular',
      _ => 'home.why.gymExplore',
    };
    return Column(
      key: const Key('home-recommendation'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: FFSectionTitle(context.tr('home.recommended'))),
            TextButton(
              onPressed: () => context.go(
                gym != null ? AppRoutes.memberGyms : AppRoutes.memberTrainers,
              ),
              child: Text(context.tr('home.seeAll')),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Text(context.tr(why), style: theme.textTheme.bodySmall),
        ),
        if (gym != null)
          GymCard(gym: gym, distanceKm: distanceKm)
        else if (trainer != null)
          TrainerCard(trainer: trainer),
      ],
    );
  }
}
