import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/challenge.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';

IconData rewardIcon(String type) => switch (type) {
  'points' => Icons.stars_outlined,
  'discount' => Icons.percent,
  'gym_pass' => Icons.confirmation_number_outlined,
  'trainer_session' => Icons.sports_gymnastics,
  'vendor_voucher' => Icons.local_offer_outlined,
  'corporate_reward' => Icons.business_center_outlined,
  'badge' => Icons.military_tech_outlined,
  'certificate' => Icons.workspace_premium_outlined,
  _ => Icons.emoji_events_outlined,
};

/// Who earns it, in words: everyone who finishes, top N, the winning team.
String rewardRuleText(BuildContext context, RewardRule rule, int? topN) =>
    switch (rule) {
      RewardRule.top =>
        context.tr('reward.rule.top').replaceAll('{n}', '${topN ?? ''}'),
      RewardRule.team => context.tr('reward.rule.team'),
      RewardRule.finishers => context.tr('reward.rule.finishers'),
    };

/// What the challenge offers: each reward, its value and who earns it.
class ChallengeRewardsOffered extends StatelessWidget {
  const ChallengeRewardsOffered({super.key, required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in challenge.rewardItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    rewardIcon(r.type),
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.value == null || r.value!.isEmpty
                              ? r.label
                              : '${r.label} · ${r.value}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          rewardRuleText(context, r.rule, r.topN),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
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

/// The member's own rewards from this challenge and where each stands:
/// earned, pending fulfilment → approved → issued, or not approved.
/// Shows nothing until something is earned (or if it can't load).
class ChallengeEarnedRewards extends StatefulWidget {
  const ChallengeEarnedRewards({super.key, required this.challenge});

  final Challenge challenge;

  @override
  State<ChallengeEarnedRewards> createState() => _ChallengeEarnedRewardsState();
}

class _ChallengeEarnedRewardsState extends State<ChallengeEarnedRewards> {
  List<EarnedReward> _mine = const [];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final rows = await api.myRewards();
      if (!mounted) return;
      setState(
        () => _mine = [
          for (final r in rows)
            if (EarnedReward.tryParse(r) case final e?)
              if (e.challengeId == widget.challenge.id) e,
        ],
      );
    } catch (_) {
      // Rewards are extra; the challenge screen works without them.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mine.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFSectionTitle(context.tr('reward.yours')),
        for (final r in _mine) _EarnedCard(reward: r),
      ],
    );
  }
}

class _EarnedCard extends StatelessWidget {
  const _EarnedCard({required this.reward});

  final EarnedReward reward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = reward;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final day = DateFormat.yMMMd(locale);
    final why = switch (r.rule) {
      RewardRule.top =>
        context.tr('reward.why.top').replaceAll('{n}', '${r.rank ?? ''}'),
      RewardRule.team => context.tr('reward.why.team'),
      RewardRule.finishers => context.tr('reward.why.finished'),
    };
    final (FFBadgeTone tone, String statusKey) = switch (r.status) {
      RewardStatus.pending => (FFBadgeTone.warning, 'reward.status.pending'),
      RewardStatus.approved => (FFBadgeTone.brand, 'reward.status.approved'),
      RewardStatus.issued => (FFBadgeTone.success, 'reward.status.issued'),
      RewardStatus.rejected => (FFBadgeTone.danger, 'reward.status.rejected'),
    };
    return FFCard(
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Column(
        key: Key('earned-${r.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, size: 18, color: FFTokens.accent),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(child: Text(why, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                rewardIcon(r.type),
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: Text(
                  context
                      .tr('reward.earned')
                      .replaceAll(
                        '{reward}',
                        r.value == null || r.value!.isEmpty
                            ? r.label
                            : '${r.label} (${r.value})',
                      ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Wrap(
            spacing: FFTokens.spacingSm,
            runSpacing: FFTokens.spacingXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FFBadge(label: context.tr(statusKey), tone: tone, dot: true),
              Text(
                r.status == RewardStatus.issued && r.issuedAt != null
                    ? context
                          .tr('reward.issuedOn')
                          .replaceAll('{date}', day.format(r.issuedAt!))
                    : context
                          .tr('reward.earnedOn')
                          .replaceAll('{date}', day.format(r.earnedAt)),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (r.status == RewardStatus.issued && r.reference != null) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              context.tr('reward.reference').replaceAll('{ref}', r.reference!),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (r.note != null &&
              (r.status == RewardStatus.rejected ||
                  r.status == RewardStatus.issued)) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Text(r.note!, style: theme.textTheme.bodySmall),
          ],
          if (r.status == RewardStatus.pending) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              context.tr('reward.pendingHelp'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
