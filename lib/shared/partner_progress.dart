// Partner progress (journey audit Phase B · B4b) — the typed view of the
// `progress` block GET /me/kyc adds while the server flag PARTNER_PROGRESS is
// on (fitflex-functions#236). Absent means the app shows what it showed
// before; there is no app flag.
//
// One story for gym owners, trainers and vendors:
//   registered → approved → verified → payoutReady ("Ready to be paid")
//
// Steps are judged one by one on the server: a later step can be done before
// an earlier one, so each step is drawn with its own state. At most one step
// is `current`. Only codes arrive here, never reviewer or admin notes.

enum PartnerStepState {
  done,
  current,
  todo,
  blocked;

  static PartnerStepState parse(Object? wire) => switch (wire) {
    'done' => done,
    'current' => current,
    'blocked' => blocked,
    _ => todo,
  };
}

/// The four steps, in order. Unknown keys from a newer server are dropped.
const partnerStepKeys = ['registered', 'approved', 'verified', 'payoutReady'];

class PartnerStep {
  const PartnerStep({
    required this.key,
    required this.state,
    this.at,
    this.reason,
  });

  /// registered | approved | verified | payoutReady
  final String key;
  final PartnerStepState state;

  /// When the step was done (ISO), when the server knows it.
  final String? at;

  /// Why it is blocked: account_suspended | role_rejected | kyc_rejected |
  /// kyc_suspended. Only on blocked steps.
  final String? reason;

  factory PartnerStep.fromJson(Map<String, dynamic> j) => PartnerStep(
    key: '${j['key']}',
    state: PartnerStepState.parse(j['state']),
    at: _text(j['at']),
    reason: _text(j['reason']),
  );
}

/// One checklist item named by a next action: `identity.fullName`, or
/// `operational.rate_card@gym_1` for an item that belongs to one gym.
class PartnerItemRef {
  const PartnerItemRef(this.key, {this.gymId});

  final String key;
  final String? gymId;

  factory PartnerItemRef.parse(String wire) {
    final at = wire.indexOf('@');
    if (at < 0) return PartnerItemRef(wire);
    return PartnerItemRef(
      wire.substring(0, at),
      gymId: wire.substring(at + 1).isEmpty ? null : wire.substring(at + 1),
    );
  }

  /// The last part of the key, which names its `kyc.item.*` label.
  String get field => key.split('.').last;

  @override
  bool operator ==(Object other) =>
      other is PartnerItemRef && other.key == key && other.gymId == gymId;

  @override
  int get hashCode => Object.hash(key, gymId);
}

/// What the partner (or FitFlex) does next. Always present; `none` when every
/// step is done.
class PartnerNextAction {
  const PartnerNextAction({
    required this.code,
    this.missing = const [],
    this.reasonCode,
    this.reason,
    this.until,
    this.gymId,
  });

  static const none = PartnerNextAction(code: 'none');

  /// wait_for_approval | complete_kyc_items | submit_kyc | kyc_under_review |
  /// kyc_changes_requested | add_payout_account | payout_account_under_review
  /// | payout_account_cooling_off | payout_not_ready | add_gym |
  /// contact_support | none
  final String code;

  /// Checklist items still missing (complete_kyc_items, kyc_changes_requested).
  final List<PartnerItemRef> missing;

  /// The KYC reason code on kyc_changes_requested (may be null).
  final String? reasonCode;

  /// add_payout_account: payout_account_rejected; payout_not_ready: the raw
  /// eligibility reason; contact_support: one of the blocked reasons.
  final String? reason;

  /// payout_account_cooling_off: when the hold ends (ISO), or null.
  final String? until;

  /// The gym a gym owner's overall payout action is about.
  final String? gymId;

  bool get isNone => code == 'none';

  factory PartnerNextAction.fromJson(Map<String, dynamic>? j) {
    if (j == null) return none;
    return PartnerNextAction(
      code: _text(j['code']) ?? 'none',
      missing: [
        for (final m in (j['missing'] as List? ?? const []))
          if (m is String && m.isNotEmpty) PartnerItemRef.parse(m),
      ],
      reasonCode: _text(j['reasonCode']),
      reason: _text(j['reason']),
      until: _text(j['until']),
      gymId: _text(j['gymId']),
    );
  }
}

class PartnerGymProgress {
  const PartnerGymProgress({
    required this.gymId,
    required this.progress,
    this.name,
  });

  final String gymId;
  final String? name;
  final PartnerProgress progress;
}

class PartnerProgress {
  const PartnerProgress({
    required this.steps,
    required this.current,
    required this.nextAction,
    this.gyms = const [],
  });

  final List<PartnerStep> steps;

  /// The first step that is not done; payoutReady when every step is.
  final String current;
  final PartnerNextAction nextAction;

  /// Gym owners only: one entry per gym, since payout readiness is per gym.
  final List<PartnerGymProgress> gyms;

  /// Every step is done (the partner can be paid).
  bool get finished =>
      nextAction.isNone && steps.every((s) => s.state == PartnerStepState.done);

  /// 1-based position of [current] among the steps.
  int get currentNumber {
    final i = steps.indexWhere((s) => s.key == current);
    return i < 0 ? steps.length : i + 1;
  }

  PartnerStep? get currentStep {
    for (final s in steps) {
      if (s.key == current) return s;
    }
    return null;
  }

  String? gymName(String? gymId) {
    if (gymId == null) return null;
    for (final g in gyms) {
      if (g.gymId == gymId) return g.name;
    }
    return null;
  }

  /// Null when [json] is missing or not a usable progress block, so the
  /// caller keeps today's screens.
  static PartnerProgress? tryParse(Object? json) {
    if (json is! Map) return null;
    final j = json.cast<String, dynamic>();
    final steps = <PartnerStep>[
      for (final s in (j['steps'] as List? ?? const []))
        if (s is Map) PartnerStep.fromJson(s.cast<String, dynamic>()),
    ].where((s) => partnerStepKeys.contains(s.key)).toList();
    if (steps.isEmpty) return null;
    final current = _text(j['current']);
    return PartnerProgress(
      steps: steps,
      current: current != null && partnerStepKeys.contains(current)
          ? current
          : steps.last.key,
      nextAction: PartnerNextAction.fromJson(
        (j['nextAction'] as Map?)?.cast<String, dynamic>(),
      ),
      gyms: [
        for (final g in (j['gyms'] as List? ?? const []))
          if (g is Map) ?_gym(g.cast<String, dynamic>()),
      ],
    );
  }

  static PartnerGymProgress? _gym(Map<String, dynamic> g) {
    final id = _text(g['gymId']);
    final progress = tryParse(g['progress']);
    if (id == null || progress == null) return null;
    return PartnerGymProgress(
      gymId: id,
      name: _text(g['name']),
      progress: progress,
    );
  }
}

String? _text(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;
