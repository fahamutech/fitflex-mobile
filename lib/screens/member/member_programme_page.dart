import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/activity_summary.dart';
import '../../shared/activity/programme.dart';
import '../../shared/activity/training_plan.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/programme_widgets.dart';
import 'widgets/training_widgets.dart';

/// Programmes P1 (M1): one programme, day by day, and starting it.
class MemberProgrammePage extends StatefulWidget {
  const MemberProgrammePage({super.key, required this.programmeId, this.now});

  final String programmeId;

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<MemberProgrammePage> createState() => _MemberProgrammePageState();
}

class _MemberProgrammePageState extends State<MemberProgrammePage> {
  Programme? _programme;
  bool _failed = false;
  bool _gone = false;

  /// What to do once the start sheet has closed: where to go, and the snack.
  ({String route, String? snack, bool error})? _after;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_programme == null && !_failed && !_gone) _load();
  }

  // The same page can be shown for another programme (a link, or the
  // browser's back/forward): start over for the new id.
  @override
  void didUpdateWidget(covariant MemberProgrammePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.programmeId == widget.programmeId) return;
    _programme = null;
    _failed = false;
    _gone = false;
    _after = null;
    _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).programmes;
    final lang = Localizations.localeOf(context).languageCode;
    final id = widget.programmeId;
    setState(() => _failed = false);
    // A reply for an id the page no longer shows is dropped.
    bool current() => mounted && widget.programmeId == id;
    try {
      final p = await repo.programme(id, lang: lang);
      if (current()) setState(() => _programme = p);
    } on ProgrammesDisabled {
      if (current()) setState(() => _gone = true);
    } on ProgrammeUnavailable {
      if (current()) setState(() => _gone = true);
    } catch (_) {
      if (current()) setState(() => _failed = true);
    }
  }

  /// Name of the member's current plan, as the replace question says it.
  String _planName(BuildContext context, TrainingPlan plan) =>
      plan.name.isNotEmpty ? plan.name : trainingPlanTitle(context, plan);

  /// Starts the programme; asks before replacing a plan (PD-1). Returns an
  /// inline error for the sheet, or null when the sheet should close.
  Future<String?> _start(Programme p, DateTime startDate) async {
    final repo = AppScope.of(context).programmes;
    final lang = Localizations.localeOf(context).languageCode;
    final data = MemberDataScope.of(context);
    final shell = context.findAncestorStateOfType<MemberShellState>();
    final t = context.tr;
    Future<void> done() async {
      if (shell != null) await shell.refreshTraining();
      _after = (
        route: AppRoutes.memberTrainingPlan,
        snack: t('programmes.started'),
        error: false,
      );
    }

    try {
      await repo.start(p.id, startDate: startDate, lang: lang);
      await done();
      return null;
    } on ProgrammePlanExists catch (e) {
      if (e.sameProgramme) {
        _after = (
          route: AppRoutes.memberTrainingPlan,
          snack: null,
          error: false,
        );
        return null;
      }
      final current = data.trainingPlan;
      if (!mounted) return null;
      final body = [
        t('programmes.replaceBody')
            .replaceAll(
              '{plan}',
              current != null
                  ? _planName(context, current)
                  : t('training.myPlan'),
            )
            .replaceAll('{programme}', p.title),
        if (current != null && current.fromTrainer)
          t('programmes.replaceTrainer').replaceAll(
            '{trainer}',
            current.trainerName ?? t('training.yourTrainer'),
          ),
      ].join(' ');
      final ok = await showFFConfirmDialog(
        context,
        title: t('programmes.replaceTitle'),
        message: body,
        confirmLabel: t('programmes.replace'),
        cancelLabel: t('programmes.keep'),
        confirmKey: const Key('programme-replace-confirm'),
        cancelKey: const Key('programme-replace-keep'),
      );
      if (!ok) return null;
      try {
        await repo.start(p.id, startDate: startDate, replace: true, lang: lang);
        await done();
        return null;
      } on ProgrammeStartRefused catch (e) {
        return _refused(e.code);
      }
    } on ProgrammeStartRefused catch (e) {
      return _refused(e.code);
    } on ProgrammeUnavailable {
      _after = (
        route: AppRoutes.memberProgrammes,
        snack: t('programmes.unavailable'),
        error: true,
      );
      return null;
    } on ProgrammesDisabled {
      _after = (
        route: AppRoutes.memberTrainingPlan,
        snack: t('programmes.unavailable'),
        error: true,
      );
      return null;
    } catch (_) {
      return t('programmes.failed');
    }
  }

  String _refused(String code) => context.tr(
    code == 'start_too_far'
        ? 'programmes.startTooFar'
        : 'programmes.startInPast',
  );

  Future<void> _openStart(Programme p) async {
    final today = dayOf(widget.now ?? DateTime.now());
    _after = null;
    await showFFSheet<void>(
      context,
      title: context.tr('programmes.startWhen'),
      child: _StartSheet(
        programme: p,
        today: today,
        onStart: (date) => _start(p, date),
      ),
    );
    final after = _after;
    if (after == null || !mounted) return;
    final snack = after.snack;
    if (snack != null) {
      after.error
          ? FFSnack.of(context).error(snack)
          : FFSnack.of(context).success(snack);
    }
    context.go(after.route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = MemberDataScope.of(context);
    final back = Align(
      alignment: Alignment.centerLeft,
      child: FFButton(
        key: const Key('programme-back'),
        label: context.tr('programmes.title'),
        onPressed: () => context.go(AppRoutes.memberProgrammes),
        variant: FFButtonVariant.ghost,
        size: FFButtonSize.sm,
        icon: Icons.arrow_back,
      ),
    );
    final p = _programme;
    if (_gone) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          back,
          FFEmptyState(
            key: const Key('programme-not-available'),
            title: context.tr('programmes.notAvailable'),
            body: context.tr('programmes.unavailable'),
          ),
        ],
      );
    }
    if (_failed) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          back,
          FFErrorState(
            key: const Key('programme-error'),
            message: context.tr('programmes.loadFailed'),
            retryLabel: context.tr('programmes.retry'),
            onRetry: _load,
          ),
        ],
      );
    }
    if (p == null) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          back,
          FFSkeletonList(count: 4, semanticLabel: context.tr('common.loading')),
        ],
      );
    }
    final onThis = data.trainingPlan?.programmeId == p.id;
    final weeks = <List<ProgrammeDay>>[
      for (var i = 0; i < p.days.length; i += 7)
        p.days.sublist(i, (i + 7).clamp(0, p.days.length)),
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('programme-scroll'),
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              back,
              FFPageHeader(
                title: p.title,
                description: programmeMeta(context, p),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FFPill(label: programmeGoal(context, p.goal)),
              ),
              if ((p.summary ?? '').isNotEmpty) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Text(p.summary!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              // Same height for all three, even when a label wraps.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (type, icon) in const [
                      ('gym', Icons.fitness_center),
                      ('home', Icons.home_outlined),
                      ('rest', Icons.bedtime_outlined),
                    ]) ...[
                      Expanded(
                        child: FFStatTile(
                          key: Key('programme-stat-$type'),
                          icon: icon,
                          value: '${p.count(type)}',
                          label: context.tr('programmes.stat.$type'),
                        ),
                      ),
                      if (type != 'rest')
                        const SizedBox(width: FFTokens.spacingXs),
                    ],
                  ],
                ),
              ),
              FFSectionTitle(context.tr('programmes.needs')),
              Wrap(
                key: const Key('programme-needs'),
                spacing: FFTokens.spacingXs,
                runSpacing: FFTokens.spacingXs,
                children: p.needs.isEmpty
                    ? [FFPill(label: context.tr('programmes.noEquipment'))]
                    : [
                        for (final e in p.needs)
                          FFPill(label: programmeEquipment(context, e)),
                      ],
              ),
              for (final (i, week) in weeks.indexed) ...[
                FFSectionTitle(
                  context.tr('programmes.week').replaceAll('{n}', '${i + 1}'),
                ),
                for (final d in week) _DayRow(day: d),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FFTokens.spacingLg,
              FFTokens.spacingSm,
              FFTokens.spacingLg,
              FFTokens.spacingLg,
            ),
            child: FFButton(
              key: const Key('programme-start'),
              fullWidth: true,
              label: context.tr(
                onThis ? 'programmes.goToMine' : 'programmes.start',
              ),
              onPressed: onThis
                  ? () => context.go(AppRoutes.memberTrainingPlan)
                  : () => _openStart(p),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final ProgrammeDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final type = context.tr('programmes.type.${day.type}');
    final String detail;
    if (day.isRest) {
      detail = type;
    } else if (day.hasWorkout) {
      detail = [
        day.workoutName!,
        if (day.estimatedDuration != null)
          context
              .tr('programmes.minutes')
              .replaceAll('{n}', '${day.estimatedDuration}'),
      ].join(' · ');
    } else {
      detail = context.tr('programmes.gymAnyGym');
    }
    return Padding(
      key: Key('programme-day-${day.day}'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              context.tr('programmes.day').replaceAll('{n}', '${day.day}'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: day.isRest ? muted : null,
              ),
            ),
          ),
          Icon(
            programmeDayIcon(day.type),
            size: 20,
            color: day.isRest ? muted : theme.colorScheme.primary,
          ),
          const SizedBox(width: FFTokens.spacingXs),
          if (!day.isRest)
            Text(
              '$type · ',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          Expanded(
            child: Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: day.isRest ? muted : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "When do you want to start?": today, tomorrow or a date up to 30 days on.
class _StartSheet extends StatefulWidget {
  const _StartSheet({
    required this.programme,
    required this.today,
    required this.onStart,
  });

  final Programme programme;
  final DateTime today;
  final Future<String?> Function(DateTime date) onStart;

  @override
  State<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<_StartSheet> {
  String _choice = 'today';
  late DateTime _date = widget.today;
  bool _busy = false;
  String? _error;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.today,
      lastDate: widget.today.add(const Duration(days: 30)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = dayOf(picked);
        _choice = 'pick';
        _error = null;
      });
    }
  }

  Future<void> _go() async {
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onStart(_date);
    if (!mounted) return;
    if (error == null) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final end = _date.add(Duration(days: widget.programme.lengthDays - 1));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFSegmented(
          key: const Key('programme-start-when'),
          value: _choice,
          options: [
            ('today', context.tr('programmes.today')),
            ('tomorrow', context.tr('programmes.tomorrow')),
            ('pick', context.tr('programmes.pickDate')),
          ],
          onChanged: (v) {
            if (v == 'pick') {
              _pickDate();
              return;
            }
            setState(() {
              _choice = v;
              _error = null;
              _date = v == 'tomorrow'
                  ? widget.today.add(const Duration(days: 1))
                  : widget.today;
            });
          },
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context
              .tr('programmes.endsOn')
              .replaceAll(
                '{date}',
                DateFormat('EEE d MMM y', lang).format(end),
              ),
          key: const Key('programme-ends-on'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (_error != null) ...[
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            _error!,
            key: const Key('programme-start-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('programme-start-go'),
          fullWidth: true,
          loading: _busy,
          label: context.tr('programmes.startButton'),
          onPressed: _busy ? null : _go,
        ),
      ],
    );
  }
}
