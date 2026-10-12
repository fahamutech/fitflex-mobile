// The owner top bar: the gym name must keep real room next to the bell,
// language, theme and avatar controls, and the subtitle stays on one line.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

Widget _app(FFOwnerDashboardBar bar, {String lang = 'sw'}) {
  final api = ApiClient(baseUrl: 'http://localhost:0');
  return AppScope(
    api: api,
    auth: AuthState(api),
    child: ThemeScope(
      notifier: ThemeNotifier(),
      child: FFLocaleScope(
        notifier: FFLocale()..set(Locale(lang)),
        child: MaterialApp(
          theme: buildTheme(),
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(appBar: bar, body: const SizedBox()),
        ),
      ),
    ),
  );
}

void main() {
  const gyms = [
    {'id': 'g1', 'name': 'Iron Paradise Dar es Salaam'},
    {'id': 'g2', 'name': 'Zanzibar Iron'},
  ];

  testWidgets(
    'long gym name keeps room at 360dp and the subtitle is one line',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          const FFOwnerDashboardBar(
            selectedGymName: 'Iron Paradise Dar es Salaam',
            initials: 'DO',
            ownerGyms: gyms,
            subtitleLabel: 'Dashibodi ya mmiliki wa gym',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The name is more than a stub ("De…" before the fix).
      final name = tester.getSize(find.text('Iron Paradise Dar es Salaam'));
      expect(name.width, greaterThan(90));
      // The subtitle is a single line and the bar did not grow.
      final subtitle = tester.getSize(find.text('Dashibodi ya mmiliki wa gym'));
      expect(subtitle.height, lessThan(20));
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    },
  );

  testWidgets('tapping the name opens the gym list and selects a gym', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    String? picked;
    await tester.pumpWidget(
      _app(
        FFOwnerDashboardBar(
          selectedGymName: 'Iron Paradise Dar es Salaam',
          initials: 'DO',
          ownerGyms: gyms,
          subtitleLabel: 'Dashibodi',
          onGymSelected: (id) => picked = id,
        ),
      ),
    );
    await tester.tap(find.text('Iron Paradise Dar es Salaam'));
    await tester.pumpAndSettle();
    expect(find.text('Zanzibar Iron'), findsOneWidget);
    await tester.tap(find.text('Zanzibar Iron'));
    await tester.pumpAndSettle();
    expect(picked, 'g2');
  });

  testWidgets('a pending owner has a plain label and no gym menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const FFOwnerDashboardBar(
          selectedGymName: 'Inasubiri idhini',
          initials: 'DO',
          ownerGyms: [],
          subtitleLabel: 'Dashibodi',
        ),
      ),
    );
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Inasubiri idhini'), findsOneWidget);
  });
}
