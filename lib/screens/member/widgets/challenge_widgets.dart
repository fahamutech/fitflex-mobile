import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../router.dart';
import '../../../shared/activity/challenge.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'activity_widgets.dart' show formatSteps;

String challengeRoute(String id) => AppRoutes.memberChallenge.replaceFirst(
  ':challengeId',
  Uri.encodeComponent(id),
);

/// "32,450" / "12.5 km" / "18 days" — a challenge amount in its unit.
String challengeAmount(BuildContext context, ChallengeType type, num v) {
  String n(num x) =>
      x == x.roundToDouble() ? formatSteps(x.round()) : x.toStringAsFixed(1);
  return switch (type) {
    ChallengeType.distanceKm => '${n(v)} km',
    _ => n(v),
  };
}

/// Nearest whole percent, but never 100 until the target is reached.
int challengePercent(double fraction, bool reached) {
  final pct = (fraction * 100).round();
  return reached ? pct : pct.clamp(0, 99);
}

/// "50,000 steps", "20 km", "10 active days".
String challengeTargetText(BuildContext context, ChallengeType type, num v) =>
    '${challengeAmount(context, type, v)} ${challengeUnit(context, type)}'
        .trim();

/// "steps", "workouts", "active days"… — the unit after a target.
String challengeUnit(BuildContext context, ChallengeType type) =>
    context.tr('challenge.unit.${type.wire}');

/// "By FitFlex", "By Coach Sarah", "By Mikocheni Fitness", "By your company".
String challengeCreatorLabel(BuildContext context, Challenge c) {
  final name = c.creatorName;
  return switch (c.creatorType) {
    ChallengeCreator.trainer || ChallengeCreator.gym when name != null =>
      context.tr('challenge.by').replaceAll('{name}', name),
    ChallengeCreator.corporate => context.tr('challenge.byCompany'),
    ChallengeCreator.fitflex => context.tr('challenge.byFitflex'),
    _ => context.tr('challenge.byPartner'),
  };
}

/// "Ends in 4 days", "Ends today", "Starts in 2 days", "Ended 3 Oct".
String challengeWhen(BuildContext context, Challenge c, DateTime now) {
  switch (c.phase) {
    case ChallengePhase.upcoming:
      final d = c.daysUntilStart(now);
      return d <= 1
          ? context.tr('challenge.startsTomorrow')
          : context.tr('challenge.startsIn').replaceAll('{n}', '$d');
    case ChallengePhase.active:
      final d = c.daysLeft(now);
      return d <= 1
          ? context.tr('challenge.endsToday')
          : context.tr('challenge.endsIn').replaceAll('{n}', '$d');
    case ChallengePhase.ended:
      return context
          .tr('challenge.endedOn')
          .replaceAll('{date}', DateFormat('d MMM').format(c.endDate));
    case ChallengePhase.cancelled:
      return context.tr('challenge.cancelled');
  }
}

/// The card from the brief: name, "32,450 / 50,000", a bar, "65%",
/// "Ends in 4 days", and a way into the challenge.
class ChallengeCard extends StatelessWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    required this.now,
    this.progress,
    this.showView = true,
  });

  final Challenge challenge;
  final DateTime now;

  /// False on the challenge's own page.
  final bool showView;

  /// Null when not joined — shows the target instead of progress.
  final num? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = challenge;
    final p = progress;
    final fraction = p == null || c.target <= 0
        ? 0.0
        : (p / c.target).toDouble();
    final reached = p != null && p >= c.target;
    return FFCard(
      key: Key('challenge-card-${c.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      challengeCreatorLabel(context, c),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (reached)
                FFPill(label: context.tr('challenge.completed'), filled: true),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (p != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    '${challengeAmount(context, c.type, p)} / ${challengeAmount(context, c.type, c.target)}',
                    key: const Key('challenge-progress'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${challengePercent(fraction, reached)}%',
                  key: const Key('challenge-percent'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingXs),
            ClipRRect(
              borderRadius: BorderRadius.circular(FFTokens.radiusFull),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ] else
            Text(
              '${challengeTargetText(context, c.type, c.target)} · ${context.tr('challenge.participants').replaceAll('{n}', '${c.participantCount}')}',
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: FFTokens.spacingSm),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: FFTokens.iconSm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: FFTokens.spacingXs),
              Expanded(
                child: Text(
                  challengeWhen(context, c, now),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (showView)
                TextButton(
                  key: Key('challenge-view-${c.id}'),
                  onPressed: () => context.go(challengeRoute(c.id)),
                  child: Text(context.tr('challenge.view')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Activity → Challenges: Active, Completed and Available.
List<Widget> buildChallengesSection(
  BuildContext context,
  MemberData data,
  DateTime now,
) {
  if (!data.challengesLoaded) {
    return const [Center(child: CircularProgressIndicator())];
  }
  final g = groupChallenges(
    data.challenges,
    data.activities,
    checkIns: data.checkInMoments,
  );
  if (g.active.isEmpty && g.completed.isEmpty && g.available.isEmpty) {
    return [
      FFEmptyState(
        key: const Key('challenges-empty'),
        title: context.tr('challenge.none'),
        body: context.tr('challenge.noneBody'),
      ),
    ];
  }
  Widget empty(String key) => Padding(
    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
    child: Text(context.tr(key), style: Theme.of(context).textTheme.bodySmall),
  );
  return [
    FFSectionTitle(context.tr('challenge.active')),
    if (g.active.isEmpty) empty('challenge.noActive'),
    for (final s in g.active)
      ChallengeCard(challenge: s.challenge, progress: s.progress, now: now),
    FFSectionTitle(context.tr('challenge.available')),
    if (g.available.isEmpty) empty('challenge.noAvailable'),
    for (final c in g.available) ChallengeCard(challenge: c, now: now),
    if (g.completed.isNotEmpty) ...[
      FFSectionTitle(context.tr('challenge.completedList')),
      for (final s in g.completed)
        ChallengeCard(challenge: s.challenge, progress: s.progress, now: now),
    ],
  ];
}

/// Overview → Current challenge: the one ending soonest, or an invitation.
Widget currentChallengeBlock(
  BuildContext context,
  MemberData data,
  DateTime now,
) {
  final g = groupChallenges(
    data.challenges,
    data.activities,
    checkIns: data.checkInMoments,
  );
  if (g.active.isNotEmpty) {
    final s = g.active.first;
    return ChallengeCard(
      challenge: s.challenge,
      progress: s.progress,
      now: now,
    );
  }
  if (g.available.isNotEmpty) {
    return ChallengeCard(challenge: g.available.first, now: now);
  }
  return FFEmptyState(
    key: const Key('activity-no-challenge'),
    title: context.tr('activity.noChallenge'),
    body: context.tr('challenge.noneBody'),
  );
}
