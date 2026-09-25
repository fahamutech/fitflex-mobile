import 'package:flutter/material.dart';

import '../../shared/activity/activity.dart';
import '../../shared/activity/activity_summary.dart';
import '../../shared/activity/goal.dart';
import '../../shared/activity/progress_engine.dart';
import '../../shared/activity/streaks.dart';
import '../../shared/activity/workout.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/phone_steps_card.dart';
import 'widgets/activity_widgets.dart';
import 'widgets/challenge_widgets.dart';
import 'widgets/goal_widgets.dart';
import 'widgets/progress_section.dart';
import 'widgets/workout_widgets.dart';

/// Member Activity tab: Overview · Workouts · Challenges · Progress.
class MemberActivityTab extends StatefulWidget {
  const MemberActivityTab({
    super.key,
    this.now,
    this.initialSection = 'overview',
  });

  /// Injectable clock for tests.
  final DateTime? now;

  /// `overview`, `workouts`, `challenges` or `progress`.
  final String initialSection;

  @override
  State<MemberActivityTab> createState() => _MemberActivityTabState();
}

class _MemberActivityTabState extends State<MemberActivityTab> {
  late String _section = widget.initialSection;

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
            'workouts' => _workouts(context, data, today),
            'challenges' => buildChallengesSection(context, data, today),
            'progress' => buildProgressSection(context, data, today),
            _ => _overview(context, data.activities, data.goals, today),
          },
      ],
    );
  }

  List<Widget> _overview(
    BuildContext context,
    List<Activity> activities,
    List<Goal> goals,
    DateTime today,
  ) {
    final s = summarizeDay(activities, today);
    final stepGoal = dailyStepGoal(goals)?.target.round();
    final streak = computeStreak(
      StreakKind.activity,
      today: today,
      activities: activities,
    )!;
    final recent = activities.take(8).toList();
    final data = MemberDataScope.of(context);
    return [
      // Planning lives on the Workouts tab; Overview only surfaces a
      // workout that's actually on for today.
      if (todaysWorkouts(data.workouts, today).isNotEmpty)
        TodayWorkoutCard(data: data, now: today),
      Row(
        children: [
          Expanded(child: FFSectionTitle(context.tr('activity.today'))),
          if (activities.isNotEmpty)
            TextButton.icon(
              key: const Key('activity-log-open'),
              onPressed: () => openLogActivity(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr('logActivity.open')),
            ),
        ],
      ),
      const PhoneStepsCard(),
      if (activities.isEmpty)
        const ActivityGetStartedCard()
      else ...[
        _TileRow(
          left: FFStatTile(
            icon: Icons.directions_walk,
            value: formatSteps(s.steps),
            label: context.tr('activity.steps'),
          ),
          right: FFStatTile(
            icon: Icons.straighten,
            value: formatKm(s.distanceKm),
            // The phone counts steps only; its distance is estimated.
            label: context.tr(
              activities.any(
                    (a) =>
                        a.devicePlatform == DevicePlatform.phoneSensor &&
                        (a.distanceKm ?? 0) > 0 &&
                        dayOf(a.startedAt) == dayOf(today),
                  )
                  ? 'activity.distanceEstimated'
                  : 'activity.distance',
            ),
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
      ],
      const SizedBox(height: FFTokens.spacingSm),
      if (stepGoal != null)
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
                '${formatSteps(s.steps)} / ${formatSteps(stepGoal)}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              ActivityGoalBar(steps: s.steps, goal: stepGoal),
            ],
          ),
        ),
      StreakCard(key: const Key('activity-streak'), streak: streak),
      FFSectionTitle(context.tr('activity.currentChallenge')),
      currentChallengeBlock(context, data, today),
      Row(
        children: [
          Expanded(child: FFSectionTitle(context.tr('activity.recent'))),
          TextButton.icon(
            key: const Key('data-origins-info'),
            onPressed: () => showDataOriginsSheet(context),
            icon: const Icon(Icons.info_outline, size: 18),
            label: Text(context.tr('origin.link')),
          ),
        ],
      ),
      if (recent.isEmpty)
        FFEmptyState(title: context.tr('activity.noActivity'))
      else
        ...recent.map((a) => ActivityTimelineTile(activity: a)),
    ];
  }

  List<Widget> _workouts(BuildContext context, MemberData data, DateTime now) {
    final todayIds = todaysWorkouts(
      data.workouts,
      now,
    ).map((w) => w.id).toSet();
    final upcoming =
        data.workouts
            .where((w) => w.status.isOpen && !todayIds.contains(w.id))
            .where((w) => !w.scheduledDate.isBefore(dayOf(now)))
            .toList()
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final done = data.workouts
        .where((w) => w.status == WorkoutStatus.completed)
        .toList();
    // Workouts recorded some other way (a run, a class) — completed
    // structured workouts are already listed above.
    final other = data.activities
        .where((a) => a.isWorkout && a.workoutId == null)
        .toList();
    return [
      TodayWorkoutCard(data: data, now: now),
      TrainerPlanBlock(data: data, now: now),
      if (todayIds.isNotEmpty || upcoming.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('workout-plan-more'),
            onPressed: () => showPlanWorkoutSheet(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('workout.plan')),
          ),
        ),
      if (upcoming.isNotEmpty) ...[
        FFSectionTitle(context.tr('workout.upcoming')),
        for (final w in upcoming) WorkoutTile(workout: w),
      ],
      if (done.isNotEmpty) ...[
        FFSectionTitle(context.tr('workout.completedList')),
        for (final w in done) WorkoutTile(workout: w),
      ],
      Row(
        children: [
          Expanded(child: FFSectionTitle(context.tr('workout.otherActivity'))),
          TextButton.icon(
            key: const Key('workouts-log-open'),
            onPressed: () => openLogActivity(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('logActivity.open')),
          ),
        ],
      ),
      if (other.isEmpty)
        FFEmptyState(title: context.tr('activity.noWorkouts'))
      else
        for (final a in other) ActivityTimelineTile(activity: a),
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
