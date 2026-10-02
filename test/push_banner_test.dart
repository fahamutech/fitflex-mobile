// A push that arrives while the app is open: the phone shows nothing, so
// the app shows a banner with the message and a way to open it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/shared/push_banner.dart';

void main() {
  Future<GlobalKey<ScaffoldMessengerState>> pump(WidgetTester tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: key,
        home: const Scaffold(body: Text('home')),
      ),
    );
    return key;
  }

  testWidgets('shows the title and text, and Open follows the message', (
    tester,
  ) async {
    final key = await pump(tester);
    var opened = 0;
    showPushBanner(
      key.currentState!,
      title: 'JOB OFFER',
      body: 'TRAINER NEEDED at FitFlex',
      openLabel: 'Open',
      onOpen: () => opened += 1,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const Key('push-banner')), findsOneWidget);
    expect(find.text('JOB OFFER'), findsOneWidget);
    expect(find.text('TRAINER NEEDED at FitFlex'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('a newer push replaces the banner; an empty one shows nothing', (
    tester,
  ) async {
    final key = await pump(tester);
    showPushBanner(
      key.currentState!,
      title: '',
      body: null,
      openLabel: 'Open',
      onOpen: () {},
    );
    await tester.pump();
    expect(find.byKey(const Key('push-banner')), findsNothing);

    for (final title in ['First', 'Second']) {
      showPushBanner(
        key.currentState!,
        title: title,
        body: 'text',
        openLabel: 'Open',
        onOpen: () {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });
}
