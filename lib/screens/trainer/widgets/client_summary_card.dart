import 'package:flutter/material.dart';

import '../../../shared/activity/goal.dart';
import '../../../shared/activity/trainer_connection.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../member/widgets/activity_widgets.dart' show formatSteps, formatKm;

/// One prompt as a sentence, e.g. "Missed 2 planned workouts".
String promptText(BuildContext context, ClientPrompt p) {
  switch (p.code) {
    case 'missed_workouts':
      return context
          .tr(p.value == 1 ? 'digest.missedOne' : 'digest.missed')
          .replaceAll('{n}', '${p.value}');
    case 'inactive':
      return p.value == null
          ? context.tr('digest.noWorkouts')
          : context.tr('digest.inactive').replaceAll('{n}', '${p.value}');
    case 'nothing_planned':
      return context.tr('digest.nothingPlanned');
    case 'streak_ended':
      return context.tr('digest.streakEnded').replaceAll('{n}', '${p.value}');
    case 'goal_met':
      return context.tr('digest.goalMet');
    default:
      return p.code;
  }
}

/// "4 workouts · 42,320 steps · 184 active min" — only what's shared.
List<String> weekFacts(BuildContext context, ClientSummary s) => [
  if (s.workouts != null)
    context
        .tr(s.workouts == 1 ? 'digest.workout' : 'digest.workouts')
        .replaceAll('{n}', '${s.workouts}'),
  if (s.steps != null)
    '${formatSteps(s.steps!)} ${context.tr('activity.steps').toLowerCase()}',
  if (s.activeMinutes != null)
    context
        .tr('digest.activeMin')
        .replaceAll('{n}', formatSteps(s.activeMinutes!)),
  if (s.distanceKm != null) formatKm(s.distanceKm!),
];

String _goalLine(BuildContext context, ClientGoal g) {
  String n(num v) =>
      v == v.roundToDouble() ? formatSteps(v.round()) : v.toStringAsFixed(1);
  final unit = switch (g.type) {
    GoalType.workouts => context.tr('activity.workoutCount').toLowerCase(),
    GoalType.steps => context.tr('activity.steps').toLowerCase(),
    GoalType.activeMinutes =>
      context.tr('activity.activeMinutes').toLowerCase(),
    GoalType.distanceKm => 'km',
  };
  final period = context.tr('goal.period.${g.period.wire}');
  return '${n(g.current)} / ${n(g.target)} $unit $period';
}

/// A client at a glance: this week, goal, streak, and what to act on.
/// Built entirely from the server's summary, so it only ever shows what
/// the client shares.
class ClientSummaryCard extends StatelessWidget {
  const ClientSummaryCard({
    super.key,
    required this.name,
    required this.summary,
    this.photoUrl,
    this.onTap,
  });

  final String name;
  final String? photoUrl;
  final ClientSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final facts = weekFacts(context, s);
    return FFCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FFAvatar(name: name, src: photoUrl),
                const SizedBox(width: FFTokens.spacingMd),
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right),
              ],
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context.tr('digest.thisWeek').toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              facts.isEmpty
                  ? context.tr('digest.noActivityShared')
                  // Keep each fact on one line; wrap only between facts.
                  : facts.map((f) => f.replaceAll(' ', '\u00A0')).join(' · '),
              key: const Key('summary-week'),
              style: facts.isEmpty
                  ? theme.textTheme.bodySmall
                  : theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
            ),
            if (s.goal != null || s.streak != null) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Wrap(
                spacing: FFTokens.spacingMd,
                runSpacing: FFTokens.spacingXs,
                children: [
                  if (s.goal case final g?)
                    _Fact(
                      key: const Key('summary-goal'),
                      icon: g.completed ? Icons.flag : Icons.flag_outlined,
                      color: g.completed ? theme.colorScheme.primary : null,
                      text:
                          '${context.tr('digest.goal')}: ${_goalLine(context, g)}',
                    ),
                  if (s.streak case final n?)
                    _Fact(
                      key: const Key('summary-streak'),
                      icon: Icons.local_fire_department,
                      color: n > 0 ? FFTokens.warning500 : null,
                      text: context
                          .tr('streak.activity.current')
                          .replaceAll('{n}', '$n'),
                    ),
                ],
              ),
            ],
            if (s.prompts.isNotEmpty) ...[
              const SizedBox(height: FFTokens.spacingSm),
              for (final p in s.prompts)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                  child: _Fact(
                    key: Key('summary-prompt-${p.code}'),
                    icon: p.positive
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: p.positive
                        ? theme.colorScheme.primary
                        : FFTokens.warning500,
                    text: promptText(context, p),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({super.key, required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: FFTokens.iconSm, color: color),
      const SizedBox(width: FFTokens.spacingXs),
      Flexible(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    ],
  );
}
