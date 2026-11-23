import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/activity/training_plan.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'programme_widgets.dart';
import 'workout_widgets.dart';

// Programmes P1 (M2): the plan page when the plan is a FitFlex programme —
// day by day, gym / home / rest, done by a workout or by a check-in.

/// The day's state for the list: done, today, upcoming, missed or rest.
String programmeDayState(TrainingPlanDay d, DateTime today) {
  if (d.isRest) return 'rest';
  if (d.isDone) return 'done';
  if (d.date == today) return 'today';
  if (d.date.isBefore(today)) return 'missed';
  return 'upcoming';
}

class ProgrammePlanView extends StatelessWidget {
  const ProgrammePlanView({
    super.key,
    required this.plan,
    required this.today,
    required this.back,
    required this.menu,
    required this.onRefresh,
  });

  final TrainingPlan plan;
  final DateTime today;
  final Widget back;
  final Widget menu;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = plan.days.toList()..sort((a, b) => a.date.compareTo(b.date));
    final length = plan.lengthDays ?? days.length;
    final dueSoFar = days
        .where((d) => !d.isRest && !d.date.isAfter(today))
        .length;
    final done = days.where((d) => d.isDone).length;
    final todays = days.where((d) => d.date == today).firstOrNull;
    final dark = theme.brightness == Brightness.dark;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const Key('programme-plan-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          back,
          FFPageHeader(
            title: plan.name,
            description: context
                .tr('programmes.dayOf')
                .replaceAll('{n}', '${plan.currentDay ?? 1}')
                .replaceAll('{N}', '$length'),
            actions: menu,
          ),
          FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                  child: LinearProgressIndicator(
                    value: dueSoFar == 0
                        ? 0
                        : (done / dueSoFar).clamp(0.0, 1.0),
                    minHeight: 8,
                    semanticsLabel: context.tr('programmes.progress'),
                  ),
                ),
                const SizedBox(height: FFTokens.spacingXs),
                Text(
                  context
                      .tr('programmes.doneSoFar')
                      .replaceAll('{n}', '$done')
                      .replaceAll('{total}', '$dueSoFar'),
                  key: const Key('programme-progress'),
                  style: theme.textTheme.bodyMedium,
                ),
                if (plan.streak > 0) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  Row(
                    key: const Key('programme-streak'),
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 20,
                        color: dark ? FFTokens.fuelOnDark : FFTokens.fuel,
                      ),
                      const SizedBox(width: FFTokens.spacingXs),
                      Text(
                        context
                            .tr('programmes.streak')
                            .replaceAll('{n}', '${plan.streak}'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: dark ? FFTokens.fuelOnDark : FFTokens.fuel,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (todays != null) _TodayCard(day: todays),
          for (final d in days) _ProgrammeDayRow(day: d, today: today),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('training.restNote'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _time(BuildContext context, DateTime t) =>
    DateFormat.Hm(Localizations.localeOf(context).languageCode).format(t);

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.day});

  final TrainingPlanDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final List<Widget> body;
    if (day.isRest) {
      body = [
        Text(
          context.tr('programmes.restDay'),
          style: theme.textTheme.titleMedium,
        ),
        Text(context.tr('training.restNote'), style: theme.textTheme.bodySmall),
      ];
    } else if (day.isGym && day.completedBy == 'checkin') {
      body = [
        Row(
          children: [
            Icon(Icons.check_circle, color: scheme.primary),
            const SizedBox(width: FFTokens.spacingXs),
            Expanded(
              child: Text(
                day.completedAt != null
                    ? context
                          .tr('programmes.doneCheckinAt')
                          .replaceAll(
                            '{time}',
                            _time(context, day.completedAt!),
                          )
                    : context.tr('programmes.doneCheckin'),
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ];
    } else if (day.isGym && !day.isDone) {
      body = [
        Text(
          context.tr('programmes.gymToday'),
          style: theme.textTheme.titleSmall,
        ),
        if (day.workoutId != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: const Key('programme-today-suggested'),
            label: context.tr('programmes.seeSuggested'),
            variant: FFButtonVariant.secondary,
            onPressed: () => context.go(workoutRoute(day.workoutId!)),
          ),
        ],
      ];
    } else {
      body = [
        Text(
          day.name ?? context.tr('training.session'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (day.estimatedDuration != null)
          Text(
            context
                .tr('programmes.minutes')
                .replaceAll('{n}', '${day.estimatedDuration}'),
            style: theme.textTheme.bodySmall,
          ),
        if (day.workoutId != null && !day.isDone) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: const Key('programme-today-start'),
            label: context.tr('workout.start'),
            icon: Icons.play_arrow,
            onPressed: () => context.go(workoutRoute(day.workoutId!)),
          ),
        ],
        if (day.isDone)
          Text(
            context.tr('programmes.state.done'),
            style: theme.textTheme.bodyMedium,
          ),
      ];
    }
    return Container(
      key: const Key('programme-today'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('programmes.todayTitle'),
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          ...body,
        ],
      ),
    );
  }
}

class _ProgrammeDayRow extends StatelessWidget {
  const _ProgrammeDayRow({required this.day, required this.today});

  final TrainingPlanDay day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = programmeDayState(day, today);
    final type = day.type ?? 'home';
    final title = day.isRest
        ? context.tr('programmes.type.rest')
        : day.name ??
              (day.isGym
                  ? context.tr('programmes.gymAnyGym')
                  : context.tr('training.session'));
    final meta = [
      context
          .tr('programmes.day')
          .replaceAll('{n}', '${day.programmeDay ?? ''}'),
      context.tr('programmes.type.$type'),
      if (state == 'done' && day.completedBy != null)
        context.tr('programmes.source.${day.completedBy}'),
    ].join(' · ');
    final tappable = day.workoutId != null && !day.isRest;
    return Padding(
      key: Key('programme-plan-day-${day.programmeDay}'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
      child: InkWell(
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        onTap: tappable ? () => context.go(workoutRoute(day.workoutId!)) : null,
        child: FFCard(
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              Icon(
                state == 'done' ? Icons.check_circle : programmeDayIcon(type),
                color: state == 'done' || state == 'today'
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: day.isRest ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    Text(meta, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              FFPill(
                label: context.tr('programmes.state.$state'),
                filled: state == 'today',
              ),
              if (tappable) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
