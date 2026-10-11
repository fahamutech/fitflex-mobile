import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/activity/trainer_connection.dart';
import '../../shared/activity/training_plan.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../member/widgets/training_offer.dart' show weekdayLabel;

/// Opens the plan builder; resolves to true when a plan was sent.
Future<bool?> openTrainerTrainingPlan(
  BuildContext context, {
  required TrainerConnection connection,
  required List<TrainerPlan> savedWorkouts,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(
    builder: (_) => TrainerTrainingPlanPage(
      connection: connection,
      savedWorkouts: savedWorkouts,
    ),
  ),
);

const _rest = 'rest';
const _suggested = 'suggested';
const _maxTrainingDays = 6;

/// A trainer lays out a training plan for a client: for each day of the
/// week, rest, one of their saved workouts, or the session FitFlex
/// suggests — for a number of weeks. It is sent as an offer the client
/// accepts or declines.
class TrainerTrainingPlanPage extends StatefulWidget {
  const TrainerTrainingPlanPage({
    super.key,
    required this.connection,
    required this.savedWorkouts,
  });

  final TrainerConnection connection;
  final List<TrainerPlan> savedWorkouts;

  @override
  State<TrainerTrainingPlanPage> createState() =>
      _TrainerTrainingPlanPageState();
}

class _TrainerTrainingPlanPageState extends State<TrainerTrainingPlanPage> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  int _weeks = 4;
  int _suggestDays = 3;

  /// What each weekday (1 = Monday) holds: [_rest], [_suggested], or the id
  /// of a saved workout.
  final Map<int, String> _days = {for (var d = 1; d <= 7; d++) d: _rest};

  /// FitFlex's session for each weekday it suggests one.
  Map<int, PlanSessionOutline> _suggestion = const {};
  bool? _usedClientPreferences;
  bool _loadingSuggestion = false;
  bool _busy = false;
  String? _error;

  String get _client =>
      widget.connection.member?.displayName ?? context.tr('clients.client');

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _preferences => {'daysPerWeek': _suggestDays};

  Future<void> _suggest() async {
    final api = AppScope.of(context).api;
    final lang = Localizations.localeOf(context).languageCode;
    final failed = context.tr('trainerPlan.suggestFailed');
    setState(() {
      _loadingSuggestion = true;
      _error = null;
    });
    try {
      final res = await api.trainerSuggestTrainingPlan(widget.connection.id, {
        'durationWeeks': _weeks,
        'preferences': _preferences,
        'lang': lang,
      });
      final sessions = <int, PlanSessionOutline>{};
      for (final raw in (res['days'] as List? ?? const [])) {
        final s = PlanSessionOutline.tryParse(raw);
        if (s != null) sessions[s.day] = s;
      }
      if (!mounted) return;
      setState(() {
        _suggestion = sessions;
        _usedClientPreferences = res['usedClientPreferences'] == true;
        // FitFlex's days take its sessions; the trainer's own choices on
        // other days stay as they are.
        for (var d = 1; d <= 7; d++) {
          if (sessions.containsKey(d)) {
            _days[d] = _suggested;
          } else if (_days[d] == _suggested) {
            _days[d] = _rest;
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = failed);
    } finally {
      if (mounted) setState(() => _loadingSuggestion = false);
    }
  }

  int get _trainingDays => _days.values.where((v) => v != _rest).length;

  Future<void> _send() async {
    if (_trainingDays == 0) {
      setState(() => _error = context.tr('trainerPlan.needDay'));
      return;
    }
    if (_trainingDays > _maxTrainingDays) {
      setState(() => _error = context.tr('trainerPlan.tooManyDays'));
      return;
    }
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final failed = context.tr('trainerPlan.sendFailed');
    final stale = context.tr('trainerPlan.suggestionChanged');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.trainerOfferTrainingPlan(widget.connection.id, {
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        'durationWeeks': _weeks,
        'preferences': _preferences,
        'lang': lang,
        'days': [
          for (final e in _days.entries)
            if (e.value == _suggested)
              {'day': e.key, 'suggested': true}
            else if (e.value != _rest)
              {'day': e.key, 'planId': e.value},
        ],
      });
      navigator.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // The suggestion on screen no longer matches (a week later, say).
        _error = e.code == 'no_suggestion_for_day' ? stale : failed;
      });
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
    final saved = widget.savedWorkouts.where((p) => p.id != null).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr('trainerPlan.title').replaceAll('{name}', _client),
        ),
      ),
      body: ListView(
        key: const Key('trainer-plan-builder'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          Text(
            context.tr('trainerPlan.intro').replaceAll('{name}', _client),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          TextField(
            key: const Key('trainer-plan-name'),
            controller: _name,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: context.tr('trainerPlan.name'),
              border: const OutlineInputBorder(),
            ),
          ),
          Text(
            context.tr('training.weeksTitle'),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Wrap(
            spacing: FFTokens.spacingSm,
            children: [
              for (final w in trainingPlanWeeks)
                ChoiceChip(
                  key: Key('trainer-plan-weeks-$w'),
                  label: Text(
                    context.tr('training.weeks').replaceAll('{n}', '$w'),
                  ),
                  selected: _weeks == w,
                  onSelected: _busy ? null : (_) => setState(() => _weeks = w),
                ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingLg),
          FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('trainerPlan.suggestTitle'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  context.tr('trainerPlan.suggestBody'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Wrap(
                  spacing: FFTokens.spacingSm,
                  children: [
                    for (final d in trainingDaysPerWeek)
                      ChoiceChip(
                        key: Key('trainer-plan-suggest-days-$d'),
                        label: Text(
                          context.tr('training.days').replaceAll('{n}', '$d'),
                        ),
                        selected: _suggestDays == d,
                        onSelected: _busy || _loadingSuggestion
                            ? null
                            : (_) => setState(() => _suggestDays = d),
                      ),
                  ],
                ),
                const SizedBox(height: FFTokens.spacingSm),
                OutlinedButton.icon(
                  key: const Key('trainer-plan-suggest'),
                  onPressed: _busy || _loadingSuggestion ? null : _suggest,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(context.tr('trainerPlan.suggest')),
                ),
                if (_usedClientPreferences != null)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                    child: Text(
                      context
                          .tr(
                            _usedClientPreferences!
                                ? 'trainerPlan.usedClient'
                                : 'trainerPlan.usedDefaults',
                          )
                          .replaceAll('{name}', _client),
                      key: const Key('trainer-plan-suggest-basis'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            context.tr('trainerPlan.weekTitle'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (saved.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context.tr('trainerPlan.noSaved'),
                key: const Key('trainer-plan-no-saved'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (var d = 1; d <= 7; d++)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      weekdayLabel(context, d),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    // Rebuilt when FitFlex's suggestion changes the day.
                    key: ValueKey('day-$d-${_days[d]}-${_suggestion[d]?.name}'),
                    child: DropdownButtonFormField<String>(
                      key: Key('trainer-plan-day-$d'),
                      initialValue: _days[d],
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: _rest,
                          child: Text(context.tr('trainerPlan.rest')),
                        ),
                        if (_suggestion[d] case final s?)
                          DropdownMenuItem(
                            value: _suggested,
                            child: Text(
                              context
                                  .tr('trainerPlan.fitflexSession')
                                  .replaceAll('{name}', s.name),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        for (final p in saved)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _days[d] = v ?? _rest;
                              _error = null;
                            }),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: FFTokens.spacingLg),
          TextField(
            key: const Key('trainer-plan-note'),
            controller: _note,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: context
                  .tr('trainerPlan.note')
                  .replaceAll('{name}', _client),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: Text(
                _error!,
                key: const Key('trainer-plan-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const Key('trainer-plan-send'),
              onPressed: _busy ? null : _send,
              child: Text(
                context.tr('trainerPlan.send').replaceAll('{name}', _client),
              ),
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('trainerPlan.sendNote').replaceAll('{name}', _client),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
