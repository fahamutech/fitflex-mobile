import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/trainer_connection.dart';
import '../../../shared/activity/training_plan.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';

/// Opens the FitFlex exercise library for a trainer to choose from.
/// Resolves to the exercise picked, or null.
Future<LibraryExercise?> showExercisePicker(BuildContext context) =>
    showModalBottomSheet<LibraryExercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ExercisePickerSheet(),
    );

/// "Chest · No equipment · 3 × 10".
String libraryExerciseLine(BuildContext context, LibraryExercise e) => [
  e.targetAreas.take(2).map((a) => context.tr('training.area.$a')).join(', '),
  e.equipment.map((x) => context.tr('training.equipment.$x')).join(', '),
  e.reps != null
      ? '${e.sets} × ${e.reps}'
      : '${e.sets} × ${e.duration ?? 0} ${context.tr('workout.secondsShort')}',
].where((s) => s.isNotEmpty).join(' · ');

class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet();

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  List<LibraryExercise>? _all;
  bool _failed = false;
  bool _started = false;
  String _search = '';
  String? _area;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    final lang = Localizations.localeOf(context).languageCode;
    setState(() => _failed = false);
    try {
      final rows = await api.trainingExercises(lang: lang);
      if (!mounted) return;
      setState(
        () =>
            _all = [for (final r in rows) ?LibraryExercise.tryParse(r)]
              ..sort((a, b) => a.name.compareTo(b.name)),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = _all;
    final query = _search.trim().toLowerCase();
    final shown = [
      for (final e in all ?? const <LibraryExercise>[])
        if ((_area == null || e.targetAreas.contains(_area)) &&
            (query.isEmpty || e.name.toLowerCase().contains(query)))
          e,
    ];
    // Only the areas the library actually has something for.
    final areas = [
      for (final a in trainingAreaGroups.values.expand((x) => x))
        if ((all ?? const []).any((e) => e.targetAreas.contains(a))) a,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          FFTokens.spacingLg,
          FFTokens.spacingLg,
          FFTokens.spacingLg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Column(
            key: const Key('exercise-picker'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('exercisePicker.title'),
                style: theme.textTheme.titleLarge,
              ),
              Text(
                context.tr('exercisePicker.body'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              TextField(
                key: const Key('exercise-picker-search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.tr('exercisePicker.search'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              if (areas.isNotEmpty) ...[
                const SizedBox(height: FFTokens.spacingSm),
                // A handful of chips: all built, so each can be reached.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          right: FFTokens.spacingSm,
                        ),
                        child: ChoiceChip(
                          key: const Key('exercise-picker-area-all'),
                          label: Text(context.tr('exercisePicker.allAreas')),
                          selected: _area == null,
                          onSelected: (_) => setState(() => _area = null),
                        ),
                      ),
                      for (final a in areas)
                        Padding(
                          padding: const EdgeInsets.only(
                            right: FFTokens.spacingSm,
                          ),
                          child: ChoiceChip(
                            key: Key('exercise-picker-area-$a'),
                            label: Text(context.tr('training.area.$a')),
                            selected: _area == a,
                            onSelected: (_) => setState(() => _area = a),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: FFTokens.spacingSm),
              Expanded(
                child: _failed
                    ? FFEmptyState(
                        key: const Key('exercise-picker-failed'),
                        title: context.tr('exercisePicker.failed'),
                        action: FilledButton.tonal(
                          key: const Key('exercise-picker-retry'),
                          onPressed: _load,
                          child: Text(context.tr('exercisePicker.retry')),
                        ),
                      )
                    : all == null
                    ? const Center(child: CircularProgressIndicator())
                    : shown.isEmpty
                    ? FFEmptyState(
                        key: const Key('exercise-picker-none'),
                        title: context.tr('exercisePicker.none'),
                        body: context.tr('exercisePicker.noneBody'),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final e = shown[i];
                          return ListTile(
                            key: Key('exercise-pick-${e.id}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(e.name),
                            subtitle: Text(libraryExerciseLine(context, e)),
                            trailing: Text(
                              context.tr('onboarding.level_${e.difficulty}'),
                              style: theme.textTheme.bodySmall,
                            ),
                            onTap: () => Navigator.pop(context, e),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
