import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/training_plan.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

/// Programmes P1: what the member did in the programme that just ended.
class MemberProgrammeSummaryPage extends StatefulWidget {
  const MemberProgrammeSummaryPage({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<MemberProgrammeSummaryPage> createState() =>
      _MemberProgrammeSummaryPageState();
}

List<Widget> _tiles(BuildContext context, TrainingPlan plan) => [
  FFStatTile(
    icon: Icons.event_available,
    value: '${plan.completed}/${plan.sessions}',
    label: context.tr('programmes.sum.days'),
  ),
  FFStatTile(
    icon: Icons.fitness_center,
    value: '${plan.byWorkout}',
    label: context.tr('programmes.sum.workouts'),
  ),
  FFStatTile(
    icon: Icons.qr_code_scanner,
    value: '${plan.byCheckin}',
    label: context.tr('programmes.sum.checkins'),
  ),
  FFStatTile(
    icon: Icons.local_fire_department,
    value: '${plan.bestStreak}',
    label: context.tr('programmes.sum.bestStreak'),
  ),
];

class _MemberProgrammeSummaryPageState
    extends State<MemberProgrammeSummaryPage> {
  TrainingPlan? _plan;
  bool _loading = true;
  bool _failed = false;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_asked) {
      _asked = true;
      _load();
    }
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).programmes;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final plan = await repo.finished(now: widget.now);
      if (mounted) setState(() => _plan = plan);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final back = Align(
      alignment: Alignment.centerLeft,
      child: FFButton(
        key: const Key('summary-back'),
        label: context.tr('programmes.backToTraining'),
        onPressed: () => context.go(AppRoutes.memberTrainingPlan),
        variant: FFButtonVariant.ghost,
        size: FFButtonSize.sm,
        icon: Icons.arrow_back,
      ),
    );
    final plan = _plan;
    final List<Widget> body;
    if (_loading) {
      body = [FFSkeletonList(semanticLabel: context.tr('common.loading'))];
    } else if (_failed) {
      body = [
        FFErrorState(
          key: const Key('summary-error'),
          message: context.tr('programmes.loadFailed'),
          retryLabel: context.tr('programmes.retry'),
          onRetry: _load,
        ),
      ];
    } else if (plan == null) {
      body = [
        FFEmptyState(
          key: const Key('summary-none'),
          title: context.tr('programmes.notAvailable'),
        ),
      ];
    } else {
      final total = plan.sessions;
      final finished = total > 0 && plan.completed / total >= 0.5;
      body = [
        FFPageHeader(
          title: context
              .tr(finished ? 'programmes.finished' : 'programmes.ended')
              .replaceAll('{title}', plan.name),
        ),
        Column(
          key: const Key('summary-stats'),
          children: [
            for (final pair in [
              _tiles(context, plan).sublist(0, 2),
              _tiles(context, plan).sublist(2),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: pair[0]),
                      const SizedBox(width: FFTokens.spacingSm),
                      Expanded(child: pair[1]),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingLg),
        FFButton(
          key: const Key('summary-next'),
          fullWidth: true,
          label: context.tr('programmes.findNext'),
          onPressed: () => context.go(
            Uri(
              path: AppRoutes.memberProgrammes,
              queryParameters: {'goal': plan.goal},
            ).toString(),
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFButton(
          key: const Key('summary-training'),
          fullWidth: true,
          variant: FFButtonVariant.secondary,
          label: context.tr('programmes.backToTraining'),
          onPressed: () => context.go(AppRoutes.memberTrainingPlan),
        ),
      ];
    }
    return ListView(
      key: const Key('summary-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [back, ...body],
    );
  }
}

/// On the empty plan page: "See your summary" for a programme that ended in
/// the last 30 days. Nothing while programmes are off or none ended.
class ProgrammeSummaryCard extends StatefulWidget {
  const ProgrammeSummaryCard({super.key, this.now});

  final DateTime? now;

  @override
  State<ProgrammeSummaryCard> createState() => _ProgrammeSummaryCardState();
}

class _ProgrammeSummaryCardState extends State<ProgrammeSummaryCard> {
  TrainingPlan? _plan;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    // No scope (a bare widget test): nothing to show.
    final repo = context
        .dependOnInheritedWidgetOfExactType<AppScope>()
        ?.programmes;
    if (repo == null) return;
    repo.finished(now: widget.now).then((p) {
      if (mounted && p != null) setState(() => _plan = p);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFActionTile(
        key: const Key('programme-summary-card'),
        icon: Icons.emoji_events_outlined,
        title: context.tr('programmes.seeSummary'),
        subtitle: plan.name,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(AppRoutes.memberProgrammeSummary),
      ),
    );
  }
}
