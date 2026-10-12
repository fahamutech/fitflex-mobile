import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/activity_summary.dart';
import '../../shared/activity/training_plan.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/training_widgets.dart';
import 'widgets/workout_widgets.dart';

/// The member's training plan, week by week: every session with its day
/// and state, and a way into each workout.
class MemberTrainingPlanPage extends StatefulWidget {
  const MemberTrainingPlanPage({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<MemberTrainingPlanPage> createState() => _MemberTrainingPlanPageState();
}

class _MemberTrainingPlanPageState extends State<MemberTrainingPlanPage> {
  bool _busy = false;

  Future<void> _stop(TrainingPlan plan) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('training.stopTitle'),
      message: context.tr('training.stopBody'),
      cancelLabel: context.tr('training.keepPlan'),
      confirmLabel: context.tr('training.stop'),
      confirmKey: const Key('training-stop-confirm'),
    );
    if (ok != true || !mounted) return;
    final repo = AppScope.of(context).training;
    final data = MemberDataScope.of(context);
    final shell = context.findAncestorStateOfType<MemberShellState>();
    final messenger = FFSnack.of(context);
    final failed = context.tr('training.failed');
    setState(() => _busy = true);
    try {
      await repo.cancel(plan.id);
      if (shell != null) {
        await shell.refreshTraining();
      } else {
        // Keep the screen right even without a shell (tests, previews).
        data.update((d) => d.trainingPlan = null);
      }
    } catch (_) {
      messenger.error(failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(BuildContext context, TrainingPlanDay d, DateTime today) {
    if (d.isOpen && d.date.isBefore(today)) {
      return context.tr('training.status.missed');
    }
    if (d.isOpen && d.date == today) return context.tr('training.status.today');
    return context.tr('training.status.${d.status}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = MemberDataScope.of(context);
    final today = dayOf(widget.now ?? DateTime.now());
    final plan = data.trainingPlan;
    final back = Align(
      alignment: Alignment.centerLeft,
      child: FFButton(
        key: const Key('training-back'),
        label: context.tr('activity.title'),
        onPressed: () => context.go(AppRoutes.memberActivity),
        variant: FFButtonVariant.ghost,
        size: FFButtonSize.sm,
        icon: Icons.arrow_back,
      ),
    );

    if (!data.trainingLoaded) {
      return const Center(child: FFSpinner(size: 32));
    }
    if (plan == null) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          back,
          FFEmptyState(
            key: const Key('training-plan-empty'),
            title: context.tr('training.noneTitle'),
            body: context.tr('training.noneBody'),
            action: FFButton(
              key: const Key('training-create'),
              label: context.tr('training.create'),
              onPressed: () => context.go(AppRoutes.memberTrainingSetup),
            ),
          ),
        ],
      );
    }

    return ListView(
      key: const Key('training-plan-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        back,
        FFPageHeader(
          title: trainingPlanTitle(context, plan),
          description: [
            if (plan.fromTrainer) plan.name,
            trainingPlanByline(context, plan),
            context
                .tr('training.daysAWeek')
                .replaceAll('{n}', '${plan.daysPerWeek}'),
            context
                .tr('training.minutes')
                .replaceAll('{n}', '${plan.sessionMinutes}'),
          ].join(' · '),
          actions: PopupMenuButton<String>(
            key: const Key('training-plan-menu'),
            enabled: !_busy,
            onSelected: (v) => v == 'change'
                ? context.go(AppRoutes.memberTrainingSetup)
                : _stop(plan),
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const Key('training-change'),
                value: 'change',
                child: Text(context.tr('training.change')),
              ),
              PopupMenuItem(
                key: const Key('training-stop'),
                value: 'stop',
                child: Text(context.tr('training.stop')),
              ),
            ],
          ),
        ),
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                child: LinearProgressIndicator(
                  value: plan.completion.clamp(0.0, 1.0),
                  minHeight: 8,
                  semanticsLabel: context.tr('training.myPlan'),
                ),
              ),
              const SizedBox(height: FFTokens.spacingXs),
              Text(
                trainingProgressLine(context, plan),
                key: const Key('training-progress'),
                style: theme.textTheme.bodyMedium,
              ),
              if (plan.targetAreas.isNotEmpty) ...[
                const SizedBox(height: FFTokens.spacingXs),
                Text(
                  context
                      .tr('training.focusOn')
                      .replaceAll(
                        '{areas}',
                        plan.targetAreas
                            .map((a) => trainingAreaLabel(context, a))
                            .join(', '),
                      ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        for (final week in plan.weeks) ...[
          FFSectionTitle(
            week.week == plan.currentWeek
                ? context
                      .tr('training.weekCurrent')
                      .replaceAll('{n}', '${week.week}')
                : context.tr('training.week').replaceAll('{n}', '${week.week}'),
          ),
          for (final d in week.days)
            _DayTile(
              key: Key(
                'training-day-${d.date.toIso8601String().substring(0, 10)}',
              ),
              day: d,
              status: _statusLabel(context, d, today),
              highlight: d.isOpen && d.date == today,
              onTap: d.workoutId != null
                  ? () => context.go(workoutRoute(d.workoutId!))
                  : null,
            ),
        ],
        const SizedBox(height: FFTokens.spacingSm),
        Text(context.tr('training.restNote'), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    super.key,
    required this.day,
    required this.status,
    required this.highlight,
    required this.onTap,
  });

  final TrainingPlanDay day;
  final String status;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      trainingDate(context, day.date),
      if (day.exerciseCount > 0)
        context
            .tr('training.exercises')
            .replaceAll('{n}', '${day.exerciseCount}'),
      if (day.estimatedDuration != null)
        context
            .tr('training.minutes')
            .replaceAll('{n}', '${day.estimatedDuration}'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        child: FFCard(
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              Icon(
                day.isDone
                    ? Icons.check_circle
                    : day.status == 'skipped' || day.status == 'removed'
                    ? Icons.remove_circle_outline
                    : Icons.fitness_center,
                color: day.isDone || highlight
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trainingDayName(context, day),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(meta, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              FFPill(label: status, filled: highlight),
              if (onTap != null) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
