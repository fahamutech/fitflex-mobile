/// Challenge rewards: what a challenge offers, and what the member earned.
///
/// Earning a reward isn't the same as receiving it. An earned reward starts
/// as pending fulfilment, is approved, then issued by whoever funds it
/// (FitFlex, a partner or the member's company) — or rejected with a reason.
library;

/// Who earns a reward.
enum RewardRule {
  finishers('finishers'),
  top('top'),
  team('team');

  const RewardRule(this.wire);
  final String wire;

  static RewardRule fromWire(String? v) =>
      values.firstWhere((r) => r.wire == v, orElse: () => RewardRule.finishers);
}

enum RewardStatus {
  pending('pending'),
  approved('approved'),
  issued('issued'),
  rejected('rejected');

  const RewardStatus(this.wire);
  final String wire;

  static RewardStatus fromWire(String? v) =>
      values.firstWhere((s) => s.wire == v, orElse: () => RewardStatus.pending);
}

/// Reward types this build names; anything else shows as "other".
const rewardTypes = {
  'points',
  'discount',
  'gym_pass',
  'trainer_session',
  'vendor_voucher',
  'corporate_reward',
  'badge',
  'certificate',
  'other',
};

String _type(Object? v) => rewardTypes.contains(v) ? v as String : 'other';

/// One reward a challenge offers.
class ChallengeRewardItem {
  const ChallengeRewardItem({
    required this.id,
    required this.label,
    this.type = 'other',
    this.value,
    this.rule = RewardRule.finishers,
    this.topN,
  });

  final String id;
  final String type;
  final String label;
  final String? value;
  final RewardRule rule;
  final int? topN;

  static ChallengeRewardItem? tryParse(Object? json) {
    if (json is! Map) return null;
    final label = json['label'];
    if (label is! String || label.isEmpty) return null;
    return ChallengeRewardItem(
      id: json['id'] as String? ?? label,
      type: _type(json['type']),
      label: label,
      value: json['value']?.toString(),
      rule: RewardRule.fromWire(json['rule'] as String?),
      topN: (json['topN'] as num?)?.toInt(),
    );
  }
}

/// A reward the member earned, and where it stands.
class EarnedReward {
  const EarnedReward({
    required this.id,
    required this.challengeId,
    required this.label,
    required this.earnedAt,
    this.challengeName,
    this.type = 'other',
    this.value,
    this.rule = RewardRule.finishers,
    this.rank,
    this.status = RewardStatus.pending,
    this.issuedAt,
    this.reference,
    this.note,
  });

  final String id;
  final String challengeId;
  final String? challengeName;
  final String type;
  final String label;
  final String? value;
  final RewardRule rule;

  /// Place, for a top-places reward.
  final int? rank;
  final RewardStatus status;
  final DateTime earnedAt;
  final DateTime? issuedAt;

  /// What was handed over (voucher code, pass or booking id), once issued.
  final String? reference;

  /// The reason, when rejected; otherwise any note from whoever issued it.
  final String? note;

  static EarnedReward? tryParse(Object? json) {
    if (json is! Map) return null;
    final challenge = json['challenge'] is Map
        ? json['challenge'] as Map
        : const {};
    final reward = json['reward'] is Map ? json['reward'] as Map : const {};
    final earned = DateTime.tryParse(json['earnedAt'] as String? ?? '');
    final label = reward['label'];
    if (label is! String || earned == null) return null;
    return EarnedReward(
      id: json['id'] as String? ?? '',
      challengeId: challenge['id'] as String? ?? '',
      challengeName: challenge['name'] as String?,
      type: _type(reward['type']),
      label: label,
      value: reward['value']?.toString(),
      rule: RewardRule.fromWire(reward['rule'] as String?),
      rank: (json['rank'] as num?)?.toInt(),
      status: RewardStatus.fromWire(json['status'] as String?),
      earnedAt: earned.toLocal(),
      issuedAt: DateTime.tryParse(json['issuedAt'] as String? ?? '')?.toLocal(),
      reference: json['reference'] as String?,
      note: json['note'] as String?,
    );
  }
}
