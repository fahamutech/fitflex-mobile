import '../member_shell.dart';

/// What the member's pass is doing right now. One place decides this, so
/// Home, My QR and Profile can agree instead of each reading `status`.
enum PassState {
  /// No pass and nothing in flight.
  none,

  /// A payment is waiting for FitFlex to confirm it.
  pending,

  /// Can train.
  active,

  /// Can train, but three visits or fewer are left.
  lowVisits,

  /// Can train, but the pass ends within three days.
  endingSoon,

  /// Was a pass, no longer one.
  ended,
}

/// How a state reads on screen: green you can train, amber waiting or running
/// low, grey not active.
enum PassTone { success, warning, neutral }

const lowVisitsThreshold = 3;
const endingSoonDays = 3;

extension PassStateX on PassState {
  /// The QR is only live in these states.
  bool get canShowQr =>
      this == PassState.active ||
      this == PassState.lowVisits ||
      this == PassState.endingSoon;

  PassTone get tone => switch (this) {
    PassState.active => PassTone.success,
    PassState.lowVisits ||
    PassState.endingSoon ||
    PassState.pending => PassTone.warning,
    PassState.none || PassState.ended => PassTone.neutral,
  };
}

/// Visits left on a capped pass, or null when uncapped / unknown.
int? visitsLeft(MemberData d) {
  final cap = d.me?.visitCap;
  if (cap == null || cap <= 0) return null;
  final left = cap - (d.me?.visitsUsed ?? 0);
  return left < 0 ? 0 : left;
}

PassState passStateFor(MemberData d) {
  final sub = d.subscription;
  if (d.hasActivePass) {
    final days = sub?.daysLeft;
    final left = visitsLeft(d);
    if (days != null && days >= 0 && days <= endingSoonDays) {
      return PassState.endingSoon;
    }
    if (left != null && left <= lowVisitsThreshold) {
      return PassState.lowVisits;
    }
    return PassState.active;
  }
  if (d.pendingPayment != null) return PassState.pending;
  if (sub != null && (sub.isExpired || sub.status != 'inactive')) {
    return PassState.ended;
  }
  return PassState.none;
}
