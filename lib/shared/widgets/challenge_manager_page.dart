import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../screens/member/widgets/challenge_widgets.dart'
    show challengeAmount, challengeTargetText, challengeUnit;
import '../activity/challenge.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';

/// Opens the challenge manager for a trainer (`scope: 'trainer'`) or a gym
/// (`scope: 'owner'`, with [gymId]).
Future<void> openChallengeManager(
  BuildContext context, {
  required String scope,
  String? gymId,
}) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => ChallengeManagerPage(scope: scope, gymId: gymId),
  ),
);

/// Challenges a trainer or gym created: create, cancel, and see who joined.
class ChallengeManagerPage extends StatefulWidget {
  const ChallengeManagerPage({
    super.key,
    required this.scope,
    this.gymId,
    this.now,
  });

  final String scope;
  final String? gymId;

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<ChallengeManagerPage> createState() => _ChallengeManagerPageState();
}

class _ChallengeManagerPageState extends State<ChallengeManagerPage> {
  List<Challenge>? _items;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null && !_failed) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AppScope.of(
        context,
      ).api.creatorChallenges(widget.scope, gymId: widget.gymId);
      if (!mounted) return;
      setState(
        () => _items = [
          for (final r in rows.whereType<Map>())
            ?Challenge.tryParse(Map<String, dynamic>.from(r)),
        ],
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateChallengeSheet(
        now: widget.now ?? DateTime.now(),
        onCreate: (body) => AppScope.of(
          context,
        ).api.createChallenge(widget.scope, body, gymId: widget.gymId),
      ),
    );
    if (created == true && mounted) await _load();
  }

  Future<void> _open(Challenge c) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _ParticipantsPage(
        challenge: c,
        scope: widget.scope,
        gymId: widget.gymId,
        onCancelled: _load,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('challenge.manageTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('challenge-new'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(context.tr('challenge.new')),
      ),
      body: _failed
          ? Center(child: FFEmptyState(title: context.tr('owner.errorGeneric')))
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                FFTokens.spacingLg,
                FFTokens.spacingLg,
                FFTokens.spacingLg,
                96,
              ),
              children: [
                Text(
                  context.tr('challenge.manageBody.${widget.scope}'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                if (items.isEmpty)
                  FFEmptyState(title: context.tr('challenge.noneCreated'))
                else
                  for (final c in items)
                    FFActionTile(
                      key: Key('managed-challenge-${c.id}'),
                      icon: Icons.emoji_events_outlined,
                      title: c.name,
                      subtitle: [
                        challengeTargetText(context, c.type, c.target),
                        '${DateFormat('d MMM').format(c.startDate)} – ${DateFormat('d MMM').format(c.endDate)}',
                        context.tr('challenge.phase.${c.phase.name}'),
                        context
                            .tr('challenge.participants')
                            .replaceAll('{n}', '${c.participantCount}'),
                      ].join(' · '),
                      onTap: () => _open(c),
                    ),
              ],
            ),
    );
  }
}

class _ParticipantsPage extends StatefulWidget {
  const _ParticipantsPage({
    required this.challenge,
    required this.scope,
    required this.gymId,
    required this.onCancelled,
  });

  final Challenge challenge;
  final String scope;
  final String? gymId;
  final Future<void> Function() onCancelled;

  @override
  State<_ParticipantsPage> createState() => _ParticipantsPageState();
}

class _ParticipantsPageState extends State<_ParticipantsPage> {
  List<Map<String, dynamic>>? _rows;
  ChallengeLeaderboard? _board;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rows == null) _load();
  }

  Future<void> _load() async {
    try {
      final res = await AppScope.of(context).api.challengeParticipants(
        widget.scope,
        widget.challenge.id,
        gymId: widget.gymId,
      );
      if (!mounted) return;
      setState(
        () => _rows = [
          for (final p
              in (res['participants'] as List? ?? const []).whereType<Map>())
            Map<String, dynamic>.from(p),
        ],
      );
    } catch (_) {
      if (mounted) setState(() => _rows = const []);
    }
    if (widget.challenge.mode.hasTeams && mounted) {
      try {
        final lb = await AppScope.of(context).api.creatorLeaderboard(
          widget.scope,
          widget.challenge.id,
          gymId: widget.gymId,
        );
        if (mounted) setState(() => _board = ChallengeLeaderboard.fromJson(lb));
      } catch (_) {
        // Standings are extra; the participant list stands on its own.
      }
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('challenge.cancelTitle')),
        content: Text(ctx.tr('challenge.cancelBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('workout.keepGoing')),
          ),
          FilledButton(
            key: const Key('challenge-cancel-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('challenge.cancel')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    try {
      await AppScope.of(context).api.cancelChallenge(
        widget.scope,
        widget.challenge.id,
        gymId: widget.gymId,
      );
      await widget.onCancelled();
      navigator.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('owner.errorGeneric'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.challenge;
    final rows = _rows;
    final open =
        c.phase == ChallengePhase.active || c.phase == ChallengePhase.upcoming;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          if (open)
            TextButton(
              key: const Key('challenge-cancel'),
              onPressed: _cancel,
              child: Text(context.tr('challenge.cancel')),
            ),
        ],
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Text(
                  context.tr('challenge.participantsNote'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                if (_board case final b? when c.mode.hasTeams)
                  FFCard(
                    key: const Key('creator-team-standings'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('leaderboard.teams'),
                          style: theme.textTheme.titleSmall,
                        ),
                        if (b.teams.isEmpty)
                          Text(
                            context
                                .tr('leaderboard.noTeamsYet')
                                .replaceAll('{n}', '${b.minTeamSize}'),
                            style: theme.textTheme.bodySmall,
                          ),
                        for (final t in b.teams)
                          Text(
                            '${t.rank}. ${t.name} · ${(t.averageCompletion * 100).round()}% · ${context.tr('leaderboard.members').replaceAll('{n}', '${t.members}')}',
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                if (rows.isEmpty)
                  FFEmptyState(title: context.tr('challenge.noParticipants'))
                else
                  for (final p in rows)
                    FFCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (p['member'] as Map?)?['displayName']
                                          as String? ??
                                      '',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (p['completed'] == true)
                                FFPill(
                                  label: context.tr('challenge.completed'),
                                  filled: true,
                                ),
                            ],
                          ),
                          if (p['progress'] case final num v) ...[
                            const SizedBox(height: FFTokens.spacingXs),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                FFTokens.radiusFull,
                              ),
                              child: LinearProgressIndicator(
                                value: c.target <= 0
                                    ? 0
                                    : (v / c.target).clamp(0.0, 1.0).toDouble(),
                                minHeight: 6,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                            Text(
                              '${challengeAmount(context, c.type, v)} / ${challengeAmount(context, c.type, c.target)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ] else
                            Text(
                              context.tr('challenge.progressNotShared'),
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }
}

const _defaultTargets = {
  ChallengeType.steps: 50000,
  ChallengeType.distanceKm: 20,
  ChallengeType.workouts: 8,
  ChallengeType.activeMinutes: 300,
  ChallengeType.consistency: 10,
  ChallengeType.gymAttendance: 8,
};

class _CreateChallengeSheet extends StatefulWidget {
  const _CreateChallengeSheet({required this.now, required this.onCreate});

  final DateTime now;
  final Future<Object?> Function(Map<String, dynamic> body) onCreate;

  @override
  State<_CreateChallengeSheet> createState() => _CreateChallengeSheetState();
}

class _CreateChallengeSheetState extends State<_CreateChallengeSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _rewards = TextEditingController();
  late final _target = TextEditingController(
    text: '${_defaultTargets[ChallengeType.steps]}',
  );
  ChallengeType _type = ChallengeType.steps;
  late DateTimeRange _range = DateTimeRange(
    start: DateTime(widget.now.year, widget.now.month, widget.now.day),
    end: DateTime(widget.now.year, widget.now.month, widget.now.day + 13),
  );
  bool _public = false;
  bool _teams = false;
  final _teamNames = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _description, _rewards, _target, _teamNames]) {
      c.dispose();
    }
    super.dispose();
  }

  String _date(DateTime d) => formatChallengeDate(d);

  Future<void> _pickDates() async {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_teams) {
      final names = [
        for (final t in _teamNames.text.split(','))
          if (t.trim().isNotEmpty) t.trim().toLowerCase(),
      ];
      if (names.length < 2 || names.toSet().length != names.length) {
        setState(() => _error = context.tr('leaderboard.teamsInvalid'));
        return;
      }
    }
    final days = _range.end.difference(_range.start).inDays + 1;
    if (days > 92) {
      setState(() => _error = context.tr('challenge.tooLong'));
      return;
    }
    final navigator = Navigator.of(context);
    final failed = context.tr('challenge.createFailed');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCreate({
        'name': _name.text.trim(),
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
        'type': _type.wire,
        'target': num.parse(_target.text.trim()),
        'startDate': _date(_range.start),
        'endDate': _date(_range.end),
        'rewards': [
          for (final r in _rewards.text.split(','))
            if (r.trim().isNotEmpty) r.trim(),
        ],
        'visibility': _public ? 'public' : 'audience',
        'mode': _teams ? 'teams' : 'individual',
        if (_teams)
          'teams': [
            for (final t in _teamNames.text.split(','))
              if (t.trim().isNotEmpty) t.trim(),
          ],
      });
      navigator.pop(true);
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
    final fmt = DateFormat('d MMM');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              context.tr('challenge.new'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: FFTokens.spacingMd),
            TextFormField(
              key: const Key('challenge-name'),
              controller: _name,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: context.tr('challenge.name'),
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? context.tr('plans.required')
                  : null,
            ),
            TextFormField(
              key: const Key('challenge-description'),
              controller: _description,
              maxLength: 500,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: context.tr('plans.description'),
                border: const OutlineInputBorder(),
              ),
            ),
            Text(
              context.tr('challenge.type'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final t in ChallengeType.values)
                  ChoiceChip(
                    key: Key('challenge-type-${t.wire}'),
                    label: Text(context.tr('challenge.type.${t.wire}')),
                    selected: _type == t,
                    onSelected: (_) => setState(() {
                      _type = t;
                      _target.text = '${_defaultTargets[t]}';
                    }),
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingMd),
            TextFormField(
              key: const Key('challenge-target'),
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: context.tr('challenge.goal'),
                suffixText: challengeUnit(context, _type),
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final n = num.tryParse(v ?? '');
                return n == null || n <= 0
                    ? context.tr('plans.invalidNumber')
                    : null;
              },
            ),
            const SizedBox(height: FFTokens.spacingSm),
            OutlinedButton.icon(
              key: const Key('challenge-dates'),
              onPressed: _pickDates,
              icon: const Icon(Icons.date_range),
              label: Text(
                '${fmt.format(_range.start)} – ${fmt.format(_range.end)}',
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            TextFormField(
              key: const Key('challenge-rewards'),
              controller: _rewards,
              decoration: InputDecoration(
                labelText: context.tr('challenge.rewardsField'),
                helperText: context.tr('challenge.rewardsHelp'),
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              key: const Key('challenge-teams'),
              contentPadding: EdgeInsets.zero,
              value: _teams,
              onChanged: (v) => setState(() => _teams = v),
              title: Text(context.tr('leaderboard.teamChallenge')),
              subtitle: Text(context.tr('leaderboard.teamChallengeHint')),
            ),
            if (_teams)
              TextFormField(
                key: const Key('challenge-team-names'),
                controller: _teamNames,
                decoration: InputDecoration(
                  labelText: context.tr('leaderboard.teamNames'),
                  helperText: context.tr('leaderboard.teamNamesHelp'),
                  border: const OutlineInputBorder(),
                ),
              ),
            SwitchListTile(
              key: const Key('challenge-public'),
              contentPadding: EdgeInsets.zero,
              value: _public,
              onChanged: (v) => setState(() => _public = v),
              title: Text(context.tr('challenge.public')),
              subtitle: Text(context.tr('challenge.publicHint')),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: FFTokens.spacingSm),
            FilledButton(
              key: const Key('challenge-create'),
              onPressed: _busy ? null : _save,
              child: Text(context.tr('challenge.create')),
            ),
          ],
        ),
      ),
    );
  }
}

String formatChallengeDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Creator view of one member: their progress on your challenges (only
/// present when the member shares challenge data with you).
class SharedChallengesList extends StatelessWidget {
  const SharedChallengesList({super.key, required this.items});

  final List<SharedChallengeProgress> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text(
        context.tr('challenge.noneJoinedYours'),
        style: theme.textTheme.bodySmall,
      );
    }
    return Column(
      key: const Key('shared-challenges'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in items)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(c.name, style: theme.textTheme.bodyMedium),
                    ),
                    Text(
                      c.completed
                          ? context.tr('challenge.completed')
                          : '${challengeAmount(context, c.type, c.progress)} / ${challengeAmount(context, c.type, c.target)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FFTokens.spacing2xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                  child: LinearProgressIndicator(
                    value: c.target <= 0
                        ? 0
                        : (c.progress / c.target).clamp(0.0, 1.0).toDouble(),
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
