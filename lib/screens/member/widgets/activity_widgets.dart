import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/activity/activity.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../router.dart';
import '../../../shared/i18n.dart';

IconData activityTypeIcon(ActivityType type) => switch (type) {
  ActivityType.walking => Icons.directions_walk,
  ActivityType.running || ActivityType.jogging => Icons.directions_run,
  ActivityType.cycling => Icons.directions_bike,
  ActivityType.hiking => Icons.hiking,
  ActivityType.swimming => Icons.pool,
  ActivityType.sports => Icons.sports_soccer,
  ActivityType.strength => Icons.fitness_center,
  ActivityType.hiit => Icons.bolt,
  ActivityType.functional => Icons.sports_gymnastics,
  ActivityType.groupClass => Icons.groups_outlined,
  ActivityType.personalTraining => Icons.person_outline,
  ActivityType.mobility || ActivityType.stretching => Icons.self_improvement,
  ActivityType.other => Icons.timeline,
};

String activityTypeLabel(BuildContext context, ActivityType type) =>
    context.tr('activity.type.${type.wire}');

String formatSteps(int steps) => formatMoney(steps);

String formatKm(double km) => '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';

/// Flags generated numbers so members never mistake them for real tracking.
class ActivitySampleBadge extends StatelessWidget {
  const ActivitySampleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.tr('activity.sampleHint'),
      child: FFPill(
        key: const Key('activity-sample-badge'),
        label: context.tr('activity.sample'),
      ),
    );
  }
}

/// One row in the activity timeline.
class ActivityTimelineTile extends StatelessWidget {
  const ActivityTimelineTile({super.key, required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final parts = <String>[
      DateFormat('EEE d MMM · HH:mm').format(a.startedAt.toLocal()),
      if (a.durationMinutes != null)
        '${a.durationMinutes} ${context.tr('activity.min')}',
      if (a.distanceKm != null && a.distanceKm! > 0) formatKm(a.distanceKm!),
      if (a.steps != null && a.type == ActivityType.walking)
        '${formatSteps(a.steps!)} ${context.tr('activity.steps').toLowerCase()}',
    ];
    final workoutId = a.workoutId;
    return FFActionTile(
      icon: activityTypeIcon(a.type),
      // A finished workout is recorded under its own name.
      title: workoutId != null && (a.notes ?? '').isNotEmpty
          ? a.notes!
          : activityTypeLabel(context, a.type),
      subtitle: parts.join(' · '),
      onTap: workoutId == null
          ? () {}
          : () => context.go(
              AppRoutes.memberWorkout.replaceFirst(
                ':workoutId',
                Uri.encodeComponent(workoutId),
              ),
            ),
    );
  }
}

/// Labelled progress bar toward the daily step goal.
class ActivityGoalBar extends StatelessWidget {
  const ActivityGoalBar({
    super.key,
    required this.steps,
    required this.goal,
    this.dense = false,
  });

  final int steps;
  final int goal;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = goal <= 0 ? 0.0 : steps / goal;
    final percent = (progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(FFTokens.radiusFull),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: dense ? 6 : 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(
          context.tr('activity.ofGoal').replaceAll('{percent}', '$percent'),
          key: const Key('activity-goal-percent'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
