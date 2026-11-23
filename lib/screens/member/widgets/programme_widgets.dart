import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/activity/programme.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';

// Programmes P1 (M1): words and small pieces shared by the catalogue, the
// detail page and the ways in (the Training tile, the empty plan page).

String programmeGoal(BuildContext context, String id) =>
    context.tr('onboarding.goal_$id');
String programmeLevel(BuildContext context, String id) =>
    context.tr('onboarding.level_$id');
String programmeWhere(BuildContext context, String id) =>
    context.tr('training.env.$id');
String programmeEquipment(BuildContext context, String id) =>
    context.tr('training.equipment.$id');
String programmeDays(BuildContext context, int n) =>
    context.tr('programmes.days').replaceAll('{n}', '$n');

/// "21 days · Beginner · Home".
String programmeMeta(BuildContext context, Programme p) => [
  programmeDays(context, p.lengthDays),
  programmeLevel(context, p.level),
  programmeWhere(context, p.environment),
].join(' · ');

String programmeRoute(String id) => AppRoutes.memberProgramme.replaceFirst(
  ':programmeId',
  Uri.encodeComponent(id),
);

IconData programmeDayIcon(String type) => switch (type) {
  'gym' => Icons.fitness_center,
  'home' => Icons.home_outlined,
  _ => Icons.bedtime_outlined,
};

/// Builds [builder] only once the server has answered the catalogue: with
/// programmes off (or any error) it builds nothing, so no way in is shown.
class ProgrammesAvailable extends StatefulWidget {
  const ProgrammesAvailable({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<ProgrammesAvailable> createState() => _ProgrammesAvailableState();
}

class _ProgrammesAvailableState extends State<ProgrammesAvailable> {
  // One answer per repository: every way in on screen asks once.
  static final Expando<bool> _known = Expando();
  bool _available = false;
  ProgrammeRepository? _repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No scope (a bare widget test): stay hidden.
    final repo = context
        .dependOnInheritedWidgetOfExactType<AppScope>()
        ?.programmes;
    if (repo == null || identical(repo, _repo)) return;
    _repo = repo;
    _available = _known[repo] ?? false;
    if (_known[repo] == null) _check(repo);
  }

  Future<void> _check(ProgrammeRepository repo) async {
    try {
      await repo.catalogue();
      _known[repo] = true;
      if (mounted && identical(repo, _repo)) setState(() => _available = true);
    } catch (_) {
      // Off, or not reachable just now: stay hidden; asked again next time.
    }
  }

  @override
  Widget build(BuildContext context) =>
      _available ? widget.builder(context) : const SizedBox.shrink();
}

/// The Training tab's way in: "Programmes · Free day-by-day plans…".
class ProgrammesTile extends StatelessWidget {
  const ProgrammesTile({super.key});

  @override
  Widget build(BuildContext context) => ProgrammesAvailable(
    builder: (context) => Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFActionTile(
        key: const Key('programmes-tile'),
        icon: Icons.event_note_outlined,
        title: context.tr('programmes.title'),
        subtitle: context.tr('programmes.tileSubtitle'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(AppRoutes.memberProgrammes),
      ),
    ),
  );
}

/// One small dot per day, coloured by type; at most 30, then "+n". The same
/// meaning is given in words for screen readers.
class ProgrammeDayStrip extends StatelessWidget {
  const ProgrammeDayStrip({super.key, required this.programme});

  final Programme programme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final types = programme.types;
    const max = 30;
    Color colour(String t) => switch (t) {
      'gym' => scheme.primary,
      'home' => scheme.onSurface,
      _ => scheme.outlineVariant,
    };
    return Semantics(
      label: context
          .tr('programmes.dayMix')
          .replaceAll('{gym}', '${programme.count('gym')}')
          .replaceAll('{home}', '${programme.count('home')}')
          .replaceAll('{rest}', '${programme.count('rest')}'),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 3,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final t in types.take(max))
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colour(t),
                  shape: BoxShape.circle,
                ),
              ),
            if (types.length > max)
              Text(
                context
                    .tr('programmes.more')
                    .replaceAll('{n}', '${types.length - max}'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
    );
  }
}
