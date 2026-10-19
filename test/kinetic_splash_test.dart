import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/splash/kinetic_splash.dart';

Widget _host({
  required bool enabled,
  bool reduce = false,
  String? tagline = 'Fitness Without Limits',
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: KineticSplashGate(
      enabled: enabled,
      tagline: tagline,
      child: const Scaffold(body: Text('HOME')),
    ),
  ),
);

void main() {
  testWidgets('plays over the app, then removes itself', (tester) async {
    await tester.pumpWidget(_host(enabled: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(KineticLogo), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1800));
    expect(find.text('Fitness Without Limits'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.byType(KineticLogo), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('tap skips the splash', (tester) async {
    await tester.pumpWidget(_host(enabled: true));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tapAt(tester.getCenter(find.byType(KineticSplashGate)));
    await tester.pump();
    expect(find.byType(KineticLogo), findsNothing);
  });

  testWidgets('disabled shows the app straight away', (tester) async {
    await tester.pumpWidget(_host(enabled: false));
    expect(find.byType(KineticLogo), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('reduce motion: static logo then gone, no animation', (
    tester,
  ) async {
    await tester.pumpWidget(_host(enabled: true, reduce: true));
    await tester.pump();
    expect(find.byType(KineticLogo), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(KineticLogo), findsNothing);
  });

  // Owner 2026-10-19: "Pamoja tuna nguvu" is gone from the splash; in
  // Swahili nothing takes its place. English keeps its tagline.
  test('splash tagline: English line in English, none in Swahili', () {
    expect(
      splashTagline(FFLocale()..set(const Locale('en'))),
      'Fitness Without Limits',
    );
    expect(splashTagline(FFLocale()..set(const Locale('sw'))), isNull);
  });

  testWidgets('no tagline: only the name under the logo, no gap line', (
    tester,
  ) async {
    await tester.pumpWidget(_host(enabled: true, tagline: null));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('FitFlex Africa'), findsOneWidget);
    expect(find.textContaining('Pamoja'), findsNothing);
    expect(find.text('Fitness Without Limits'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  });
}
