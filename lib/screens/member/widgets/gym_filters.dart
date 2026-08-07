import '../../../shared/models.dart';

/// A9 — member gym discovery filter model. Pure and unit-testable.
class GymFilter {
  const GymFilter({
    this.search = '',
    this.tier = 'all',
    this.price = 'any',
    this.amenities = const {},
    this.verifiedOnly = false,
  });

  /// Free-text search over name/location/tier/amenities/equipment.
  final String search;

  /// all | nearest | standard | midtier | premium
  final String tier;

  /// any | <60k | <150k | <200k | <350k | 350k+
  final String price;

  /// Selected amenity filters — a gym must match ALL of them.
  final Set<String> amenities;

  /// Only show verified gyms (A6).
  final bool verifiedOnly;

  GymFilter copyWith({
    String? search,
    String? tier,
    String? price,
    Set<String>? amenities,
    bool? verifiedOnly,
  }) => GymFilter(
    search: search ?? this.search,
    tier: tier ?? this.tier,
    price: price ?? this.price,
    amenities: amenities ?? this.amenities,
    verifiedOnly: verifiedOnly ?? this.verifiedOnly,
  );
}

String _norm(Object? v) => v?.toString().trim().toLowerCase() ?? '';

String gymTierKey(Gym gym) {
  final t = _norm(gym.tier).replaceAll('-', '_').replaceAll(' ', '_');
  if (t == 'mid_tier' || t == 'midrange' || t == 'mid_range') return 'midtier';
  if (t == 'luxury' || t == 'executive') return 'luxury_executive';
  return t;
}

bool _matchesPrice(Gym g, String price) {
  final rate = g.ratePerMonth ?? g.perVisitRate;
  switch (price) {
    case '<60k':
      return rate < 60000;
    case '<150k':
      return rate < 150000;
    case '<200k':
      return rate < 200000;
    case '<350k':
      return rate < 350000;
    case '350k+':
      return rate >= 350000;
    default:
      return true;
  }
}

/// Applies [filter] to [gyms]. Distance sorting for 'nearest' is handled by
/// the caller (requires user coordinates).
List<Gym> applyGymFilter(List<Gym> gyms, GymFilter filter) {
  var result = gyms;

  final q = _norm(filter.search);
  if (q.isNotEmpty) {
    result = result
        .where(
          (g) =>
              _norm(g.name).contains(q) ||
              _norm(g.location).contains(q) ||
              _norm(g.tier).contains(q) ||
              g.amenities.any((a) => _norm(a).contains(q)) ||
              g.equipment.any((e) => _norm(e).contains(q)),
        )
        .toList();
  }

  if (filter.tier == 'standard') {
    result = result.where((g) => gymTierKey(g) == 'standard').toList();
  } else if (filter.tier == 'midtier') {
    result = result.where((g) => gymTierKey(g) == 'midtier').toList();
  } else if (filter.tier == 'premium') {
    result = result.where((g) {
      final t = gymTierKey(g);
      return t == 'premium' || t == 'luxury_executive';
    }).toList();
  }

  if (filter.price != 'any') {
    result = result.where((g) => _matchesPrice(g, filter.price)).toList();
  }

  // A9: amenities multi-select — gym must offer every selected amenity.
  if (filter.amenities.isNotEmpty) {
    result = result.where((g) {
      final available = [...g.amenities, ...g.equipment].map(_norm).toList();
      return filter.amenities.every(
        (wanted) => available.any((a) => a.contains(_norm(wanted))),
      );
    }).toList();
  }

  // A9/A6: verified-only toggle.
  if (filter.verifiedOnly) {
    result = result
        .where(
          (g) =>
              g.isVerified ||
              g.verificationStatus == 'verified' ||
              g.verificationStatus == 'approved',
        )
        .toList();
  }

  return result;
}

/// Union of amenities across all gyms — powers the amenities filter chips.
/// Excludes rating-style entries (e.g. "cleanliness 4.5").
List<String> availableAmenityOptions(List<Gym> gyms, {int limit = 12}) {
  final counts = <String, int>{};
  for (final gym in gyms) {
    for (final amenity in gym.amenities) {
      final key = _norm(amenity);
      if (key.isEmpty) continue;
      if (RegExp(r'[0-5](\.\d)?$').hasMatch(key)) continue; // ratings
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final sorted = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return sorted.take(limit).toList();
}
