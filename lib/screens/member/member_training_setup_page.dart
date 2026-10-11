import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/training_plan.dart';
import '../../shared/activity/training_repository.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/training_widgets.dart';

/// Sets up a training plan: the member's goal, where to focus, and how
/// they train — then FitFlex makes the plan. Everything starts filled in
/// from their profile, so "Create my plan" works straight away.
class MemberTrainingSetupPage extends StatefulWidget {
  const MemberTrainingSetupPage({super.key});

  @override
  State<MemberTrainingSetupPage> createState() =>
      _MemberTrainingSetupPageState();
}

class _MemberTrainingSetupPageState extends State<MemberTrainingSetupPage> {
  TrainingPreferences? _p;
  int _weeks = 4;
  bool _loading = false;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_p == null && !_loading) _load();
  }

  Future<void> _load() async {
    _loading = true;
    final repo = AppScope.of(context).training;
    TrainingPreferences p;
    try {
      p = await repo.preferences();
    } catch (_) {
      // The choices still work from FitFlex's defaults.
      p = const TrainingPreferences();
    }
    if (mounted) setState(() => _p = p);
  }

  void _set(TrainingPreferences p) => setState(() {
    _p = p;
    _error = null;
  });

  void _toggleArea(String area) {
    final p = _p!;
    final areas = [...p.targetAreas];
    if (areas.contains(area)) {
      areas.remove(area);
    } else if (areas.length < maxTrainingAreas) {
      areas.add(area);
    } else {
      setState(() => _error = context.tr('training.tooManyAreas'));
      return;
    }
    // Nothing chosen means the whole body.
    _set(p.copyWith(targetAreas: areas.isEmpty ? ['full_body'] : areas));
  }

  void _toggleEquipment(String item) {
    final p = _p!;
    var have = [...p.equipment];
    if (item == 'none') {
      have = ['none'];
    } else {
      have.remove('none');
      have.contains(item) ? have.remove(item) : have.add(item);
      if (have.isEmpty) have = ['none'];
    }
    _set(p.copyWith(equipment: have));
  }

  Future<bool> _confirmReplace() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('training.replaceTitle')),
          content: Text(ctx.tr('training.replaceBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('training.keepPlan')),
            ),
            FilledButton(
              key: const Key('training-replace-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('training.replace')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _create() async {
    final p = _p;
    if (p == null) return;
    final repo = AppScope.of(context).training;
    final data = MemberDataScope.of(context);
    final shell = context.findAncestorStateOfType<MemberShellState>();
    final router = GoRouter.maybeOf(context);
    final failed = context.tr('training.failed');
    var replace = data.trainingPlan != null;
    if (replace && !await _confirmReplace()) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.savePreferences(p);
      TrainingPlan plan;
      try {
        plan = await repo.generate(weeks: _weeks, replace: replace);
      } on ActivePlanExists {
        // A plan made elsewhere since this screen opened: ask, then go on.
        if (!mounted || !await _confirmReplace()) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        replace = true;
        plan = await repo.generate(weeks: _weeks, replace: true);
      }
      if (shell != null) {
        await shell.refreshTraining();
      } else {
        // Keep the screen right even without a shell (tests, previews).
        data.update((d) {
          d.trainingPlan = plan;
          d.trainingLoaded = true;
        });
      }
      router?.go(AppRoutes.memberTrainingPlan);
    } catch (_) {
      if (mounted) setState(() => _error = failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chips<T>({
    required String prefix,
    required List<T> options,
    required bool Function(T) selected,
    required void Function(T) onTap,
    required String Function(T) label,
  }) => Wrap(
    spacing: FFTokens.spacingSm,
    runSpacing: FFTokens.spacingXs,
    children: [
      for (final o in options)
        ChoiceChip(
          key: Key('$prefix-$o'),
          label: Text(label(o)),
          selected: selected(o),
          onSelected: _busy ? null : (_) => onTap(o),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _p;
    final back = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('training-back'),
        onPressed: () => context.go(AppRoutes.memberActivity),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text(context.tr('activity.title')),
      ),
    );
    if (p == null) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          back,
          const Padding(
            padding: EdgeInsets.all(FFTokens.spacingXl),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    Widget section(String key, {String? hint}) => Padding(
      padding: const EdgeInsets.only(
        top: FFTokens.spacingLg,
        bottom: FFTokens.spacingXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(key),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null)
            Text(context.tr(hint), style: theme.textTheme.bodySmall),
        ],
      ),
    );

    return ListView(
      key: const Key('training-setup-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        back,
        FFPageHeader(
          title: context.tr('training.setupTitle'),
          description: context.tr('training.setupBody'),
        ),
        section('training.goalTitle'),
        _chips<String>(
          prefix: 'training-goal',
          options: [
            ...trainingGoals,
            // A goal from an older profile that isn't on today's list.
            if (!trainingGoals.contains(p.goal)) p.goal,
          ],
          selected: (g) => p.goal == g,
          onTap: (g) => _set(_p!.copyWith(goal: g)),
          label: (g) => trainingGoalLabel(context, g),
        ),
        section('training.areasTitle', hint: 'training.areasHint'),
        for (final group in trainingAreaGroups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: FFTokens.spacingXs,
              bottom: FFTokens.spacing2xs,
            ),
            child: Text(
              context.tr('training.areaGroup.${group.key}'),
              style: theme.textTheme.labelLarge,
            ),
          ),
          Wrap(
            spacing: FFTokens.spacingSm,
            runSpacing: FFTokens.spacingXs,
            children: [
              for (final area in group.value)
                FilterChip(
                  key: Key('training-area-$area'),
                  label: Text(trainingAreaLabel(context, area)),
                  selected: p.targetAreas.contains(area),
                  onSelected: _busy ? null : (_) => _toggleArea(area),
                ),
            ],
          ),
        ],
        section('training.experienceTitle'),
        _chips<String>(
          prefix: 'training-experience',
          options: trainingExperienceLevels,
          selected: (l) => p.experience == l,
          onTap: (l) => _set(_p!.copyWith(experience: l)),
          label: (l) => context.tr('onboarding.level_$l'),
        ),
        section('training.envTitle'),
        _chips<String>(
          prefix: 'training-env',
          options: trainingEnvironments,
          selected: (e) => p.environment == e,
          onTap: (e) => _set(
            _p!.copyWith(
              environment: e,
              // A gym has its equipment unless they say otherwise.
              equipment: e == 'gym' && _p!.equipment.join() == 'none'
                  ? ['full_gym']
                  : null,
            ),
          ),
          label: (e) => context.tr('training.env.$e'),
        ),
        section('training.equipmentTitle', hint: 'training.equipmentHint'),
        Wrap(
          spacing: FFTokens.spacingSm,
          runSpacing: FFTokens.spacingXs,
          children: [
            for (final item in trainingEquipment)
              FilterChip(
                key: Key('training-equipment-$item'),
                label: Text(context.tr('training.equipment.$item')),
                selected: p.equipment.contains(item),
                onSelected: _busy ? null : (_) => _toggleEquipment(item),
              ),
          ],
        ),
        section('training.minutesTitle'),
        _chips<int>(
          prefix: 'training-minutes',
          options: trainingSessionMinutes,
          selected: (m) => p.sessionMinutes == m,
          onTap: (m) => _set(_p!.copyWith(sessionMinutes: m)),
          label: (m) => context.tr('training.minutes').replaceAll('{n}', '$m'),
        ),
        section('training.daysTitle'),
        _chips<int>(
          prefix: 'training-days',
          options: trainingDaysPerWeek,
          selected: (d) => p.daysPerWeek == d,
          onTap: (d) => _set(_p!.copyWith(daysPerWeek: d)),
          label: (d) => context.tr('training.days').replaceAll('{n}', '$d'),
        ),
        section('training.weeksTitle'),
        _chips<int>(
          prefix: 'training-weeks',
          options: trainingPlanWeeks,
          selected: (w) => _weeks == w,
          onTap: (w) => setState(() => _weeks = w),
          label: (w) => context.tr('training.weeks').replaceAll('{n}', '$w'),
        ),
        const SizedBox(height: FFTokens.spacingLg),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Text(
              _error!,
              key: const Key('training-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            key: const Key('training-generate'),
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('training.create')),
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr('training.privacyNote'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
