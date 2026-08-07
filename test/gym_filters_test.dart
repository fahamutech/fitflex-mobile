// Batch 3 (A6/A9) — gym filter predicates including amenities multi-select
// and verified-only.

import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_filters.dart';

Gym _gym(
  String id, {
  String tier = 'standard',
  num month = 100000,
  List<String> amenities = const [],
  List<String> equipment = const [],
  bool verified = false,
}) => Gym.fromJson({
  'id': id,
  'name': 'Gym $id',
  'tier': tier,
  'location': 'Dar es Salaam',
  'perVisitRate': 5000,
  'ratePerMonth': month,
  'commissionRate': 12,
  'status': 'active',
  'amenities': amenities,
  'equipment': equipment,
  'verified': verified,
});

void main() {
  final gyms = [
    _gym(
      'a',
      amenities: ['showers', 'sauna'],
      equipment: ['treadmills'],
      verified: true,
    ),
    _gym('b', amenities: ['showers'], equipment: ['yoga'], month: 50000),
    _gym('c', tier: 'premium', amenities: ['pool'], verified: true),
  ];

  group('applyGymFilter (A9)', () {
    test('no filter returns everything', () {
      expect(applyGymFilter(gyms, const GymFilter()).length, 3);
    });

    test('single amenity filter matches gyms offering it', () {
      final out = applyGymFilter(gyms, const GymFilter(amenities: {'showers'}));
      expect(out.map((g) => g.id), ['a', 'b']);
    });

    test('multiple amenities require ALL to match', () {
      final out = applyGymFilter(
        gyms,
        const GymFilter(amenities: {'showers', 'sauna'}),
      );
      expect(out.map((g) => g.id), ['a']);
    });

    test('amenity filter also searches equipment (classes like yoga)', () {
      final out = applyGymFilter(gyms, const GymFilter(amenities: {'yoga'}));
      expect(out.map((g) => g.id), ['b']);
    });

    test('verified-only keeps only verified gyms (A6)', () {
      final out = applyGymFilter(gyms, const GymFilter(verifiedOnly: true));
      expect(out.map((g) => g.id), ['a', 'c']);
    });

    test('price and amenity filters combine', () {
      final out = applyGymFilter(
        gyms,
        const GymFilter(price: '<60k', amenities: {'showers'}),
      );
      expect(out.map((g) => g.id), ['b']);
    });

    test('tier filter still works through the shared helper', () {
      final out = applyGymFilter(gyms, const GymFilter(tier: 'premium'));
      expect(out.map((g) => g.id), ['c']);
    });

    test('empty result when nothing matches', () {
      final out = applyGymFilter(
        gyms,
        const GymFilter(amenities: {'crossfit rig'}),
      );
      expect(out, isEmpty);
    });
  });

  group('availableAmenityOptions (A9)', () {
    test('collects unique amenities sorted by frequency', () {
      final options = availableAmenityOptions(gyms);
      expect(options.first, 'showers');
      expect(options, containsAll(['sauna', 'pool']));
    });

    test('excludes rating-style entries', () {
      final withRatings = [
        _gym('r', amenities: ['cleanliness 4.5', 'showers']),
      ];
      final options = availableAmenityOptions(withRatings);
      expect(options, ['showers']);
    });
  });

  group('Gym verified parsing (A6)', () {
    test('parses verified flag from backend payload', () {
      expect(_gym('v', verified: true).isVerified, isTrue);
      expect(_gym('u').isVerified, isFalse);
    });
  });
}
