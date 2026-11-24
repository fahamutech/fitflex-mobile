import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/programme.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/programme_widgets.dart';

export 'member_programme_page.dart';

const _goals = [
  'lose_weight',
  'gain_muscle',
  'build_muscle',
  'stay_fit',
  'improve_endurance',
  'improve_flexibility',
  'learn_new_skill',
  'stress_relief',
];
const _levels = ['beginner', 'intermediate', 'advanced'];
const _lengths = [7, 14, 21, 28];
const _wheres = ['gym', 'home', 'outdoor', 'any'];

/// Programmes P1 (M1): the catalogue of live FitFlex programmes, filtered by
/// goal, level, length and where.
class MemberProgrammesPage extends StatefulWidget {
  const MemberProgrammesPage({super.key, this.initialGoal});

  /// Opens filtered to this goal ("Find your next programme").
  final String? initialGoal;

  @override
  State<MemberProgrammesPage> createState() => _MemberProgrammesPageState();
}

class _MemberProgrammesPageState extends State<MemberProgrammesPage> {
  late ProgrammeFilters _filters = ProgrammeFilters(
    goal: _goals.contains(widget.initialGoal) ? widget.initialGoal : null,
  );
  List<Programme>? _rows;
  bool _failed = false;
  bool _disabled = false;
  int _gen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rows == null && !_failed && !_disabled) _load();
  }

  Future<void> _load() async {
    final mine = ++_gen;
    final repo = AppScope.of(context).programmes;
    final lang = Localizations.localeOf(context).languageCode;
    setState(() {
      _rows = null;
      _failed = false;
    });
    try {
      final rows = await repo.catalogue(filters: _filters, lang: lang);
      if (mounted && mine == _gen) setState(() => _rows = rows);
    } on ProgrammesDisabled {
      if (mounted && mine == _gen) setState(() => _disabled = true);
    } catch (_) {
      if (mounted && mine == _gen) setState(() => _failed = true);
    }
  }

  void _set(ProgrammeFilters f) {
    _filters = f;
    _load();
  }

  Future<void> _pick<T>({
    required String title,
    required List<T> options,
    required T? current,
    required String Function(T) label,
    required void Function(T?) onPicked,
  }) async {
    final picked = await showFFSheet<(T?,)>(
      context,
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FFChoiceTile(
            title: context.tr('programmes.filter.any'),
            selected: current == null,
            onSelected: () => Navigator.of(context).pop((null,)),
          ),
          for (final o in options)
            FFChoiceTile(
              key: Key('programmes-option-$o'),
              title: label(o),
              selected: current == o,
              onSelected: () => Navigator.of(context).pop((o,)),
            ),
        ],
      ),
    );
    if (picked != null) onPicked(picked.$1);
  }

  Widget _chip<T>(
    String key,
    String name,
    T? value,
    String Function(T) label,
    List<T> options,
    ProgrammeFilters Function(T?) apply,
  ) => Padding(
    padding: const EdgeInsets.only(right: FFTokens.spacingXs),
    child: FFFilterChip(
      key: Key('programmes-filter-$key'),
      label: value == null ? name : label(value),
      selected: value != null,
      onSelected: () => _pick<T>(
        title: name,
        options: options,
        current: value,
        label: label,
        onPicked: (v) => _set(apply(v)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final plan = data.trainingPlan;
    String length(int n) => n == 28
        ? context.tr('programmes.length.28')
        : programmeDays(context, n);
    final back = Align(
      alignment: Alignment.centerLeft,
      child: FFButton(
        key: const Key('programmes-back'),
        label: context.tr('programmes.back'),
        onPressed: () => context.go(AppRoutes.memberTrainingPlan),
        variant: FFButtonVariant.ghost,
        size: FFButtonSize.sm,
        icon: Icons.arrow_back,
      ),
    );
    if (_disabled) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          back,
          FFEmptyState(
            key: const Key('programmes-not-available'),
            title: context.tr('programmes.notAvailable'),
            body: context.tr('programmes.notAvailableBody'),
          ),
        ],
      );
    }
    final rows = _rows;
    return ListView(
      key: const Key('programmes-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        back,
        FFPageHeader(title: context.tr('programmes.title')),
        if (plan != null && plan.isProgramme)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFActionTile(
              key: const Key('programmes-current'),
              icon: Icons.flag_outlined,
              title: context
                  .tr('programmes.onProgramme')
                  .replaceAll('{title}', plan.name)
                  .replaceAll('{n}', '${plan.currentDay ?? 1}')
                  .replaceAll('{N}', '${plan.lengthDays ?? plan.days.length}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.memberTrainingPlan),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip<String>(
                'goal',
                context.tr('programmes.filter.goal'),
                _filters.goal,
                (v) => programmeGoal(context, v),
                _goals,
                (v) => _filters.copyWith(goal: () => v),
              ),
              _chip<String>(
                'level',
                context.tr('programmes.filter.level'),
                _filters.level,
                (v) => programmeLevel(context, v),
                _levels,
                (v) => _filters.copyWith(level: () => v),
              ),
              _chip<int>(
                'length',
                context.tr('programmes.filter.length'),
                _filters.length,
                length,
                _lengths,
                (v) => _filters.copyWith(length: () => v),
              ),
              _chip<String>(
                'where',
                context.tr('programmes.filter.where'),
                _filters.where,
                (v) => programmeWhere(context, v),
                _wheres,
                (v) => _filters.copyWith(where: () => v),
              ),
              if (!_filters.isEmpty)
                FFButton(
                  key: const Key('programmes-clear'),
                  label: context.tr('programmes.clear'),
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                  onPressed: () => _set(const ProgrammeFilters()),
                ),
            ],
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (_failed)
          FFErrorState(
            key: const Key('programmes-error'),
            message: context.tr('programmes.loadFailed'),
            retryLabel: context.tr('programmes.retry'),
            onRetry: _load,
          )
        else if (rows == null)
          FFSkeletonList(semanticLabel: context.tr('common.loading'))
        else if (rows.isEmpty)
          _filters.isEmpty
              ? FFEmptyState(
                  key: const Key('programmes-empty'),
                  title: context.tr('programmes.emptyTitle'),
                  body: context.tr('programmes.emptyBody'),
                )
              : FFEmptyState(
                  key: const Key('programmes-no-match'),
                  title: context.tr('programmes.noMatch'),
                  action: FFButton(
                    key: const Key('programmes-clear-filters'),
                    label: context.tr('programmes.clearFilters'),
                    variant: FFButtonVariant.secondary,
                    onPressed: () => _set(const ProgrammeFilters()),
                  ),
                )
        else
          for (final p in rows) _ProgrammeCard(programme: p),
      ],
    );
  }
}

class _ProgrammeCard extends StatelessWidget {
  const _ProgrammeCard({required this.programme});

  final Programme programme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = programme;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: InkWell(
        key: Key('programme-card-${p.id}'),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        onTap: () => context.go(programmeRoute(p.id)),
        child: FFCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      p.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (p.free)
                    FFBadge(
                      label: context.tr('programmes.free'),
                      tone: FFBadgeTone.success,
                    ),
                ],
              ),
              const SizedBox(height: FFTokens.spacingXs),
              Text(
                programmeMeta(context, p),
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: FFTokens.spacingXs),
              Align(
                alignment: Alignment.centerLeft,
                child: FFPill(label: programmeGoal(context, p.goal)),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              ProgrammeDayStrip(programme: p),
            ],
          ),
        ),
      ),
    );
  }
}
