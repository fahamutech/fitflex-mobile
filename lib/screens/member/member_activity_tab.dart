import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';

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
import 'widgets/run_widgets.dart';
import 'widgets/activity_widgets.dart';
import 'widgets/challenge_widgets.dart';
import 'widgets/goal_widgets.dart';
import 'widgets/gym_visit_tile.dart';
import 'widgets/progress_section.dart';
import 'widgets/training_offer.dart';
import 'widgets/training_widgets.dart';
import 'widgets/workout_widgets.dart';

/// Member Activity tab: Today · Training · Challenges · Progress.
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
          actions:
              data.activityLoaded &&
                  (data.activities.isNotEmpty || _section != 'overview')
              ? FFButton(
                  key: const Key('activity-log-open'),
                  label: context.tr('logActivity.open'),
                  onPressed: () => openLogActivity(context),
                  variant: FFButtonVariant.secondary,
                  size: FFButtonSize.sm,
                  icon: Icons.add,
                )
              : null,
        ),
        if (data.activityIsSample)
          const Padding(
            padding: EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActivitySampleBadge(),
            ),
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
            child: Center(child: FFSpinner(size: 32)),
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
    final data = MemberDataScope.of(context);
    // Gym visits sit in the same list, with what was logged during them.
    final recent = recentTimeline(activities, data.checkins);
    return [
      // Planning lives on the Workouts tab; Overview only surfaces a
      // workout that's actually on for today.
      if (todaysWorkouts(data.workouts, today).isNotEmpty)
        TodayWorkoutCard(data: data, now: today),
      FFSectionTitle(context.tr('activity.today')),
      const PhoneStepsCard(),
      const RecordRunButton(),
      if (activities.isEmpty)
        const ActivityGetStartedCard()
      else ...[
        _TodaySummary(
          steps: s.steps,
          stepGoal: stepGoal,
          cells: [
            (
              Icons.straighten,
              formatKm(s.distanceKm),
              context.tr(
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
            (
              Icons.timer_outlined,
              '${s.activeMinutes}',
              context.tr('activity.activeMinutes'),
            ),
            (
              Icons.local_fire_department_outlined,
              s.calories == null ? '—' : formatSteps(s.calories!),
              context.tr('activity.calories'),
            ),
            (
              Icons.timeline,
              '${s.activityCount}',
              context.tr('activity.activities'),
            ),
            (
              Icons.fitness_center,
              '${s.workoutCount}',
              context.tr('activity.workoutCount'),
            ),
          ],
        ),
      ],
      const SizedBox(height: FFTokens.spacingSm),
      StreakCard(key: const Key('activity-streak'), streak: streak),
      FFSectionTitle(context.tr('activity.currentChallenge')),
      currentChallengeBlock(context, data, today),
      Row(
        children: [
          Expanded(child: FFSectionTitle(context.tr('activity.recent'))),
          FFButton(
            key: const Key('data-origins-info'),
            label: context.tr('origin.link'),
            onPressed: () => showDataOriginsSheet(context),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            icon: Icons.info_outline,
          ),
        ],
      ),
      if (recent.isEmpty)
        FFEmptyState(title: context.tr('activity.noActivity'))
      else ...[
        for (final e in recent) recentEntryTile(e),
        Align(
          alignment: Alignment.centerRight,
          child: FFButton(
            key: const Key('activity-view-more'),
            label: context.tr('activity.viewMore'),
            onPressed: () => context.push(AppRoutes.memberActivityHistory),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            icon: Icons.history,
          ),
        ),
      ],
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
    final noPlanNoWorkout =
        data.trainingLoaded &&
        data.workoutsLoaded &&
        data.trainingPlan == null &&
        todayIds.isEmpty;
    return [
      for (final offer in data.trainingOffers) TrainingOfferCard(offer: offer),
      TrainingPlanCard(data: data, now: now),
      if (noPlanNoWorkout)
        // One invitation, two actions: the plan card above already offers
        // "Create my plan", so the empty workout card becomes a quiet link.
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFButton(
            key: const Key('workout-plan'),
            fullWidth: true,
            variant: FFButtonVariant.secondary,
            label: context.tr('workout.plan'),
            onPressed: () => showPlanWorkoutSheet(context),
          ),
        )
      else
        TodayWorkoutCard(data: data, now: now),
      TrainerPlanBlock(data: data, now: now),
      if (todayIds.isNotEmpty || upcoming.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: FFButton(
            key: const Key('workout-plan-more'),
            label: context.tr('workout.plan'),
            onPressed: () => showPlanWorkoutSheet(context),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            icon: Icons.add,
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
      FFSectionTitle(context.tr('workout.otherActivity')),
      if (other.isEmpty)
        FFEmptyState(title: context.tr('activity.noWorkouts'))
      else
        for (final a in other) ActivityTimelineTile(activity: a),
    ];
  }
}

/// Today's numbers in one card: steps (with the daily goal bar when there
/// is one) on top, the other measures in a compact grid below.
class _TodaySummary extends StatelessWidget {
  const _TodaySummary({
    required this.steps,
    required this.stepGoal,
    required this.cells,
  });

  final int steps;
  final int? stepGoal;
  final List<(IconData, String, String)> cells;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FFCard(
      key: stepGoal != null ? const Key('activity-daily-goal') : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              stepGoal != null ? 'activity.dailyGoal' : 'activity.steps',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.directions_walk,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: FFTokens.spacingXs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: formatSteps(steps),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      if (stepGoal != null)
                        TextSpan(
                          text: ' / ${formatSteps(stepGoal!)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (stepGoal != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            ActivityGoalBar(steps: steps, goal: stepGoal!),
          ],
          const Divider(height: FFTokens.spacingLg * 2),
          Wrap(
            runSpacing: FFTokens.spacingMd,
            children: [
              for (final c in cells)
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Row(
                    children: [
                      Icon(c.$1, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: FFTokens.spacingSm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.$2,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              c.$3,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
