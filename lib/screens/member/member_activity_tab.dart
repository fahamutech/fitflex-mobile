import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/activity/activity.dart';
import '../../shared/activity/activity_summary.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/activity_widgets.dart';

/// Member Activity tab: Overview · Workouts · Challenges · Progress.
class MemberActivityTab extends StatefulWidget {
  const MemberActivityTab({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<MemberActivityTab> createState() => _MemberActivityTabState();
}

class _MemberActivityTabState extends State<MemberActivityTab> {
  String _section = 'overview';

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final today = widget.now ?? DateTime.now();

    return ListView(
      key: const Key('activity-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFPageHeader(
          title: context.tr('activity.title'),
          actions: data.activityIsSample ? const ActivitySampleBadge() : null,
        ),
        SizedBox(
          width: double.infinity,
          child: FFSegmented(
            key: const Key('activity-sections'),
            value: _section,
            options: [
              ('overview', context.tr('activity.overview')),
              ('workouts', context.tr('activity.workouts')),
              ('challenges', context.tr('activity.challenges')),
              ('progress', context.tr('activity.progress')),
            ],
            onChanged: (v) => setState(() => _section = v),
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (!data.activityLoaded)
          const Padding(
            padding: EdgeInsets.all(FFTokens.spacingXl),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ...switch (_section) {
            'workouts' => _workouts(context, data.activities),
            'challenges' => _challenges(context),
            'progress' => _progress(context, data.activities, today),
            _ => _overview(context, data.activities, today),
          },
      ],
    );
  }

  List<Widget> _overview(
    BuildContext context,
    List<Activity> activities,
    DateTime today,
  ) {
    final s = summarizeDay(activities, today);
    final streak = currentStreak(activities, today: today);
    final recent = activities.take(8).toList();
    return [
      FFSectionTitle(context.tr('activity.today')),
      _TileRow(
        left: FFStatTile(
          icon: Icons.directions_walk,
          value: formatSteps(s.steps),
          label: context.tr('activity.steps'),
        ),
        right: FFStatTile(
          icon: Icons.straighten,
          value: formatKm(s.distanceKm),
          label: context.tr('activity.distance'),
        ),
      ),
      _TileRow(
        left: FFStatTile(
          icon: Icons.timer_outlined,
          value: '${s.activeMinutes}',
          label: context.tr('activity.activeMinutes'),
        ),
        right: FFStatTile(
          icon: Icons.local_fire_department_outlined,
          value: s.calories == null ? '—' : formatSteps(s.calories!),
          label: context.tr('activity.calories'),
        ),
      ),
      _TileRow(
        left: FFStatTile(
          icon: Icons.timeline,
          value: '${s.activityCount}',
          label: context.tr('activity.activities'),
        ),
        right: FFStatTile(
          icon: Icons.fitness_center,
          value: '${s.workoutCount}',
          label: context.tr('activity.workoutCount'),
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFCard(
        key: const Key('activity-daily-goal'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('activity.dailyGoal'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              '${formatSteps(s.steps)} / ${formatSteps(defaultDailyStepGoal)}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            ActivityGoalBar(steps: s.steps, goal: defaultDailyStepGoal),
          ],
        ),
      ),
      FFMetricCard(
        key: const Key('activity-streak'),
        label: context.tr('activity.streak'),
        value: context.tr('activity.dayStreak').replaceAll('{n}', '$streak'),
        sub: context.tr('activity.streakHint'),
        icon: const Icon(
          Icons.local_fire_department,
          color: FFTokens.warning500,
        ),
      ),
      FFSectionTitle(context.tr('activity.currentChallenge')),
      ..._challenges(context),
      FFSectionTitle(context.tr('activity.recent')),
      if (recent.isEmpty)
        FFEmptyState(title: context.tr('activity.noActivity'))
      else
        ...recent.map((a) => ActivityTimelineTile(activity: a)),
    ];
  }

  List<Widget> _workouts(BuildContext context, List<Activity> activities) {
    final workouts = activities.where((a) => a.isWorkout).toList();
    if (workouts.isEmpty) {
      return [FFEmptyState(title: context.tr('activity.noWorkouts'))];
    }
    return workouts.map((a) => ActivityTimelineTile(activity: a)).toList();
  }

  List<Widget> _challenges(BuildContext context) => [
    FFEmptyState(
      key: const Key('activity-no-challenge'),
      title: context.tr('activity.noChallenge'),
      body: context.tr('activity.challengesSoon'),
    ),
  ];

  List<Widget> _progress(
    BuildContext context,
    List<Activity> activities,
    DateTime today,
  ) {
    final days = summarizeDays(activities, today: today).reversed.toList();
    final theme = Theme.of(context);
    final steps = days.fold<int>(0, (t, d) => t + d.steps);
    final minutes = days.fold<int>(0, (t, d) => t + d.activeMinutes);
    final workouts = days.fold<int>(0, (t, d) => t + d.workoutCount);
    return [
      FFSectionTitle(context.tr('activity.last7Days')),
      _TileRow(
        left: FFStatTile(
          icon: Icons.directions_walk,
          value: formatSteps(steps),
          label: context.tr('activity.steps'),
        ),
        right: FFStatTile(
          icon: Icons.timer_outlined,
          value: '$minutes',
          label: context.tr('activity.activeMinutes'),
        ),
      ),
      _TileRow(
        left: FFStatTile(
          icon: Icons.fitness_center,
          value: '$workouts',
          label: context.tr('activity.workoutCount'),
        ),
        right: FFStatTile(
          icon: Icons.local_fire_department,
          value: '${currentStreak(activities, today: today)}',
          label: context.tr('activity.streak'),
          accent: FFTokens.warning500,
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFCard(
        key: const Key('activity-progress-days'),
        child: Column(
          children: [
            for (final d in days)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: FFTokens.spacingXs,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        DateFormat('EEE').format(d.day),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          FFTokens.radiusFull,
                        ),
                        child: LinearProgressIndicator(
                          value: d.goalProgress().clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        formatSteps(d.steps),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(child: right),
          ],
        ),
      ),
    );
  }
}
