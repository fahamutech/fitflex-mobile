import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/owner/owner_shell.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, DateTime now) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final data = OwnerData()
    ..ownerGyms = [
      {'id': 'g1', 'name': 'Mikocheni Fitness'},
    ]
    ..activeGymId = 'g1'
    ..dashboard = {
      'totalMembers': 12,
      'periodVisits': 30,
      'prevPeriodVisits': 20,
      'periodMembers': 4,
      'prevPeriodMembers': 4,
      'directMembers': 5,
      'fitflexMembers': 7,
      'chartSeries': [
        {'label': 'W1', 'direct': 2, 'fitflex': 3},
        {'label': 'W2', 'direct': 5, 'fitflex': 7},
      ],
    };
  final api = ApiClient();
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
            body: OwnerDataScope(
              data: data,
              child: OwnerHomeTab(now: now),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('greeting follows the time of day, not always morning', (
    tester,
  ) async {
    await _pump(tester, DateTime(2026, 10, 12, 20));
    expect(find.textContaining('Good evening'), findsOneWidget);
    expect(find.textContaining('Good morning'), findsNothing);
    expect(find.text('Mikocheni Fitness'), findsOneWidget);
  });

  testWidgets('check-in leads; chart sits above engagement and manage tiles', (
    tester,
  ) async {
    await _pump(tester, DateTime(2026, 10, 12, 9));
    expect(find.textContaining('Good morning'), findsOneWidget);
    double top(Key k) => tester.getTopLeft(find.byKey(k)).dy;
    final order = [
      top(const Key('owner-checkin-primary')),
      top(const Key('owner-card-checkins')),
      top(const Key('owner-challenges')),
    ];
    expect(order, [...order]..sort());
    // Shop is a bottom tab now; Trainers is reached from Home.
    expect(find.text('Trainers'), findsOneWidget);
    expect(find.text('Shop'), findsNothing);
    // The grow-your-gym promo (a dead end) is gone.
    expect(find.byIcon(Icons.trending_up), findsNothing);
  });

  testWidgets('trend chips show one arrow, not two', (tester) async {
    await _pump(tester, DateTime(2026, 10, 12, 9));
    final labels = [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        if ((w.data ?? w.textSpan?.toPlainText() ?? '').contains(
          'vs prev period',
        ))
          w.data ?? w.textSpan!.toPlainText(),
    ];
    expect(labels, isNotEmpty);
    for (final l in labels) {
      expect(RegExp(r'[↑↓→].*[↑↓→]').hasMatch(l), isFalse, reason: l);
    }
  });
}
