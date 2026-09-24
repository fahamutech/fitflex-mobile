import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/activity/activity.dart';
import '../../../shared/activity/activity_summary.dart';
import '../../../shared/activity/progress_engine.dart';
import '../../../shared/activity/streaks.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'activity_bar_chart.dart';
import 'activity_widgets.dart';
import 'goal_widgets.dart';

/// The Progress section of the Activity tab: goals, weekly and monthly
/// progress, trends, consistency, streaks, milestones and records.
List<Widget> buildProgressSection(
  BuildContext context,
  MemberData data,
  DateTime now,
) {
  final acts = data.activities;
  // Nothing recorded yet: goals, then one way in, not eight blocks of zeros.
  if (acts.isEmpty && !data.activityIsSample) {
    return [
      GoalsBlock(data: data, now: now),
      const SizedBox(height: FFTokens.spacingMd),
      const ActivityGetStartedCard(),
    ];
  }
  return [
    GoalsBlock(data: data, now: now),
    _WeeklyBlock(activities: acts, now: now),
    _MonthlyBlock(activities: acts, now: now),
    _TrendsBlock(activities: acts, now: now),
    _ConsistencyBlock(activities: acts, now: now),
    _StreaksBlock(data: data, now: now),
    _MilestonesBlock(activities: acts),
    _RecordsBlock(activities: acts, now: now),
  ];
}

// ── Weekly / monthly ────────────────────────────────────────────────────────

/// Compares the period so far with the same stretch of the previous period,
/// so a Tuesday isn't measured against a whole previous week.
class _Comparison {
  final PeriodTotals current;
  final PeriodTotals previous;

  const _Comparison(this.current, this.previous);
}

_Comparison _compare(
  List<Activity> acts,
  DateTime periodStart,
  DateTime previousStart,
  DateTime now,
) {
  final elapsed = dayOf(now).difference(periodStart).inDays + 1;
  DateTime plus(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  // A short previous month (e.g. February) never spills into this one.
  var previousEnd = plus(previousStart, elapsed);
  if (previousEnd.isAfter(periodStart)) previousEnd = periodStart;
  return _Comparison(
    totalsFor(acts, PeriodWindow(periodStart, plus(periodStart, elapsed))),
    totalsFor(acts, PeriodWindow(previousStart, previousEnd)),
  );
}

class _WeeklyBlock extends StatelessWidget {
  const _WeeklyBlock({required this.activities, required this.now});

  final List<Activity> activities;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final start = weekStart(now);
    final c = _compare(
      activities,
      start,
      DateTime(start.year, start.month, start.day - 7),
      now,
    );
    return _ComparisonBlock(
      title: context.tr('progress.weekly'),
      caption: context.tr('progress.vsLastWeek'),
      comparison: c,
      blockKey: const Key('progress-weekly'),
    );
  }
}

class _MonthlyBlock extends StatelessWidget {
  const _MonthlyBlock({required this.activities, required this.now});

  final List<Activity> activities;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final start = monthStart(now);
    final c = _compare(
      activities,
      start,
      DateTime(start.year, start.month - 1),
      now,
    );
    return _ComparisonBlock(
      title: context.tr('progress.monthly'),
      caption: context.tr('progress.vsLastMonth'),
      comparison: c,
      showActiveDays: true,
      blockKey: const Key('progress-monthly'),
    );
  }
}

class _ComparisonBlock extends StatelessWidget {
  const _ComparisonBlock({
    required this.title,
    required this.caption,
    required this.comparison,
    required this.blockKey,
    this.showActiveDays = false,
  });

  final String title;
  final String caption;
  final _Comparison comparison;
  final Key blockKey;
  final bool showActiveDays;

  @override
  Widget build(BuildContext context) {
    final cur = comparison.current;
    final prev = comparison.previous;
    Widget tile(String label, num value, num before, String shown) =>
        FFMetricCard(
          label: label,
          value: shown,
          trendDirection: _trend(value, before),
          trendLabel: _trendLabel(context, value, before),
        );
    return Column(
      key: blockKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(title),
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ),
        _Pair(
          tile(
            context.tr('activity.activeMinutes'),
            cur.activeMinutes,
            prev.activeMinutes,
            formatSteps(cur.activeMinutes),
          ),
          tile(
            context.tr('activity.workoutCount'),
            cur.workouts,
            prev.workouts,
            '${cur.workouts}',
          ),
        ),
        _Pair(
          showActiveDays
              ? tile(
                  context.tr('progress.activeDays'),
                  cur.activeDays,
                  prev.activeDays,
                  '${cur.activeDays}',
                )
              : tile(
                  context.tr('activity.steps'),
                  cur.steps,
                  prev.steps,
                  formatSteps(cur.steps),
                ),
          tile(
            context.tr('activity.distance'),
            cur.distanceKm,
            prev.distanceKm,
            formatKm(cur.distanceKm),
          ),
        ),
      ],
    );
  }
}

FFTrendDirection? _trend(num now, num before) {
  if (now == 0 && before == 0) return null;
  if (before == 0) return FFTrendDirection.up;
  final change = (now - before) / before;
  if (change.abs() < 0.05) return FFTrendDirection.neutral;
  return change > 0 ? FFTrendDirection.up : FFTrendDirection.down;
}

String? _trendLabel(BuildContext context, num now, num before) {
  if (now == 0 && before == 0) return null;
  if (before == 0) return context.tr('progress.new');
  final pct = ((now - before) / before * 100).round();
  return '${pct > 0 ? '+' : ''}$pct%';
}

// ── Trends ──────────────────────────────────────────────────────────────────

class _TrendsBlock extends StatefulWidget {
  const _TrendsBlock({required this.activities, required this.now});

  final List<Activity> activities;
  final DateTime now;

  @override
  State<_TrendsBlock> createState() => _TrendsBlockState();
}

class _TrendsBlockState extends State<_TrendsBlock> {
  String _metric = 'minutes';

  @override
  Widget build(BuildContext context) {
    final weeks = weeklyTotals(widget.activities, today: widget.now);
    final fmt = DateFormat('d MMM');
    final labelFmt = DateFormat('d/M');
    final bars = [
      for (var i = 0; i < weeks.length; i++)
        () {
          final w = weeks[i];
          final (num value, String shown, String unit) = switch (_metric) {
            'steps' => (
              w.steps,
              formatSteps(w.steps),
              context.tr('activity.steps').toLowerCase(),
            ),
            'workouts' => (
              w.workouts,
              '${w.workouts}',
              context.tr('activity.workoutCount').toLowerCase(),
            ),
            _ => (
              w.activeMinutes,
              formatSteps(w.activeMinutes),
              context.tr('activity.activeMinutes').toLowerCase(),
            ),
          };
          final isCurrent = i == weeks.length - 1;
          final week = context
              .tr('progress.weekOf')
              .replaceAll('{date}', fmt.format(w.window.start));
          final soFar = isCurrent ? ' (${context.tr('progress.soFar')})' : '';
          return BarDatum(
            labelFmt.format(w.window.start),
            value,
            '$week: $shown $unit$soFar',
          );
        }(),
    ];
    return FFCard(
      key: const Key('progress-trends'),
      margin: const EdgeInsets.only(top: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('progress.trends'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            context.tr('progress.trendsCaption'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          SizedBox(
            width: double.infinity,
            child: FFSegmented(
              key: const Key('progress-trend-metric'),
              value: _metric,
              options: [
                ('minutes', context.tr('activity.activeMinutes')),
                ('steps', context.tr('activity.steps')),
                ('workouts', context.tr('activity.workoutCount')),
              ],
              onChanged: (v) => setState(() => _metric = v),
            ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          ActivityBarChart(data: bars),
        ],
      ),
    );
  }
}

// ── Consistency ─────────────────────────────────────────────────────────────

class _ConsistencyBlock extends StatelessWidget {
  const _ConsistencyBlock({required this.activities, required this.now});

  final List<Activity> activities;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDay = groupByDay(activities);
    // Four full Monday–Sunday rows ending with the current week.
    final firstMonday = DateTime(
      weekStart(now).year,
      weekStart(now).month,
      weekStart(now).day - 21,
    );
    final today = dayOf(now);
    final days = [
      for (var i = 0; i < 28; i++)
        DateTime(firstMonday.year, firstMonday.month, firstMonday.day + i),
    ];
    final last28 = [
      for (var i = 27; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i),
    ];
    final activeCount = last28
        .where((d) => byDay[d]?.countsForStreak ?? false)
        .length;
    final weekdayFmt = DateFormat('E');

    return FFCard(
      key: const Key('progress-consistency'),
      margin: const EdgeInsets.only(top: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('progress.consistency'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            context
                .tr('progress.activeDaysOf')
                .replaceAll('{n}', '$activeCount'),
            key: const Key('progress-active-days'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          ExcludeSemantics(
            child: Column(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Text(
                          weekdayFmt.format(days[i]).substring(0, 1),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: FFTokens.spacingXs),
                for (var row = 0; row < 4; row++)
                  Row(
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: _DayCell(
                            summary: byDay[days[row * 7 + col]],
                            future: days[row * 7 + col].isAfter(today),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('progress.consistencyLegend'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.summary, required this.future});

  final DaySummary? summary;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qualifies = summary?.countsForStreak ?? false;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: future
                ? Colors.transparent
                : qualifies
                ? cs.primary
                : cs.surfaceContainerHighest,
            // Days still to come are faint, so the grid reads "up to today".
            border: Border.all(
              color: qualifies
                  ? cs.primary
                  : future
                  ? cs.outlineVariant.withValues(alpha: 0.35)
                  : cs.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(FFTokens.radiusSm),
          ),
        ),
      ),
    );
  }
}

// ── Streaks ─────────────────────────────────────────────────────────────────

class _StreaksBlock extends StatelessWidget {
  const _StreaksBlock({required this.data, required this.now});

  final MemberData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final checkIns = [
      for (final c in data.checkins) ?DateTime.tryParse(c.timestamp),
    ];
    final streaks = [
      for (final kind in StreakKind.values)
        ?computeStreak(
          kind,
          today: now,
          activities: data.activities,
          checkIns: checkIns,
          goals: data.goals,
        ),
    ];
    return Column(
      key: const Key('progress-streaks'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(context.tr('progress.streaks')),
        for (final s in streaks) StreakCard(streak: s),
      ],
    );
  }
}

// ── Milestones ──────────────────────────────────────────────────────────────

class _MilestonesBlock extends StatelessWidget {
  const _MilestonesBlock({required this.activities});

  final List<Activity> activities;

  @override
  Widget build(BuildContext context) {
    final reached = topMilestones(activities);
    return Column(
      key: const Key('progress-milestones'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(context.tr('progress.milestones')),
        if (reached.isEmpty)
          FFEmptyState(title: context.tr('progress.noMilestones'))
        else
          Wrap(
            spacing: FFTokens.spacingSm,
            runSpacing: FFTokens.spacingSm,
            children: [
              for (final m in reached)
                Chip(
                  avatar: const Icon(Icons.emoji_events_outlined, size: 18),
                  label: Text(milestoneLabel(context, m)),
                ),
            ],
          ),
      ],
    );
  }
}

String milestoneLabel(BuildContext context, Milestone m) {
  if (m.id == 'workouts_1') return context.tr('milestone.firstWorkout');
  final n = switch (m.metric) {
    MilestoneMetric.steps => formatSteps(m.threshold.toInt()),
    _ => '${m.threshold}',
  };
  final key = switch (m.metric) {
    MilestoneMetric.workouts => 'milestone.workouts',
    MilestoneMetric.steps => 'milestone.steps',
    MilestoneMetric.distanceKm => 'milestone.distance',
  };
  return context.tr(key).replaceAll('{n}', n);
}

// ── Personal records ────────────────────────────────────────────────────────

class _RecordsBlock extends StatelessWidget {
  const _RecordsBlock({required this.activities, required this.now});

  final List<Activity> activities;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final r = personalRecords(activities, today: now);
    final fmt = DateFormat('d MMM');
    final tiles = <Widget>[
      if (r.longestRun != null)
        FFMetricCard(
          label: context.tr('record.longestRun'),
          value: formatKm(r.longestRun!.distanceKm!),
          sub: fmt.format(r.longestRun!.startedAt.toLocal()),
        ),
      if (r.mostStepsDay != null)
        FFMetricCard(
          label: context.tr('record.mostSteps'),
          value: formatSteps(r.mostStepsDay!.steps),
          sub: fmt.format(r.mostStepsDay!.day),
        ),
      if (r.longestWorkout != null)
        FFMetricCard(
          label: context.tr('record.longestWorkout'),
          value:
              '${r.longestWorkout!.durationMinutes} ${context.tr('activity.min')}',
          sub:
              '${activityTypeLabel(context, r.longestWorkout!.type)} · '
              '${fmt.format(r.longestWorkout!.startedAt.toLocal())}',
        ),
      if (r.bestWeek != null)
        FFMetricCard(
          label: context.tr('record.bestWeek'),
          value:
              '${formatSteps(r.bestWeek!.activeMinutes)} ${context.tr('activity.min')}',
          sub: context
              .tr('progress.weekOf')
              .replaceAll('{date}', fmt.format(r.bestWeek!.window.start)),
        ),
    ];
    return Column(
      key: const Key('progress-records'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(context.tr('progress.records')),
        if (tiles.isEmpty)
          FFEmptyState(title: context.tr('progress.noRecords'))
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Text(
              context.tr('progress.recordsCaption'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (var i = 0; i < tiles.length; i += 2)
            _Pair(tiles[i], i + 1 < tiles.length ? tiles[i + 1] : null),
        ],
      ],
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair(this.left, this.right);

  final Widget left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(child: right ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}
