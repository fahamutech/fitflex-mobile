import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../screens/member/widgets/challenge_widgets.dart'
    show challengeAmount, challengeTargetText, challengeUnit;
import '../activity/challenge.dart';
import '../api_client.dart';
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

/// Challenges a trainer or gym created: create (or save as a draft), edit,
/// publish, pause, close, cancel, archive, and see who joined.
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
      builder: (_) => _ChallengeSheet(
        now: widget.now ?? DateTime.now(),
        onSave: (body) => AppScope.of(
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
        now: widget.now,
        onChanged: _load,
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
                        challengeStatusLabel(context, c),
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
    required this.onChanged,
    this.now,
  });

  final Challenge challenge;
  final String scope;
  final String? gymId;
  final DateTime? now;

  /// Reloads the list behind this page after the challenge changes.
  final Future<void> Function() onChanged;

  @override
  State<_ParticipantsPage> createState() => _ParticipantsPageState();
}

class _ParticipantsPageState extends State<_ParticipantsPage> {
  List<Map<String, dynamic>>? _rows;
  ChallengeLeaderboard? _board;
  late Challenge _c = widget.challenge;
  bool _busy = false;

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

  /// The server's answer, keeping what a short answer leaves out.
  void _adopt(Map<String, dynamic> res) {
    final json = res['challenge'];
    if (json is! Map) return;
    final next = Challenge.tryParse(Map<String, dynamic>.from(json));
    if (next == null) return;
    setState(
      () => _c = json.containsKey('participantCount')
          ? next
          : next.copyWith(participantCount: _c.participantCount),
    );
  }

  /// Runs a creator action (cancel, close, archive, publish, pause, resume),
  /// asking first unless [body] is null. [leave] closes the page after.
  Future<void> _act(
    String action, {
    String? title,
    String? body,
    String? confirm,
    bool leave = false,
  }) async {
    if (body != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title ?? _c.name),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('workout.keepGoing')),
            ),
            FilledButton(
              key: Key('challenge-$action-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirm ?? title ?? ''),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final generic = context.tr('owner.errorGeneric');
    final tr = context.tr;
    setState(() => _busy = true);
    try {
      final res = await AppScope.of(
        context,
      ).api.challengeAction(widget.scope, _c.id, action, gymId: widget.gymId);
      await widget.onChanged();
      if (leave) {
        navigator.pop();
      } else if (mounted) {
        _adopt(res);
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(challengeErrorText(tr, e, generic))),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(generic)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    Map<String, dynamic>? saved;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChallengeSheet(
        now: widget.now ?? DateTime.now(),
        existing: _c,
        onSave: (body) async => saved = await AppScope.of(
          context,
        ).api.updateChallenge(widget.scope, _c.id, body, gymId: widget.gymId),
      ),
    );
    if (ok != true || !mounted) return;
    if (saved != null) _adopt(saved!);
    await widget.onChanged();
  }

  void _menu(String v) {
    final tr = context.tr;
    switch (v) {
      case 'edit':
        _edit();
      case 'publish':
        _act(
          'publish',
          title: tr('challenge.publish'),
          body: tr('challenge.publishBody'),
        );
      case 'pause':
        _act(
          'pause',
          title: tr('challenge.pause'),
          body: tr('challenge.pauseBody'),
        );
      case 'resume':
        _act('resume');
      case 'close':
        _act(
          'close',
          title: tr('challenge.closeNow'),
          body: tr('challenge.closeBody'),
        );
      case 'cancel':
        _act(
          'cancel',
          title: tr('challenge.cancelTitle'),
          body: tr('challenge.cancelBody'),
          confirm: tr('challenge.cancel'),
          leave: true,
        );
      case 'discard':
        _act(
          'cancel',
          title: tr('challenge.deleteDraft'),
          body: _c.name,
          leave: true,
        );
      case 'archive':
        _act(
          'archive',
          title: tr('challenge.archive'),
          body: tr('challenge.archiveBody'),
          leave: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _c;
    final rows = _rows;
    final over =
        (c.phase == ChallengePhase.ended && c.status != 'archived') ||
        c.status == 'cancelled';
    final actions = <(String, String)>[
      if (c.isLive || c.isDraft) ('edit', 'challenge.edit'),
      if (c.isDraft) ('publish', 'challenge.publish'),
      if (c.isLive && !c.isPaused) ('pause', 'challenge.pause'),
      if (c.isPaused) ('resume', 'challenge.resume'),
      if (c.isLive && c.phase == ChallengePhase.active)
        ('close', 'challenge.closeNow'),
      if (c.isLive) ('cancel', 'challenge.cancel'),
      if (c.isDraft) ('discard', 'challenge.deleteDraft'),
      if (over) ('archive', 'challenge.archive'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          if (actions.isNotEmpty)
            PopupMenuButton<String>(
              key: const Key('challenge-actions'),
              tooltip: context.tr('challenge.actions'),
              enabled: !_busy,
              onSelected: _menu,
              itemBuilder: (_) => [
                for (final (value, label) in actions)
                  PopupMenuItem(
                    key: Key('challenge-$value'),
                    value: value,
                    child: Text(context.tr(label)),
                  ),
              ],
            ),
        ],
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Row(
                  children: [
                    FFPill(
                      key: const Key('challenge-status'),
                      label: challengeStatusLabel(context, c),
                    ),
                  ],
                ),
                const SizedBox(height: FFTokens.spacingSm),
                if (c.isDraft || c.isPaused) ...[
                  Text(
                    context.tr(
                      c.isDraft
                          ? 'challenge.draftNote'
                          : 'challenge.pausedNote',
                    ),
                    key: const Key('challenge-state-note'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                ],
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

/// The label for where a challenge stands, as its maker sees it.
String challengeStatusLabel(BuildContext context, Challenge c) => context.tr(
  c.isPaused
      ? 'challenge.status.paused'
      : c.status == 'archived' || c.status == 'closed'
      ? 'challenge.status.${c.status}'
      : 'challenge.phase.${c.phase.name}',
);

/// The server's reason in words, where there is a line for it.
String challengeErrorText(
  String Function(String) tr,
  ApiException e,
  String fallback,
) {
  final key = 'challenge.err.${e.code}';
  final text = tr(key);
  return text == key ? fallback : text;
}

/// Create a challenge, or edit [existing].
class _ChallengeSheet extends StatefulWidget {
  const _ChallengeSheet({
    required this.now,
    required this.onSave,
    this.existing,
  });

  final DateTime now;
  final Challenge? existing;
  final Future<Object?> Function(Map<String, dynamic> body) onSave;

  @override
  State<_ChallengeSheet> createState() => _ChallengeSheetState();
}

class _ChallengeSheetState extends State<_ChallengeSheet> {
  final _form = GlobalKey<FormState>();
  Challenge? get _existing => widget.existing;
  DateTime get _today =>
      DateTime(widget.now.year, widget.now.month, widget.now.day);

  /// A draft hasn't gone out to anyone, so nothing about it is locked.
  bool get _started =>
      _existing != null &&
      !_existing!.isDraft &&
      _existing!.phase != ChallengePhase.upcoming;
  bool get _locked =>
      _existing != null &&
      !_existing!.isDraft &&
      (_started || _existing!.participantCount > 0);

  late final _name = TextEditingController(text: _existing?.name);
  late final _description = TextEditingController(text: _existing?.description);
  late final _rewardsBefore = (_existing?.rewards ?? const []).join(', ');
  late final _rewards = TextEditingController(text: _rewardsBefore);
  late final _target = TextEditingController(
    text: '${_existing?.target ?? _defaultTargets[ChallengeType.steps]}',
  );
  late ChallengeType _type = _existing?.type ?? ChallengeType.steps;
  late DateTimeRange _range = DateTimeRange(
    start: _existing?.startDate ?? _today,
    end: _existing?.endDate ?? _today.add(const Duration(days: 13)),
  );
  late bool _public = _existing?.visibility == 'public';
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
    final today = _today;
    final last = today.add(const Duration(days: 365));
    if (_started) {
      // Under way: only the end can move.
      final end = await showDatePicker(
        context: context,
        firstDate: today,
        lastDate: last,
        initialDate: _range.end.isBefore(today) ? today : _range.end,
      );
      if (end != null) {
        setState(() => _range = DateTimeRange(start: _range.start, end: end));
      }
      return;
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: _range.start.isBefore(today) ? _range.start : today,
      lastDate: last,
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _save({bool draft = false}) async {
    if (!_form.currentState!.validate()) return;
    final editing = _existing != null;
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
    final failed = context.tr(
      editing ? 'challenge.saveFailed' : 'challenge.createFailed',
    );
    final tr = context.tr;
    setState(() {
      _busy = true;
      _error = null;
    });
    final description = _description.text.trim();
    try {
      await widget.onSave({
        'name': _name.text.trim(),
        if (description.isNotEmpty)
          'description': description
        else if (editing)
          'description': null,
        // What is locked is left out, so the server keeps it as it is.
        if (!_locked) 'type': _type.wire,
        'target': num.parse(_target.text.trim()),
        if (!_started) 'startDate': _date(_range.start),
        'endDate': _date(_range.end),
        // Untouched rewards are left alone, so ones already earned stay put.
        if (!editing || _rewards.text.trim() != _rewardsBefore)
          'rewards': [
            for (final r in _rewards.text.split(','))
              if (r.trim().isNotEmpty) r.trim(),
          ],
        'visibility': _public ? 'public' : 'audience',
        if (!editing) 'mode': _teams ? 'teams' : 'individual',
        if (!editing && _teams)
          'teams': [
            for (final t in _teamNames.text.split(','))
              if (t.trim().isNotEmpty) t.trim(),
          ],
        if (draft) 'draft': true,
      });
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = challengeErrorText(tr, e, failed);
        });
      }
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
              context.tr(
                _existing == null ? 'challenge.new' : 'challenge.editTitle',
              ),
              style: theme.textTheme.titleLarge,
            ),
            if (_locked) ...[
              const SizedBox(height: FFTokens.spacingXs),
              Text(
                context.tr('challenge.lockedNote'),
                key: const Key('challenge-locked-note'),
                style: theme.textTheme.bodySmall,
              ),
            ],
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
                    onSelected: _locked
                        ? null
                        : (_) => setState(() {
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
            // Teams are set up when the challenge is created.
            if (_existing == null)
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
            if (_existing == null) ...[
              OutlinedButton(
                key: const Key('challenge-save-draft'),
                onPressed: _busy ? null : () => _save(draft: true),
                child: Text(context.tr('challenge.saveDraft')),
              ),
              const SizedBox(height: FFTokens.spacingXs),
              FilledButton(
                key: const Key('challenge-create'),
                onPressed: _busy ? null : _save,
                child: Text(context.tr('challenge.create')),
              ),
            ] else
              FilledButton(
                key: const Key('challenge-save'),
                onPressed: _busy ? null : _save,
                child: Text(context.tr('challenge.saveChanges')),
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
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
