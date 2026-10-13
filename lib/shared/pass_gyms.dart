// Which gyms a FitFlex Pass tier opens — the one rule the passes page, the
// upgrade view and the payment page all use. Mirrors the server: a tier opens
// its own gym tier and every tier below it (Basic: standard; Pro: + mid-tier;
// Premium: + premium; Executive: all). Only active gyms are ever listed, so a
// member never sees a gym they cannot actually check in at.
import 'models.dart';

/// Gym tiers from lowest to highest.
const passGymTierOrder = <String>[
  'standard',
  'midtier',
  'premium',
  'luxury_executive',
];

/// The gym's tier as one of [passGymTierOrder], or the cleaned-up raw value.
String passGymTierKey(String? raw) {
  final t = (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[-\s]+'), '_');
  if (t == 'mid_tier' || t == 'midrange' || t == 'mid_range') return 'midtier';
  if (t == 'luxury' || t == 'executive') return 'luxury_executive';
  return t;
}

/// A gym that is live today. An empty status counts as live, as on the server.
bool isActiveGym(Gym g) => g.status.isEmpty || g.status == 'active';

/// The active gyms a pass with this `gymAccess` opens. An access level that is
/// missing or not recognised opens every active gym, as before.
List<Gym> gymsForPass(String? gymAccess, List<Gym> gyms) {
  final active = gyms.where(isActiveGym);
  final max = passGymTierOrder.indexOf(passGymTierKey(gymAccess));
  if (max < 0) return active.toList();
  return active.where((g) {
    final i = passGymTierOrder.indexOf(passGymTierKey(g.tier));
    return i >= 0 && i <= max;
  }).toList();
}

/// [gyms] grouped by gym tier, lowest tier first, each group sorted by name.
/// A tier with no gyms is left out.
Map<String, List<Gym>> groupGymsByTier(List<Gym> gyms) {
  final out = <String, List<Gym>>{};
  for (final tier in passGymTierOrder) {
    final inTier = gyms.where((g) => passGymTierKey(g.tier) == tier).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (inTier.isNotEmpty) out[tier] = inTier;
  }
  return out;
}

/// The gyms [toAccess] opens that [fromAccess] does not: what an upgrade adds.
List<Gym> gymsAddedByUpgrade(
  String? fromAccess,
  String? toAccess,
  List<Gym> gyms,
) {
  final have = gymsForPass(fromAccess, gyms).map((g) => g.id).toSet();
  return gymsForPass(
    toAccess,
    gyms,
  ).where((g) => !have.contains(g.id)).toList();
}
