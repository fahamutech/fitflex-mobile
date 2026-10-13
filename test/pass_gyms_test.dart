// Which active gyms each FitFlex Pass tier opens, and the list the member
// reviews before paying.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/member/widgets/pass_gyms_sheet.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/pass_gyms.dart';

Gym _gym(
  String id,
  String tier, {
  String status = 'active',
  String name = '',
}) => Gym.fromJson({
  'id': id,
  'name': name.isEmpty ? 'Gym $id' : name,
  'tier': tier,
  'location': 'Kinondoni',
  'perVisitRate': 5000,
  'commissionRate': 12,
  'status': status,
});

void main() {
  final gyms = [
    _gym('s1', 'standard'),
    _gym('s2', 'standard'),
    _gym('s3', 'standard', status: 'suspended'),
    _gym('m1', 'midtier'),
    _gym('m2', 'mid_tier'),
    _gym('p1', 'premium'),
    _gym('p2', 'premium', status: 'pending'),
    _gym('l1', 'luxury_executive'),
    _gym('l2', 'Luxury'),
    _gym('o1', 'online'),
  ];
  Set<String> ids(List<Gym> g) => g.map((x) => x.id).toSet();

  test('a tier opens its own gyms and every tier below it', () {
    expect(ids(gymsForPass('standard', gyms)), {'s1', 's2'});
    expect(ids(gymsForPass('midtier', gyms)), {'s1', 's2', 'm1', 'm2'});
    expect(ids(gymsForPass('premium', gyms)), {'s1', 's2', 'm1', 'm2', 'p1'});
    expect(ids(gymsForPass('luxury_executive', gyms)), {
      's1',
      's2',
      'm1',
      'm2',
      'p1',
      'l1',
      'l2',
    });
  });

  test('only active gyms are listed, and online-only gyms never count', () {
    for (final access in [
      'standard',
      'midtier',
      'premium',
      'luxury_executive',
    ]) {
      final got = gymsForPass(access, gyms);
      expect(got.every(isActiveGym), isTrue, reason: access);
      expect(ids(got).contains('o1'), isFalse, reason: access);
    }
  });

  test('a missing or unknown access level opens every active gym', () {
    expect(gymsForPass(null, gyms).length, 8); // all active, online included
    expect(gymsForPass('', gyms).length, 8);
    expect(gymsForPass('something_new', gyms).length, 8);
  });

  test('gyms are grouped by tier, lowest first, sorted by name', () {
    final g = groupGymsByTier([
      _gym('z', 'premium', name: 'Zulu'),
      _gym('a', 'premium', name: 'alpha'),
      _gym('x', 'standard', name: 'Xray'),
      _gym('m', 'mid_tier', name: 'Mike'),
    ]);
    expect(g.keys.toList(), ['standard', 'midtier', 'premium']);
    expect(g['premium']!.map((x) => x.name), ['alpha', 'Zulu']);
  });

  test('an upgrade adds only the gyms the current plan does not open', () {
    expect(ids(gymsAddedByUpgrade('standard', 'midtier', gyms)), {'m1', 'm2'});
    expect(ids(gymsAddedByUpgrade('midtier', 'premium', gyms)), {'p1'});
    expect(gymsAddedByUpgrade('premium', 'premium', gyms), isEmpty);
  });

  Widget host(Widget child) => FFLocaleScope(
    notifier: FFLocale(),
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets('the list shows groups, filters by search, and picks a gym', (
    tester,
  ) async {
    Gym? opened;
    await tester.pumpWidget(
      host(
        PassGymsList(
          gyms: gymsForPass('midtier', gyms),
          highlightIds: const {'m1'},
          onOpenGym: (g) => opened = g,
        ),
      ),
    );
    expect(find.text('Standard · 2'), findsOneWidget);
    expect(find.text('Mid-tier · 2'), findsOneWidget);
    expect(find.text('Gym m1'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Gym p1'), findsNothing);

    await tester.enterText(find.byType(TextField), 'm2');
    await tester.pump();
    expect(find.text('Gym m2'), findsOneWidget);
    expect(find.text('Gym s1'), findsNothing);

    await tester.tap(find.text('Gym m2'));
    expect(opened?.id, 'm2');
  });

  testWidgets('a plan with no active gyms says so', (tester) async {
    await tester.pumpWidget(host(const PassGymsList(gyms: [])));
    expect(
      find.text('There are no active gyms for this plan yet.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });
}
