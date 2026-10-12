import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../shared/activity/activity.dart';
import '../../shared/activity/trainer_connection.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../member/widgets/activity_widgets.dart' show activityTypeLabel;
import '../member/widgets/workout_widgets.dart' show muscleLabel;
import 'widgets/exercise_picker.dart';

/// Opens the editor; resolves to true when the plan was saved or deleted.
Future<bool?> openTrainerPlanEditor(
  BuildContext context, {
  TrainerPlan? plan,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(builder: (_) => TrainerPlanEditorPage(plan: plan)),
);

const planActivityTypes = [
  ActivityType.strength,
  ActivityType.hiit,
  ActivityType.functional,
  ActivityType.mobility,
  ActivityType.stretching,
  ActivityType.sports,
  ActivityType.other,
];

const planMuscleGroups = [
  'chest',
  'back',
  'shoulders',
  'arms',
  'legs',
  'hamstrings',
  'glutes',
  'calves',
  'core',
  'hips',
  'full_body',
];

/// Create or edit a reusable workout plan: name, type, duration and the
/// exercises with their sets, reps or time, weight tracking and
/// instructions.
class TrainerPlanEditorPage extends StatefulWidget {
  const TrainerPlanEditorPage({super.key, this.plan});

  final TrainerPlan? plan;

  @override
  State<TrainerPlanEditorPage> createState() => _TrainerPlanEditorPageState();
}

class _TrainerPlanEditorPageState extends State<TrainerPlanEditorPage> {
  late final TrainerPlan _plan = widget.plan == null
      ? TrainerPlan(exercises: [PlanExercise()])
      : TrainerPlan.fromJson({'id': widget.plan!.id, ...widget.plan!.toJson()});
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  bool get _isNew => widget.plan?.id == null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_plan.exercises.isEmpty) {
      _toast('plans.needExercise');
      return;
    }
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await api.trainerSavePlan(_plan.id, _plan.toJson());
      navigator.pop(true);
    } catch (_) {
      _toast('plans.saveFailed');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('plans.deleteTitle'),
      message: context.tr('plans.deleteBody'),
      cancelLabel: context.tr('workout.keepGoing'),
      confirmLabel: context.tr('plans.delete'),
      confirmKey: const Key('plan-delete-confirm'),
    );
    if (ok != true || !mounted) return;
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await api.trainerDeletePlan(_plan.id!);
      navigator.pop(true);
    } catch (_) {
      _toast('plans.saveFailed');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String key) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.tr(key))));

  Future<void> _addFromLibrary() async {
    final picked = await showExercisePicker(context);
    if (picked == null || !mounted) return;
    setState(() {
      // A blank first line is what a new workout starts with: fill it
      // instead of leaving it empty above the picked one.
      final first = _plan.exercises.firstOrNull;
      if (_plan.exercises.length == 1 &&
          first != null &&
          first.exerciseName.trim().isEmpty) {
        _plan.exercises[0] = picked.toPlanExercise();
      } else {
        _plan.exercises.add(picked.toPlanExercise());
      }
    });
  }

  String? _required(String? v) =>
      (v ?? '').trim().isEmpty ? context.tr('plans.required') : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(_isNew ? 'plans.new' : 'plans.edit')),
        actions: [
          if (!_isNew)
            IconButton(
              key: const Key('plan-delete'),
              tooltip: context.tr('plans.delete'),
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            FFTextField(
              key: const Key('plan-name'),
              initialValue: _plan.name,
              label: context.tr('plans.name'),
              validator: _required,
              onChanged: (v) => _plan.name = v,
              maxLength: 80,
            ),
            FFTextField(
              key: const Key('plan-description'),
              initialValue: _plan.description,
              label: context.tr('plans.description'),
              maxLines: 2,
              minLines: 1,
              onChanged: (v) => _plan.description = v,
              maxLength: 500,
            ),
            Text(context.tr('plans.type'), style: theme.textTheme.labelLarge),
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final t in planActivityTypes)
                  ChoiceChip(
                    key: Key('plan-type-${t.wire}'),
                    label: Text(activityTypeLabel(context, t)),
                    selected: _plan.activityType == t.wire,
                    onSelected: (_) =>
                        setState(() => _plan.activityType = t.wire),
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingMd),
            FFTextField(
              key: const Key('plan-duration'),
              initialValue: _plan.estimatedDuration?.toString(),
              label: context.tr('plans.duration'),
              suffixText: context.tr('activity.min'),
              validator: (v) {
                if ((v ?? '').isEmpty) return null;
                final n = int.tryParse(v!);
                return n == null || n < 1 || n > 600
                    ? context.tr('plans.invalidNumber')
                    : null;
              },
              keyboardType: TextInputType.number,
              onChanged: (v) => _plan.estimatedDuration = int.tryParse(v),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            FFSectionTitle(context.tr('plans.exercises')),
            for (var i = 0; i < _plan.exercises.length; i++)
              _ExerciseEditor(
                key: ObjectKey(_plan.exercises[i]),
                index: i,
                exercise: _plan.exercises[i],
                required: _required,
                onRemove: _plan.exercises.length > 1
                    ? () => setState(() => _plan.exercises.removeAt(i))
                    : null,
                onChanged: () => setState(() {}),
                // A new object, so the card's fields start again from it.
                onPicked: (picked) =>
                    setState(() => _plan.exercises[i] = picked),
              ),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingXs,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('plan-add-from-library'),
                  onPressed: _plan.exercises.length >= 20
                      ? null
                      : _addFromLibrary,
                  icon: const Icon(Icons.library_add_outlined),
                  label: Text(context.tr('exercisePicker.add')),
                ),
                FFButton(
                  key: const Key('plan-add-exercise'),
                  label: context.tr('plans.addExercise'),
                  onPressed: _plan.exercises.length >= 20
                      ? null
                      : () =>
                            setState(() => _plan.exercises.add(PlanExercise())),
                  variant: FFButtonVariant.secondary,
                  icon: Icons.add,
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingLg),
            FFButton(
              key: const Key('plan-save'),
              label: context.tr('plans.save'),
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseEditor extends StatelessWidget {
  const _ExerciseEditor({
    super.key,
    required this.index,
    required this.exercise,
    required this.required,
    required this.onRemove,
    required this.onChanged,
    required this.onPicked,
  });

  final int index;
  final PlanExercise exercise;
  final String? Function(String?) required;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  /// The trainer chose a library exercise for this line.
  final void Function(PlanExercise picked) onPicked;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final timed = e.isTimed;
    String? positive(String? v, int max) {
      final n = int.tryParse(v ?? '');
      return n == null || n < 1 || n > max
          ? context.tr('plans.invalidNumber')
          : null;
    }

    return FFCard(
      key: Key('plan-exercise-$index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: Key('exercise-name-$index'),
                  initialValue: e.exerciseName,
                  decoration: InputDecoration(
                    labelText: context
                        .tr('plans.exerciseN')
                        .replaceAll('{n}', '${index + 1}'),
                    isDense: true,
                  ),
                  validator: required,
                  onChanged: (v) {
                    final linked = e.fromLibrary;
                    e.renamed(v);
                    // Typed over into something else: the note goes.
                    if (linked != e.fromLibrary) onChanged();
                  },
                ),
              ),
              if (onRemove != null)
                IconButton(
                  key: Key('exercise-remove-$index'),
                  tooltip: context.tr('plans.removeExercise'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FFButton(
              key: Key('exercise-pick-$index'),
              label: context.tr(
                e.fromLibrary
                    ? 'exercisePicker.change'
                    : 'exercisePicker.choose',
              ),
              onPressed: () async {
                final picked = await showExercisePicker(context);
                if (picked != null) onPicked(picked.toPlanExercise());
              },
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              icon: Icons.library_books_outlined,
            ),
          ),
          if (e.fromLibrary)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
              child: Text(
                context.tr('exercisePicker.linked'),
                key: Key('exercise-linked-$index'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          const SizedBox(height: FFTokens.spacingSm),
          DropdownButtonFormField<String?>(
            key: Key('exercise-muscle-$index'),
            initialValue: e.muscleGroup,
            isDense: true,
            decoration: InputDecoration(
              labelText: context.tr('plans.muscleGroup'),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(context.tr('plans.noMuscle')),
              ),
              for (final m in {
                ...planMuscleGroups,
                // A library exercise names a finer area (quadriceps…).
                ?e.muscleGroup,
              })
                DropdownMenuItem(
                  value: m,
                  child: Text(muscleLabel(context, m)),
                ),
            ],
            onChanged: (v) => e.muscleGroup = v,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          SizedBox(
            width: double.infinity,
            child: FFSegmented(
              key: Key('exercise-mode-$index'),
              value: timed ? 'time' : 'reps',
              options: [
                ('reps', context.tr('plans.byReps')),
                ('time', context.tr('plans.byTime')),
              ],
              onChanged: (v) {
                if (v == 'time') {
                  e.reps = null;
                  e.duration ??= 30;
                } else {
                  e.duration = null;
                  e.reps ??= 10;
                }
                onChanged();
              },
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: Key('exercise-sets-$index'),
                  initialValue: '${e.sets}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: context.tr('plans.sets'),
                    isDense: true,
                  ),
                  validator: (v) => positive(v, 10),
                  onChanged: (v) => e.sets = int.tryParse(v) ?? e.sets,
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: TextFormField(
                  // Rebuild when switching reps ↔ time.
                  key: Key('exercise-target-$index-${timed ? 't' : 'r'}'),
                  initialValue: '${timed ? e.duration : e.reps}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: context.tr(
                      timed ? 'plans.seconds' : 'plans.reps',
                    ),
                    isDense: true,
                  ),
                  validator: (v) => positive(v, timed ? 7200 : 1000),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (timed) {
                      e.duration = n;
                    } else {
                      e.reps = n;
                    }
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            key: Key('exercise-weight-$index'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: e.tracksWeight,
            onChanged: (v) {
              e.tracksWeight = v;
              onChanged();
            },
            title: Text(context.tr('plans.tracksWeight')),
          ),
          TextFormField(
            key: Key('exercise-instructions-$index'),
            initialValue: e.instructions,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: context.tr('plans.instructions'),
              isDense: true,
            ),
            onChanged: (v) => e.instructions = v,
          ),
        ],
      ),
    );
  }
}
