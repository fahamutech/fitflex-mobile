import 'package:fitflexmobile/screens/member/member_gym_detail_page.dart';
import 'package:fitflexmobile/screens/member/member_gyms_tab.dart';
import 'package:fitflexmobile/screens/member/member_home_tab.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_card.dart';
import 'package:fitflexmobile/screens/member/widgets/trainer_card.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Gym _gym({
  required String id,
  required double? lat,
  required double? lng,
  String location = 'Dar es Salaam',
}) {
  return Gym(
    id: id,
    name: id,
    tier: 'standard',
    location: location,
    perVisitRate: 5000,
    commissionRate: 12,
    status: 'active',
    latitude: lat,
    longitude: lng,
  );
}

void main() {
  test('Gym.fromJson preserves backend coordinates', () {
    final gym = Gym.fromJson({
      'id': 'gym1',
      'name': 'Iron Paradise',
      'tier': 'standard',
      'location': 'Masaki',
      'coordinates': {'lat': -6.7469, 'lng': 39.2666},
    });

    expect(gym.latitude, -6.7469);
    expect(gym.longitude, 39.2666);
    expect(gym.hasCoordinates, true);
  });

  test(
    'gym verified rule follows explicit backend verification fields only',
    () {
      expect(
        gymIsVerified(
          Gym(
            id: 'active-incomplete',
            name: 'Active Incomplete',
            tier: 'standard',
            location: 'Masaki',
            perVisitRate: 5000,
            commissionRate: 12,
            status: 'active',
          ),
        ),
        false,
      );
      expect(
        gymIsVerified(
          Gym(
            id: 'active-complete',
            name: 'Active Complete',
            tier: 'standard',
            location: 'Masaki',
            perVisitRate: 5000,
            commissionRate: 12,
            status: 'active',
            amenities: ['Showers'],
            equipment: ['Treadmill'],
          ),
        ),
        false,
      );
      expect(
        gymIsVerified(
          Gym.fromJson({
            'id': 'verified',
            'name': 'Verified Gym',
            'tier': 'standard',
            'location': 'Masaki',
            'perVisitRate': 5000,
            'commissionRate': 12,
            'status': 'active',
            'isVerified': true,
          }),
        ),
        true,
      );
    },
  );

  testWidgets('verified backend gym renders the member-facing badge', (
    tester,
  ) async {
    final gym = Gym.fromJson({
      'id': 'verified-card',
      'name': 'Verified Gym',
      'tier': 'standard',
      'location': 'Masaki',
      'perVisitRate': 5000,
      'commissionRate': 12,
      'status': 'active',
      'verified': true,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GymCard(gym: gym)),
      ),
    );

    expect(find.byType(GymVerifiedIcon), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsOneWidget);
  });

  testWidgets('verified gym grid card fits the Pixel 7 grid constraints', (
    tester,
  ) async {
    final gym = Gym.fromJson({
      'id': 'pixel-7-card',
      'name': 'Verified Gym With A Long Name',
      'tier': 'standard',
      'location': 'Makumbusho, Dar es Salaam',
      'perVisitRate': 10000,
      'commissionRate': 12,
      'status': 'active',
      'verified': true,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 173.7,
            height: 241.3,
            child: GymGridCard(gym: gym, distanceKm: 3.2),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(GymVerifiedIcon), findsOneWidget);
    expect(find.text('3.2 km'), findsOneWidget);
  });

  testWidgets('trainer grid card fits the Infinix device grid constraints', (
    tester,
  ) async {
    final trainer = TrainerProfile(
      id: 'infinix-card',
      displayName: 'Trainer With A Long Display Name',
      specialties: const ['Strength', 'Conditioning'],
      hourlyRateTzs: 50000,
      status: 'active',
      isVerified: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 169.3,
            height: 249,
            child: TrainerGridCard(trainer: trainer),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.verified), findsOneWidget);
    expect(find.text('TZS 50,000'), findsOneWidget);
  });

  test('nearest sorting can order gyms by km distance', () {
    final gyms = [
      _gym(id: 'far', lat: -6.8162, lng: 39.2886),
      _gym(id: 'near', lat: -6.7469, lng: 39.2666),
      _gym(id: 'missing', lat: null, lng: null),
    ];

    gyms.sort(
      (a, b) => gymDistanceKm(
        a,
        -6.7500,
        39.2600,
      ).compareTo(gymDistanceKm(b, -6.7500, 39.2600)),
    );

    expect(gyms.map((g) => g.id), ['near', 'far', 'missing']);
    expect(gymDistanceKm(gyms.first, -6.7500, 39.2600), lessThan(1));
  });

  test(
    'home near gyms uses nearest two when location exists and falls back otherwise',
    () {
      final gyms = [
        _gym(id: 'fallback-first', lat: -6.9000, lng: 39.3000),
        _gym(id: 'nearest', lat: -6.7469, lng: 39.2666),
        _gym(id: 'second-nearest', lat: -6.7600, lng: 39.2700),
      ];

      expect(
        memberHomeNearGyms(
          gyms,
          userLat: -6.7500,
          userLng: 39.2600,
        ).map((g) => g.id),
        ['nearest', 'second-nearest'],
      );
      expect(memberHomeNearGyms(gyms).map((g) => g.id), [
        'fallback-first',
        'nearest',
      ]);
    },
  );

  test(
    'gym display distance is available for every filter once location is known',
    () {
      final gym = _gym(id: 'near', lat: -6.7469, lng: 39.2666);

      expect(
        gymDisplayDistanceKm(
          gym,
          userLat: -6.7500,
          userLng: 39.2600,
          activeFilter: 'all',
        ),
        lessThan(1),
      );
      expect(
        gymDisplayDistanceKm(
          gym,
          userLat: -6.7500,
          userLng: 39.2600,
          activeFilter: 'standard',
        ),
        lessThan(1),
      );
    },
  );

  test('gym directions URL includes current location and gym destination', () {
    final uri = gymDirectionsUri(
      _gym(id: 'gym1', lat: -6.7469, lng: 39.2666),
      originLat: -6.8000,
      originLng: 39.2800,
    );

    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters['origin'], '-6.8,39.28');
    expect(uri.queryParameters['destination'], '-6.7469,39.2666');
    expect(uri.queryParameters['travelmode'], 'driving');
  });
}
