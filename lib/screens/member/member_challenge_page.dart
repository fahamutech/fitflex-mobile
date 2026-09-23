import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/challenge.dart';
import '../../shared/activity/gym_sharing.dart';
import '../../shared/activity/trainer_connection.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/challenge_leaderboard.dart';
import 'widgets/challenge_widgets.dart';

/// One challenge: what it is, who runs it, how far along you are, rewards,
/// and join / leave. For a trainer's or gym's challenge it says plainly
/// whether they can see your progress.
class MemberChallengePage extends StatefulWidget {
  const MemberChallengePage({super.key, required this.challengeId, this.now});

  final String challengeId;

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<MemberChallengePage> createState() => _MemberChallengePageState();
}

class _MemberChallengePageState extends State<MemberChallengePage> {
  bool _busy = false;

  Future<void> _toggle(Challenge c) async {
    final api = AppScope.of(context).api;
    final data = MemberDataScope.of(context);
    final shell = context.findAncestorStateOfType<MemberShellState>();
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr(
      c.joined ? 'challenge.leftToast' : 'challenge.joinedToast',
    );
    final failed = context.tr('challenge.failed');
    JoinChoice? choice;
    if (!c.joined) {
      choice = await showJoinChallengeSheet(
        context,
        challenge: c,
        myGyms: data.gymSharing,
      );
      if (choice == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (c.joined) {
        await api.leaveChallenge(c.id);
      } else {
        await api.joinChallenge(
          c.id,
          teamId: choice!.teamId,
          gymId: choice.gymId,
          leaderboardOptIn: choice.leaderboardOptIn,
        );
      }
      if (shell != null) {
        await shell.refreshChallenges();
      } else {
        // Keep the screen right even without a shell (tests, previews).
        data.update(
          (d) => d.challenges = [
            for (final x in d.challenges)
              x.id == c.id
                  ? x.copyWith(
                      joined: !c.joined,
                      leaderboardOptIn: choice?.leaderboardOptIn ?? false,
                      participantCount:
                          x.participantCount + (c.joined ? -1 : 1),
                    )
                  : x,
          ],
        );
      }
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Null for FitFlex/corporate (who never see individuals); otherwise
  /// whether this trainer or gym can see the member's progress.
  bool? _creatorSees(MemberData data, Challenge c) {
    switch (c.creatorType) {
      case ChallengeCreator.trainer:
        return data.trainerConnections.any(
          (x) =>
              x.trainerId == c.creatorId &&
              x.status == TrainerConnectionStatus.active &&
              x.permissions.has(TrainerPermission.challenges),
        );
      case ChallengeCreator.gym:
        return data.gymSharing.any(
          (g) =>
              g.gym.id == c.creatorId &&
              g.permissions.contains(GymPermission.challenges),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = MemberDataScope.of(context);
    final now = widget.now ?? DateTime.now();
    final c = data.challenges
        .where((x) => x.id == widget.challengeId)
        .firstOrNull;
    final back = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => context.go(AppRoutes.memberActivity),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text(context.tr('activity.title')),
      ),
    );
    if (c == null) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          back,
          if (!data.challengesLoaded)
            const Center(child: CircularProgressIndicator())
          else
            FFEmptyState(title: context.tr('challenge.notFound')),
        ],
      );
    }
    final progress = c.joined
        ? challengeProgress(c, data.activities, checkIns: data.checkInMoments)
        : null;
    final sees = _creatorSees(data, c);
    final dates =
        '${DateFormat('d MMM').format(c.startDate)} – ${DateFormat('d MMM yyyy').format(c.endDate)}';
    final open =
        c.phase == ChallengePhase.active || c.phase == ChallengePhase.upcoming;

    return ListView(
      key: const Key('challenge-detail'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        back,
        ChallengeCard(
          challenge: c,
          progress: progress,
          now: now,
          showView: false,
        ),
        if (c.description != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: Text(c.description!, style: theme.textTheme.bodyLarge),
          ),
        FFSectionTitle(context.tr('challenge.details')),
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Line(
                Icons.flag_outlined,
                '${context.tr('challenge.goal')}: ${challengeTargetText(context, c.type, c.target)}',
              ),
              _Line(Icons.event_outlined, dates),
              _Line(
                Icons.info_outline,
                context.tr('challenge.how.${c.type.wire}'),
              ),
              _Line(
                Icons.groups_outlined,
                context
                    .tr('challenge.participants')
                    .replaceAll('{n}', '${c.participantCount}'),
              ),
            ],
          ),
        ),
        if (c.rewards.isNotEmpty) ...[
          FFSectionTitle(context.tr('challenge.rewards')),
          FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in c.rewards)
                  _Line(Icons.emoji_events_outlined, r),
              ],
            ),
          ),
        ],
        if (c.joined && c.phase != ChallengePhase.cancelled)
          ChallengeLeaderboardSection(
            key: ValueKey('lb-${c.id}-${c.leaderboardOptIn}'),
            challenge: c,
          ),
        if (!c.joined && c.mode.hasTeams)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: Text(
              context.tr('leaderboard.mode.${c.mode.wire}'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (sees != null)
          FFCard(
            key: const Key('challenge-privacy'),
            margin: const EdgeInsets.only(top: FFTokens.spacingMd),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  sees ? Icons.visibility_outlined : Icons.lock_outline,
                  size: 18,
                ),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context
                            .tr(
                              sees
                                  ? 'challenge.creatorSees'
                                  : 'challenge.creatorDoesNotSee',
                            )
                            .replaceAll('{name}', c.creatorName ?? ''),
                        style: theme.textTheme.bodySmall,
                      ),
                      TextButton(
                        key: const Key('challenge-sharing-link'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () =>
                            context.go(AppRoutes.memberActivitySharing),
                        child: Text(context.tr('challenge.changeSharing')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: FFTokens.spacingLg),
        if (open || c.joined)
          SizedBox(
            width: double.infinity,
            child: c.joined
                ? OutlinedButton(
                    key: const Key('challenge-leave'),
                    onPressed: _busy ? null : () => _toggle(c),
                    child: Text(context.tr('challenge.leave')),
                  )
                : FilledButton(
                    key: const Key('challenge-join'),
                    onPressed: _busy ? null : () => _toggle(c),
                    child: Text(context.tr('challenge.join')),
                  ),
          ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: FFTokens.spacingSm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
