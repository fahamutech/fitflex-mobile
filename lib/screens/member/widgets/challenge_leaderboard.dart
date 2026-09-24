import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/challenge.dart';
import '../../../shared/activity/gym_sharing.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'challenge_widgets.dart' show challengeAmount;

/// What the member chose when joining.
typedef JoinChoice = ({String? teamId, String? gymId, bool leaderboardOptIn});

/// Join a challenge: pick a team or gym when the challenge has them, and
/// choose whether to appear on the leaderboard (off by default).
Future<JoinChoice?> showJoinChallengeSheet(
  BuildContext context, {
  required Challenge challenge,
  required List<GymSharing> myGyms,
}) => showModalBottomSheet<JoinChoice>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _JoinSheet(challenge: challenge, myGyms: myGyms),
);

class _JoinSheet extends StatefulWidget {
  const _JoinSheet({required this.challenge, required this.myGyms});

  final Challenge challenge;
  final List<GymSharing> myGyms;

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  String? _teamId;
  String? _gymId;
  bool _optIn = false;

  @override
  void initState() {
    super.initState();
    // A single home gym is the obvious team in a gym-vs-gym challenge.
    final home = widget.myGyms.where((g) => g.reasons.contains('member'));
    if (home.length == 1) _gymId = home.first.gym.id;
  }

  bool get _ready => switch (widget.challenge.mode) {
    ChallengeMode.teams => _teamId != null,
    ChallengeMode.gymVsGym => _gymId != null,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.challenge;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('leaderboard.joinTitle').replaceAll('{name}', c.name),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: FFTokens.spacingMd),
            if (c.mode == ChallengeMode.teams) ...[
              Text(
                context.tr('leaderboard.pickTeam'),
                style: theme.textTheme.labelLarge,
              ),
              Wrap(
                spacing: FFTokens.spacingSm,
                children: [
                  for (final t in c.teams)
                    ChoiceChip(
                      key: Key('join-team-${t.id}'),
                      label: Text(t.name),
                      selected: _teamId == t.id,
                      onSelected: (_) => setState(() => _teamId = t.id),
                    ),
                ],
              ),
              const SizedBox(height: FFTokens.spacingMd),
            ],
            if (c.mode == ChallengeMode.gymVsGym) ...[
              Text(
                context.tr('leaderboard.pickGym'),
                style: theme.textTheme.labelLarge,
              ),
              if (widget.myGyms.isEmpty)
                Text(
                  context.tr('leaderboard.noGyms'),
                  style: theme.textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: FFTokens.spacingSm,
                  children: [
                    for (final g in widget.myGyms)
                      ChoiceChip(
                        key: Key('join-gym-${g.gym.id}'),
                        label: Text(g.gym.name ?? ''),
                        selected: _gymId == g.gym.id,
                        onSelected: (_) => setState(() => _gymId = g.gym.id),
                      ),
                  ],
                ),
              const SizedBox(height: FFTokens.spacingMd),
            ],
            if (c.mode == ChallengeMode.department)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
                child: Text(
                  context.tr('leaderboard.departmentNote'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            SwitchListTile(
              key: const Key('join-leaderboard'),
              contentPadding: EdgeInsets.zero,
              value: _optIn,
              onChanged: (v) => setState(() => _optIn = v),
              title: Text(context.tr('leaderboard.optIn')),
              subtitle: Text(context.tr('leaderboard.optInHint')),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('join-confirm'),
                onPressed: _ready
                    ? () => Navigator.pop<JoinChoice>(context, (
                        teamId: _teamId,
                        gymId: _gymId,
                        leaderboardOptIn: _optIn,
                      ))
                    : null,
                child: Text(context.tr('challenge.join')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A joined challenge's leaderboard: your standing, the people who chose
/// to be listed, team standings, and the switch to appear or not.
class ChallengeLeaderboardSection extends StatefulWidget {
  const ChallengeLeaderboardSection({super.key, required this.challenge});

  final Challenge challenge;

  @override
  State<ChallengeLeaderboardSection> createState() =>
      _ChallengeLeaderboardSectionState();
}

class _ChallengeLeaderboardSectionState
    extends State<ChallengeLeaderboardSection> {
  ChallengeLeaderboard? _board;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_board == null) _load();
  }

  Future<void> _load() async {
    try {
      final res = await AppScope.of(
        context,
      ).api.challengeLeaderboard(widget.challenge.id);
      if (mounted) setState(() => _board = ChallengeLeaderboard.fromJson(res));
    } catch (_) {
      if (mounted) setState(() => _board = const ChallengeLeaderboard());
    }
  }

  Future<void> _setOptIn(bool on) async {
    final api = AppScope.of(context).api;
    final data = MemberDataScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('challenge.failed');
    setState(() => _busy = true);
    try {
      await api.setLeaderboardOptIn(widget.challenge.id, on);
      data.update(
        (d) => d.challenges = [
          for (final x in d.challenges)
            x.id == widget.challenge.id ? x.copyWith(leaderboardOptIn: on) : x,
        ],
      );
      await _load();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.challenge;
    final b = _board;
    final you = b?.you;
    return Column(
      key: const Key('challenge-leaderboard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(context.tr('leaderboard.title')),
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const Key('leaderboard-opt-in'),
                contentPadding: EdgeInsets.zero,
                value: c.leaderboardOptIn,
                onChanged: _busy ? null : _setOptIn,
                title: Text(context.tr('leaderboard.optIn')),
                subtitle: Text(context.tr('leaderboard.optInHint')),
              ),
              if (b == null)
                const Padding(
                  padding: EdgeInsets.all(FFTokens.spacingMd),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (you != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                    child: Text(
                      context
                          .tr(
                            you.optedIn
                                ? 'leaderboard.youAre'
                                : 'leaderboard.youWouldBe',
                          )
                          .replaceAll('{rank}', '${you.rank}')
                          .replaceAll('{of}', '${you.of}'),
                      key: const Key('leaderboard-you'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (c.myTeamName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                    child: Text(
                      context
                          .tr('leaderboard.yourTeam')
                          .replaceAll('{team}', c.myTeamName!),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (b.individuals.isEmpty)
                  Text(
                    context.tr('leaderboard.nobodyListed'),
                    style: theme.textTheme.bodySmall,
                  )
                else
                  for (final e in b.individuals)
                    _Row(
                      key: Key('leaderboard-row-${e.rank}'),
                      rank: e.rank,
                      label: e.isYou
                          ? '${e.name} (${context.tr('leaderboard.you')})'
                          : e.name,
                      value: challengeAmount(context, c.type, e.progress),
                      fraction: e.fraction,
                      highlight: e.isYou,
                    ),
              ],
            ],
          ),
        ),
        if (b != null && c.mode.hasTeams) ...[
          FFSectionTitle(context.tr('leaderboard.teams')),
          FFCard(
            key: const Key('leaderboard-teams'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (b.teams.isEmpty)
                  Text(
                    context
                        .tr('leaderboard.noTeamsYet')
                        .replaceAll('{n}', '${b.minTeamSize}'),
                    style: theme.textTheme.bodySmall,
                  ),
                for (final t in b.teams)
                  _Row(
                    key: Key('team-row-${t.rank}'),
                    rank: t.rank,
                    label:
                        '${t.name} · ${context.tr('leaderboard.members').replaceAll('{n}', '${t.members}')}',
                    value: '${(t.averageCompletion * 100).round()}%',
                    fraction: t.averageCompletion,
                    highlight: t.teamId == c.myTeamId,
                  ),
                if (b.hiddenTeams > 0 && b.teams.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                    child: Text(
                      context
                          .tr(
                            b.hiddenTeams == 1
                                ? 'leaderboard.hiddenTeamsOne'
                                : 'leaderboard.hiddenTeams',
                          )
                          .replaceAll('{count}', '${b.hiddenTeams}')
                          .replaceAll('{n}', '${b.minTeamSize}'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                  child: Text(
                    context.tr('leaderboard.teamRule'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Text(
            context.tr('leaderboard.fairPlay'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.rank,
    required this.label,
    required this.value,
    required this.fraction,
    this.highlight = false,
  });

  final int rank;
  final String label;
  final String value;
  final double fraction;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: highlight ? theme.colorScheme.primary : null,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: highlight ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    Text(value, style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: FFTokens.spacing2xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.0, 1.0),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
