import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../shared/activity/goal.dart';
import '../../shared/activity/trainer_connection.dart';
import '../../shared/activity/workout.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../member/widgets/activity_bar_chart.dart';
import '../member/widgets/activity_widgets.dart' show formatSteps, formatKm;
import '../member/widgets/goal_widgets.dart' show goalTitle;
import '../member/widgets/trainer_sharing.dart' show permissionLabel;
import '../member/widgets/workout_widgets.dart' show exerciseTarget;
import 'trainer_plan_editor_page.dart';
import 'widgets/client_summary_card.dart';

/// A trainer's view of one client: only what the client shares, the
/// workouts this trainer assigned, and assigning more.
class TrainerClientPage extends StatefulWidget {
  const TrainerClientPage({
    super.key,
    required this.connection,
    required this.plans,
    this.now,
  });

  final TrainerConnection connection;
  final List<TrainerPlan> plans;

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<TrainerClientPage> createState() => _TrainerClientPageState();
}

class _TrainerClientPageState extends State<TrainerClientPage> {
  ClientOverview? _o;
  bool _failed = false;
  late List<TrainerPlan> _plans = widget.plans;

  String get _name =>
      widget.connection.member?.displayName ?? context.tr('clients.client');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_o == null && !_failed) _load();
  }

  Future<void> _load() async {
    try {
      final res = await AppScope.of(
        context,
      ).api.trainerClientOverview(widget.connection.id);
      if (mounted) setState(() => _o = ClientOverview.fromJson(res));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _reloadPlans() async {
    final rows = await AppScope.of(context).api.trainerPlans();
    if (!mounted) return;
    setState(() {
      _plans = [
        for (final r in rows.whereType<Map>())
          TrainerPlan.fromJson(Map<String, dynamic>.from(r)),
      ];
    });
  }

  Future<void> _assign() async {
    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AssignWorkoutSheet(
        clientName: _name,
        plans: _plans,
        now: widget.now ?? DateTime.now(),
        onNewPlan: () async {
          final saved = await openTrainerPlanEditor(context);
          if (saved == true) await _reloadPlans();
          return _plans;
        },
        onAssign: (planId, dates) => AppScope.of(context).api
            .trainerAssignWorkout(widget.connection.id, {
              'planId': planId,
              'dates': [for (final d in dates) formatWorkoutDate(d)],
            }),
      ),
    );
    if (assigned == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('assign.done').replaceAll('{name}', _name)),
        ),
      );
      await _load();
    }
  }

  Future<void> _cancel(ClientWorkout w) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('owner.errorGeneric');
    try {
      await AppScope.of(context).api.trainerCancelWorkout(w.id);
      await _load();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _end() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('clients.endTitle')),
        content: Text(ctx.tr('clients.endBody').replaceAll('{name}', _name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('workout.keepGoing')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('connect.end')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    try {
      await AppScope.of(context).api.trainerEndClient(widget.connection.id);
      navigator.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('owner.errorGeneric'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          PopupMenuButton<String>(
            key: const Key('client-menu'),
            onSelected: (_) => _end(),
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'end', child: Text(ctx.tr('connect.end'))),
            ],
          ),
        ],
      ),
      floatingActionButton: _o == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('client-assign'),
              onPressed: _assign,
              icon: const Icon(Icons.add),
              label: Text(context.tr('assign.action')),
            ),
      body: _failed
          ? Center(child: FFEmptyState(title: context.tr('owner.errorGeneric')))
          : _o == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(context, _o!)),
    );
  }

  Widget _body(BuildContext context, ClientOverview o) {
    final theme = Theme.of(context);
    final perms = o.client.permissions;
    final notShared = [
      for (final p in TrainerPermission.values)
        if (!perms.has(p)) permissionLabel(context, p),
    ];
    final today = DateTime.now();
    final upcoming =
        o.workouts
            .where(
              (w) => w.assignedByYou && (w.status == null || w.status!.isOpen),
            )
            .where(
              (w) => !w.scheduledDate.isBefore(
                DateTime(today.year, today.month, today.day),
              ),
            )
            .toList()
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final history = o.workouts.where((w) => !upcoming.contains(w)).toList();

    return ListView(
      key: const Key('client-overview'),
      padding: const EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        96,
      ),
      children: [
        if (o.summary != null)
          ClientSummaryCard(
            key: const Key('client-summary'),
            name: _name,
            photoUrl: o.client.member?.photoUrl,
            summary: o.summary!,
          ),
        if (notShared.isNotEmpty)
          FFCard(
            key: const Key('client-not-shared'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, size: 18),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: Text(
                    '${context.tr('clients.notShared').replaceAll('{name}', _name)} ${notShared.join(', ')}.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (o.activity != null) _ActivityCard(days: o.activity!, perms: perms),
        if (o.goals != null) ...[
          FFSectionTitle(context.tr('progress.currentGoals')),
          if (o.goals!.isEmpty)
            FFEmptyState(title: context.tr('progress.noGoals'))
          else
            for (final g in o.goals!)
              FFCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goalTitle(
                        context,
                        Goal(
                          id: '',
                          userId: '',
                          type: g.type,
                          target: g.target,
                          period: g.period,
                          startDate: DateTime.now(),
                        ),
                      ),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                      child: LinearProgressIndicator(
                        value: g.target <= 0
                            ? 0
                            : (g.current / g.target).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    Text(
                      '${context.tr('goal.progressOf').replaceAll('{current}', _fmtAmount(g.current)).replaceAll('{target}', _fmtAmount(g.target))}'
                      ' · ${g.target <= 0 ? 0 : (g.current / g.target * 100).round()}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
        ],
        if (o.streaks != null) ...[
          FFSectionTitle(context.tr('progress.streaks')),
          for (final e in o.streaks!.entries)
            if (e.value case final s?)
              FFCard(
                child: Row(
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      color: s.current > 0
                          ? FFTokens.warning500
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: FFTokens.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context
                                .tr('streak.${e.key}.current')
                                .replaceAll('{n}', '${s.current}'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            context
                                .tr('streak.best')
                                .replaceAll('{n}', '${s.best}'),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
        FFSectionTitle(context.tr('assign.upcoming')),
        if (upcoming.isEmpty)
          FFEmptyState(
            title: context.tr('assign.noneUpcoming'),
            body: context.tr('assign.noneUpcomingBody'),
          )
        else
          for (final w in upcoming)
            FFActionTile(
              key: Key('client-workout-${w.id}'),
              icon: Icons.event_outlined,
              title: w.name,
              subtitle: DateFormat('EEE d MMM').format(w.scheduledDate),
              trailing: w.status == null || w.status == WorkoutStatus.planned
                  ? IconButton(
                      key: Key('client-workout-cancel-${w.id}'),
                      tooltip: context.tr('assign.cancel'),
                      onPressed: () => _cancel(w),
                      icon: const Icon(Icons.close),
                    )
                  : null,
              onTap: () {},
            ),
        FFSectionTitle(context.tr('assign.history')),
        if (!perms.has(TrainerPermission.workoutHistory))
          FFEmptyState(
            title: context
                .tr('assign.historyHidden')
                .replaceAll('{name}', _name),
          )
        else if (history.isEmpty)
          FFEmptyState(title: context.tr('assign.noHistory'))
        else
          for (final w in history)
            FFActionTile(
              key: Key('client-history-${w.id}'),
              icon: w.status == WorkoutStatus.completed
                  ? Icons.check_circle_outline
                  : Icons.radio_button_unchecked,
              title: w.name,
              subtitle: [
                DateFormat('EEE d MMM').format(w.scheduledDate),
                if (w.status != null)
                  context.tr('workout.status.${w.status!.wire}'),
                if (w.setsTotal != null)
                  '${w.setsCompleted}/${w.setsTotal} ${context.tr('workout.sets')}',
                if (w.durationMinutes != null)
                  '${w.durationMinutes} ${context.tr('activity.min')}',
                if (w.assignedByYou) context.tr('assign.byYou'),
              ].join(' · '),
              onTap: w.exercises == null ? () {} : () => _showDetails(w),
            ),
      ],
    );
  }

  void _showDetails(ClientWorkout w) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          Text(w.name, style: Theme.of(ctx).textTheme.titleLarge),
          if ((w.notes ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(w.notes!, style: Theme.of(ctx).textTheme.bodySmall),
            ),
          for (final e in w.exercises!) ...[
            FFSectionTitle('${e.exerciseName} · ${exerciseTarget(ctx, e)}'),
            for (final s in e.workoutSets)
              Text(
                '${ctx.tr('workout.set')} ${s.setNumber}: '
                '${s.completed ? '✓' : '—'} '
                '${e.isTimed ? '${s.duration ?? '-'} ${ctx.tr('workout.secondsShort')}' : '${s.reps ?? '-'} ${ctx.tr('workout.reps')}'}'
                '${s.weight != null ? ' · ${s.weight} kg' : ''}',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            if ((e.notes ?? '').isNotEmpty)
              Text(e.notes!, style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ],
      ),
    ),
  );
}

String _fmtAmount(num v) =>
    v == v.roundToDouble() ? formatSteps(v.round()) : v.toStringAsFixed(1);

/// Last 14 days of whichever activity metrics the client shares.
class _ActivityCard extends StatefulWidget {
  const _ActivityCard({required this.days, required this.perms});

  final List<ClientDay> days;
  final TrainerPermissions perms;

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  late String _metric = [
    if (widget.perms.has(TrainerPermission.steps)) 'steps',
    if (widget.perms.has(TrainerPermission.activeMinutes)) 'minutes',
    if (widget.perms.has(TrainerPermission.distance)) 'distance',
  ].first;

  @override
  Widget build(BuildContext context) {
    final options = [
      if (widget.perms.has(TrainerPermission.steps))
        ('steps', context.tr('activity.steps')),
      if (widget.perms.has(TrainerPermission.activeMinutes))
        ('minutes', context.tr('activity.activeMinutes')),
      if (widget.perms.has(TrainerPermission.distance))
        ('distance', context.tr('activity.distance')),
    ];
    final fmt = DateFormat('EEE d MMM');
    final bars = [
      for (final d in widget.days)
        switch (_metric) {
          'minutes' => BarDatum(
            DateFormat('E').format(d.date).substring(0, 1),
            d.activeMinutes ?? 0,
            '${fmt.format(d.date)}: ${d.activeMinutes ?? 0} ${context.tr('activity.activeMinutes').toLowerCase()}',
          ),
          'distance' => BarDatum(
            DateFormat('E').format(d.date).substring(0, 1),
            d.distanceKm ?? 0,
            '${fmt.format(d.date)}: ${formatKm(d.distanceKm ?? 0)}',
          ),
          _ => BarDatum(
            DateFormat('E').format(d.date).substring(0, 1),
            d.steps ?? 0,
            '${fmt.format(d.date)}: ${formatSteps(d.steps ?? 0)} ${context.tr('activity.steps').toLowerCase()}',
          ),
        },
    ];
    return FFCard(
      key: const Key('client-activity'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('clients.last14'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (options.length > 1) ...[
            SizedBox(
              width: double.infinity,
              child: FFSegmented(
                value: _metric,
                options: options,
                onChanged: (v) => setState(() => _metric = v),
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          ActivityBarChart(data: bars, height: 110),
        ],
      ),
    );
  }
}

/// Pick a plan and one or more of the next 14 days.
class AssignWorkoutSheet extends StatefulWidget {
  const AssignWorkoutSheet({
    super.key,
    required this.clientName,
    required this.plans,
    required this.now,
    required this.onNewPlan,
    required this.onAssign,
  });

  final String clientName;
  final List<TrainerPlan> plans;
  final DateTime now;
  final Future<List<TrainerPlan>> Function() onNewPlan;
  final Future<Object?> Function(String planId, List<DateTime> dates) onAssign;

  @override
  State<AssignWorkoutSheet> createState() => _AssignWorkoutSheetState();
}

class _AssignWorkoutSheetState extends State<AssignWorkoutSheet> {
  late List<TrainerPlan> _plans = widget.plans;
  String? _planId;
  final Set<DateTime> _dates = {};
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    final failed = context.tr('assign.failed');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAssign(_planId!, (_dates.toList()..sort()));
      navigator.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final days = [
      for (var i = 0; i < 14; i++)
        DateTime(today.year, today.month, today.day + i),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context
                  .tr('assign.title')
                  .replaceAll('{name}', widget.clientName),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context.tr('assign.pickPlan'),
              style: theme.textTheme.labelLarge,
            ),
            if (_plans.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: FFTokens.spacingSm,
                ),
                child: Text(
                  context.tr('plans.noneBody'),
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              Flexible(
                child: RadioGroup<String>(
                  groupValue: _planId,
                  onChanged: (v) => setState(() => _planId = v),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in _plans)
                        RadioListTile<String>(
                          key: Key('assign-plan-${p.id}'),
                          value: p.id!,
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.name),
                          subtitle: Text(
                            context
                                .tr('workout.exerciseCount')
                                .replaceAll('{n}', '${p.exercises.length}'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            TextButton.icon(
              key: const Key('assign-new-plan'),
              onPressed: () async {
                final plans = await widget.onNewPlan();
                if (mounted) setState(() => _plans = plans);
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr('plans.new')),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context.tr('assign.pickDays'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(
              spacing: FFTokens.spacingXs,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final d in days)
                  FilterChip(
                    key: Key('assign-day-${formatWorkoutDate(d)}'),
                    label: Text(
                      d == today
                          ? context.tr('workout.dayToday')
                          : DateFormat('EEE d').format(d),
                    ),
                    selected: _dates.contains(d),
                    onSelected: (on) =>
                        setState(() => on ? _dates.add(d) : _dates.remove(d)),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: FFTokens.spacingMd),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('assign-save'),
                onPressed: _planId == null || _dates.isEmpty || _busy
                    ? null
                    : _submit,
                child: Text(
                  context
                      .tr(_dates.length > 1 ? 'assign.saveMany' : 'assign.save')
                      .replaceAll('{n}', '${_dates.length}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
