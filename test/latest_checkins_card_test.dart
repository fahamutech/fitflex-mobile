import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/owner/widgets/latest_checkins_card.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this.rows, {this.fail = false}) : super(baseUrl: 'http://x.local');

  final List<Map<String, dynamic>> rows;
  final bool fail;
  int calls = 0;

  @override
  Future<List<dynamic>> ownerGymCheckins(String gymId) async {
    calls++;
    if (fail) throw Exception('boom');
    return rows;
  }
}

Map<String, dynamic> _row(
  String id,
  String at, {
  String type = 'platform_pass',
  String? tier = 'pro',
}) => {
  'id': id,
  'memberPublicId': id,
  'timestamp': at,
  'subscriptionType': type,
  'passTier': tier,
};

Future<void> _pump(
  WidgetTester tester,
  _FakeApi api, {
  VoidCallback? onSeeAll,
}) async {
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: AuthState(api),
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          theme: buildTheme(),
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: LatestCheckinsCard(
              gymId: 'g1',
              now: DateTime(2026, 10, 13, 20),
              onSeeAll: onSeeAll ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the latest three, newest first, with time and plan', (
    tester,
  ) async {
    final api = _FakeApi([
      _row('FF-1', '2026-10-13T10:00:00'),
      _row('FF-2', '2026-10-13T15:30:00', type: 'direct_sub', tier: null),
      _row('FF-3', '2026-10-13T12:00:00', tier: 'premium'),
      _row('FF-4', '2026-10-12T09:00:00'),
    ]);
    await _pump(tester, api);
    expect(find.text('Latest check-ins'), findsOneWidget);
    final top = [
      for (final id in ['FF-2', 'FF-3', 'FF-1'])
        tester.getTopLeft(find.textContaining(id)).dy,
    ];
    expect(top, [...top]..sort());
    expect(find.textContaining('FF-4'), findsNothing);
    expect(find.textContaining('Your own plan'), findsOneWidget);
    expect(find.textContaining('FitFlex Premium'), findsOneWidget);
    expect(find.text('15:30'), findsOneWidget);
  });

  testWidgets('empty gym explains where check-ins appear', (tester) async {
    await _pump(tester, _FakeApi([]));
    expect(find.textContaining('No check-ins yet'), findsOneWidget);
    expect(find.byKey(const Key('owner-latest-checkins-all')), findsNothing);
  });

  testWidgets('a failed load leaves no block behind', (tester) async {
    await _pump(tester, _FakeApi([], fail: true));
    expect(find.text('Latest check-ins'), findsNothing);
  });

  testWidgets('See all calls back', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      _FakeApi([_row('FF-1', '2026-10-13T10:00:00')]),
      onSeeAll: () => tapped = true,
    );
    await tester.tap(find.byKey(const Key('owner-latest-checkins-all')));
    expect(tapped, isTrue);
  });
}
