import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/workout.dart';
import '../../shared/activity/workout_repository.dart';
import '../../shared/activity/workout_summary.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/workout_widgets.dart';

/// Runs one workout: start it, log each set (reps, weight, duration), mark
/// sets and exercises done, add notes, and finish — then shows the summary.
/// Progress is saved as the member goes, so closing the app loses nothing.
class MemberWorkoutPage extends StatefulWidget {
  const MemberWorkoutPage({super.key, required this.workoutId, this.now});

  final String workoutId;

  /// Injectable clock for tests.
  final DateTime Function()? now;

  @override
  State<MemberWorkoutPage> createState() => _MemberWorkoutPageState();
}

class _MemberWorkoutPageState extends State<MemberWorkoutPage> {
  Workout? _w;
  bool _loaded = false;
  bool _busy = false;
  bool _dirty = false;
  WorkoutSummary? _summary;
  Timer? _tick;
  Timer? _autosave;
  final Map<String, TextEditingController> _fields = {};
  final Set<String> _noteOpen = {};

  DateTime _now() => (widget.now ?? DateTime.now)();

  late WorkoutRepository _repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = AppScope.of(context).workouts;
    if (_loaded) return;
    final data = MemberDataScope.of(context);
    if (!data.workoutsLoaded) return;
    _loaded = true;
    final found = data.workouts.where((w) => w.id == widget.workoutId);
    _w = found.isEmpty ? null : found.first.copy();
    final w = _w;
    if (w != null && w.status == WorkoutStatus.completed) {
      _summary = summarizeWorkout(
        w,
        durationMinutes: _completedMinutes(w),
        history: data.workouts,
      );
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _autosave?.cancel();
    // Flush unsaved edits; the page is going away, so don't await.
    final w = _w;
    if (_dirty && w != null && w.status.isOpen) {
      unawaited(_repo.save(w).then((_) {}, onError: (_) {}));
    }
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _completedMinutes(Workout w) {
    final s = w.startedAt, e = w.completedAt;
    if (s == null || e == null) return w.estimatedDuration ?? 0;
    return e.difference(s).inMinutes.clamp(1, 600);
  }

  void _syncTicker() {
    _tick?.cancel();
    if (_w?.status == WorkoutStatus.inProgress) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _changed() {
    _dirty = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 1500), _save);
    setState(() {});
  }

  Future<void> _save() async {
    final w = _w;
    if (w == null || !_dirty || !w.status.isOpen) return;
    _dirty = false;
    try {
      await _repo.save(w);
    } catch (_) {
      _dirty = true; // retried on the next change or on leaving
    }
  }

  void _toast(String key) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.tr(key))));

  Future<void> _start() async {
    final w = _w!;
    setState(() => _busy = true);
    try {
      final started = await _repo.start(w.id);
      // Keep anything already typed; take status and start time from the
      // server.
      setState(() {
        _w = w.copy(status: started.status, startedAt: started.startedAt);
      });
      _syncTicker();
      unawaited(_shell?.refreshAfterWorkout());
    } catch (_) {
      _toast('workout.saveFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  MemberShellState? get _shell =>
      context.findAncestorStateOfType<MemberShellState>();

  Future<void> _skip() async {
    final ok = await _confirm(
      context.tr('workout.skipTitle'),
      context.tr('workout.skipBody'),
      context.tr('workout.skip'),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.skip(_w!.id);
      _dirty = false;
      await _shell?.refreshAfterWorkout();
      if (mounted) context.go(AppRoutes.memberActivity);
    } catch (_) {
      _toast('workout.saveFailed');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final w = _w!;
    if (w.setsCompleted == 0) {
      _toast('workout.nothingDone');
      return;
    }
    if (w.setsCompleted < w.setsTotal) {
      final ok = await _confirm(
        context.tr('workout.finishTitle'),
        context
            .tr('workout.finishPartial')
            .replaceAll('{done}', '${w.setsCompleted}')
            .replaceAll('{total}', '${w.setsTotal}'),
        context.tr('workout.finish'),
      );
      if (ok != true || !mounted) return;
    }
    final data = MemberDataScope.of(context);
    setState(() => _busy = true);
    _autosave?.cancel();
    try {
      final done = await _repo.complete(w);
      _dirty = false;
      final summary = summarizeWorkout(
        done.workout,
        durationMinutes: done.activity.durationMinutes ?? 0,
        history: data.workouts,
      );
      setState(() {
        _w = done.workout;
        _summary = summary;
      });
      _syncTicker();
      await _shell?.refreshAfterWorkout();
    } catch (_) {
      _toast('workout.saveFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(String title, String body, String action) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('workout.keepGoing')),
            ),
            FilledButton(
              key: const Key('workout-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      );

  TextEditingController _field(String key, String? initial) =>
      _fields.putIfAbsent(key, () => TextEditingController(text: initial));

  String _fmtNum(num? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? '${v.round()}' : '$v';
  }

  void _toggleSet(WorkoutExercise e, WorkoutSet s, bool done) {
    s.completed = done;
    // Ticking a set you didn't type into means you did the target.
    if (done) {
      if (!e.isTimed && s.reps == null) {
        s.reps = s.targetReps;
        _field('${s.id}-reps', null).text = _fmtNum(s.reps);
      }
      if (e.isTimed && s.duration == null) {
        s.duration = s.targetDuration;
        _field('${s.id}-dur', null).text = _fmtNum(s.duration);
      }
    }
    _changed();
  }

  void _toggleExercise(WorkoutExercise e) {
    final done = !e.isComplete;
    for (final s in e.workoutSets) {
      _toggleSet(e, s, done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    if (!data.workoutsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final w = _w;
    if (w == null) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          _BackRow(),
          FFEmptyState(title: context.tr('workout.notFound')),
        ],
      );
    }
    if (_summary != null) {
      return _CompleteView(workout: w, summary: _summary!);
    }
    return _session(context, w);
  }

  Widget _session(BuildContext context, Workout w) {
    final theme = Theme.of(context);
    final live = w.status == WorkoutStatus.inProgress;
    final elapsed = live && w.startedAt != null
        ? _now().difference(w.startedAt!)
        : null;
    return ListView(
      key: const Key('workout-session'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        _BackRow(),
        Text(
          w.name,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (w.description != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(w.description!, style: theme.textTheme.bodyMedium),
          ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(
          [
            workoutMeta(context, w),
            if (elapsed != null)
              '${context.tr('workout.elapsed')} ${_clock(elapsed)}',
            if (live)
              '${w.setsCompleted}/${w.setsTotal} ${context.tr('workout.sets')}',
          ].join(' · '),
          key: const Key('workout-status-line'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (w.status == WorkoutStatus.planned) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('workout-start'),
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.play_arrow),
              label: Text(context.tr('workout.start')),
            ),
          ),
          Center(
            child: TextButton(
              key: const Key('workout-skip'),
              onPressed: _busy ? null : _skip,
              child: Text(context.tr('workout.skip')),
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
        ],
        if (w.status == WorkoutStatus.skipped)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
            child: FFPill(label: context.tr('workout.status.skipped')),
          ),
        for (final e in w.exercises) _exerciseCard(context, e, live),
        if (live) ...[
          const SizedBox(height: FFTokens.spacingSm),
          TextField(
            key: const Key('workout-notes'),
            controller: _field('workout-notes', w.notes),
            maxLines: 3,
            minLines: 1,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: context.tr('workout.notes'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              w.notes = v.trim().isEmpty ? null : v;
              _changed();
            },
          ),
          const SizedBox(height: FFTokens.spacingSm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('workout-finish'),
              onPressed: _busy ? null : _finish,
              icon: const Icon(Icons.flag_outlined),
              label: Text(context.tr('workout.finish')),
            ),
          ),
        ],
      ],
    );
  }

  String _clock(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Widget _exerciseCard(BuildContext context, WorkoutExercise e, bool live) {
    final theme = Theme.of(context);
    final noteOpen = _noteOpen.contains(e.id) || (e.notes ?? '').isNotEmpty;
    return FFCard(
      key: Key('exercise-${e.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.exerciseName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: e.isComplete
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    Text(
                      [
                        exerciseTarget(context, e),
                        if (e.muscleGroup != null)
                          muscleLabel(context, e.muscleGroup!),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (live)
                IconButton(
                  key: Key('exercise-done-${e.id}'),
                  tooltip: context.tr('workout.markExercise'),
                  onPressed: () => _toggleExercise(e),
                  icon: Icon(
                    e.isComplete
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color: e.isComplete ? theme.colorScheme.primary : null,
                  ),
                ),
            ],
          ),
          if (e.instructions != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(e.instructions!, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: FFTokens.spacingSm),
          for (final s in e.workoutSets) _setRow(context, e, s, live),
          if (live)
            noteOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                    child: TextField(
                      key: Key('exercise-note-${e.id}'),
                      controller: _field('${e.id}-note', e.notes),
                      maxLength: 500,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: context.tr('workout.exerciseNote'),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        e.notes = v.trim().isEmpty ? null : v;
                        _changed();
                      },
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: Key('exercise-add-note-${e.id}'),
                      onPressed: () => setState(() => _noteOpen.add(e.id)),
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: Text(context.tr('workout.addNote')),
                    ),
                  )
          else if ((e.notes ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(e.notes!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _setRow(
    BuildContext context,
    WorkoutExercise e,
    WorkoutSet s,
    bool live,
  ) {
    final theme = Theme.of(context);
    Widget numberField({
      required String keySuffix,
      required String? initial,
      required String hint,
      required String unit,
      required bool decimal,
      required void Function(String) onChanged,
    }) => Expanded(
      child: TextField(
        key: Key('set-${s.id}-$keySuffix'),
        controller: _field('${s.id}-$keySuffix', initial),
        enabled: live,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
          ),
        ],
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          suffixText: unit,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              '${context.tr('workout.set')} ${s.setNumber}',
              style: theme.textTheme.labelLarge,
            ),
          ),
          if (e.isTimed)
            numberField(
              keySuffix: 'dur',
              initial: _fmtNum(s.duration),
              hint: _fmtNum(s.targetDuration),
              unit: context.tr('workout.secondsShort'),
              decimal: false,
              onChanged: (v) {
                s.duration = int.tryParse(v);
                _changed();
              },
            )
          else
            numberField(
              keySuffix: 'reps',
              initial: _fmtNum(s.reps),
              hint: _fmtNum(s.targetReps),
              unit: context.tr('workout.reps'),
              decimal: false,
              onChanged: (v) {
                s.reps = int.tryParse(v);
                _changed();
              },
            ),
          if (e.tracksWeight) ...[
            const SizedBox(width: FFTokens.spacingSm),
            numberField(
              keySuffix: 'kg',
              initial: _fmtNum(s.weight),
              hint: 'kg',
              unit: 'kg',
              decimal: true,
              onChanged: (v) {
                s.weight = double.tryParse(v.replaceAll(',', '.'));
                _changed();
              },
            ),
          ],
          Checkbox(
            key: Key('set-${s.id}-done'),
            value: s.completed,
            onChanged: live ? (v) => _toggleSet(e, s, v ?? false) : null,
          ),
        ],
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('workout-back'),
        onPressed: () => context.go(AppRoutes.memberActivity),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text(context.tr('activity.title')),
      ),
    );
  }
}

class _CompleteView extends StatelessWidget {
  const _CompleteView({required this.workout, required this.summary});

  final Workout workout;
  final WorkoutSummary summary;

  String _recordValue(BuildContext context, WorkoutRecord r) {
    String n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
    return switch (r.kind) {
      WorkoutRecordKind.weight => '${n(r.value)} kg',
      WorkoutRecordKind.reps => '${n(r.value)} ${context.tr('workout.reps')}',
      WorkoutRecordKind.duration =>
        '${n(r.value)} ${context.tr('workout.secondsShort')}',
    };
  }

  String _previous(BuildContext context, WorkoutRecord r) {
    final prev = WorkoutRecord(
      exerciseName: r.exerciseName,
      kind: r.kind,
      value: r.previous,
      previous: 0,
    );
    return context
        .tr('workout.previousBest')
        .replaceAll('{value}', _recordValue(context, prev));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    Widget tile(IconData icon, String label, String value) => Expanded(
      child: FFStatTile(icon: icon, value: value, label: label),
    );
    return ListView(
      key: const Key('workout-complete'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        _BackRow(),
        Icon(Icons.emoji_events, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr('workout.complete'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          workout.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: FFTokens.spacingLg),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                Icons.timer_outlined,
                context.tr('workout.duration'),
                '${s.durationMinutes} ${context.tr('activity.min')}',
              ),
              const SizedBox(width: FFTokens.spacingSm),
              tile(
                Icons.fitness_center,
                context.tr('workout.exercisesDone'),
                '${s.exercisesCompleted}/${s.exercisesTotal}',
              ),
              const SizedBox(width: FFTokens.spacingSm),
              tile(
                Icons.repeat,
                context.tr('workout.setsDone'),
                '${s.setsCompleted}/${s.setsTotal}',
              ),
            ],
          ),
        ),
        if (s.records.isNotEmpty) ...[
          FFSectionTitle(context.tr('workout.newRecords')),
          for (final r in s.records)
            FFCard(
              key: Key('workout-record-${r.exerciseName}'),
              child: Row(
                children: [
                  const Icon(
                    Icons.emoji_events_outlined,
                    color: FFTokens.warning500,
                  ),
                  const SizedBox(width: FFTokens.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r.exerciseName} · ${_recordValue(context, r)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _previous(context, r),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          context.tr('workout.countsToward'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          key: const Key('workout-done'),
          onPressed: () => context.go(AppRoutes.memberActivity),
          child: Text(context.tr('workout.done')),
        ),
      ],
    );
  }
}
