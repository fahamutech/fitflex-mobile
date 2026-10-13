import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/pass_state.dart';
import 'package:fitflexmobile/screens/member/widgets/pass_summary_card.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

MemberData _data({
  Map<String, dynamic>? subscription,
  Map<String, dynamic>? pending,
  int used = 0,
  int? cap = 18,
}) {
  return MemberData()
    ..me = MemberMeResponse.fromJson({
      'user': {
        'id': 'm1',
        'displayName': 'Godliving',
        'onboardingCompleted': true,
      },
      'visitsUsed': used,
      'visitCap': cap,
      'subscription': ?subscription,
      'pendingPayment': ?pending,
    });
}

Map<String, dynamic> _pass({String status = 'active', int daysLeft = 30}) => {
  'id': 's1',
  'type': 'platform_pass',
  'tier': 'pro',
  'status': status,
  'expiresAt': DateTime.now()
      .add(Duration(days: daysLeft, hours: 12))
      .toUtc()
      .toIso8601String(),
};

Future<void> _pumpCard(
  WidgetTester tester,
  MemberData data, {
  Widget Function(MemberData)? body,
}) async {
  await tester.pumpWidget(
    FFLocaleScope(
      notifier: FFLocale(),
      child: MaterialApp(
        theme: buildTheme(),
        supportedLocales: const [Locale('en'), Locale('sw')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MemberDataScope(
          data: data,
          child: Scaffold(
            body: body?.call(data) ?? PassSummaryCard(data: data),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('passStateFor', () {
    test('no pass, nothing in flight', () {
      expect(passStateFor(_data()), PassState.none);
    });

    test('a payment waiting for confirmation', () {
      final d = _data(
        pending: {'id': 'p1', 'status': 'pending', 'tier': 'pro'},
      );
      expect(passStateFor(d), PassState.pending);
      expect(passStateFor(d).canShowQr, isFalse);
    });

    test('active with plenty left', () {
      final d = _data(subscription: _pass(), used: 7);
      expect(passStateFor(d), PassState.active);
      expect(passStateFor(d).tone, PassTone.success);
      expect(visitsLeft(d), 11);
    });

    test('three visits or fewer left is low, and the QR still works', () {
      final d = _data(subscription: _pass(), used: 15);
      expect(passStateFor(d), PassState.lowVisits);
      expect(passStateFor(d).canShowQr, isTrue);
      expect(passStateFor(d).tone, PassTone.warning);
    });

    test('ending within three days beats low visits', () {
      final d = _data(subscription: _pass(daysLeft: 2), used: 17);
      expect(passStateFor(d), PassState.endingSoon);
    });

    test('an uncapped pass has no visits left to count', () {
      final d = _data(subscription: _pass(), cap: null);
      expect(visitsLeft(d), isNull);
      expect(passStateFor(d), PassState.active);
    });

    test('an expired pass is ended and hides the QR', () {
      final d = _data(subscription: _pass(status: 'expired'));
      expect(passStateFor(d), PassState.ended);
      expect(passStateFor(d).canShowQr, isFalse);
    });
  });

  group('PassSummaryCard', () {
    testWidgets('active pass: ring shows visits left and Show my QR', (
      tester,
    ) async {
      await _pumpCard(tester, _data(subscription: _pass(), used: 7));
      expect(find.byKey(const Key('pass-visits-ring')), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('of 18 visits'), findsOneWidget);
      expect(find.text('Show my QR'), findsOneWidget);
      expect(find.byKey(const Key('pass-upgrade-action')), findsOneWidget);
    });

    testWidgets('low visits says how many are left', (tester) async {
      await _pumpCard(tester, _data(subscription: _pass(), used: 15));
      expect(find.text('3 visits left'), findsOneWidget);
      expect(find.text('Show my QR'), findsOneWidget);
    });

    testWidgets('ending soon says the date once, in the sentence', (
      tester,
    ) async {
      await _pumpCard(tester, _data(subscription: _pass(daysLeft: 2)));
      expect(find.textContaining('Your pass ends'), findsOneWidget);
      expect(find.textContaining('Ends '), findsNothing);
      expect(find.text('Show my QR'), findsOneWidget);
    });

    testWidgets('pending payment: no QR, no ring, a clear sentence', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _data(pending: {'id': 'p1', 'status': 'pending', 'tier': 'pro'}),
      );
      expect(find.byKey(const Key('pass-visits-ring')), findsNothing);
      expect(find.text('Show my QR'), findsNothing);
      expect(find.byKey(const Key('pass-state-message')), findsOneWidget);
      expect(find.text('View payment'), findsOneWidget);
      expect(find.byKey(const Key('pass-upgrade-action')), findsNothing);
    });

    testWidgets('ended pass offers Pay again, not the QR', (tester) async {
      await _pumpCard(tester, _data(subscription: _pass(status: 'expired')));
      expect(find.text('Pay again'), findsOneWidget);
      expect(find.text('Show my QR'), findsNothing);
    });
  });

  group('My QR reads the same state', () {
    Widget qr(MemberData _) => const MemberQrTab();

    testWidgets('low visits: the QR stays and an amber notice says why', (
      tester,
    ) async {
      final d = _data(subscription: _pass(), used: 16)..qrToken = 'tok';
      await _pumpCard(tester, d, body: qr);
      expect(find.byKey(const Key('qr-state-notice')), findsOneWidget);
      expect(find.text('2 visits left'), findsOneWidget);
    });

    testWidgets('an active pass shows no notice', (tester) async {
      final d = _data(subscription: _pass(), used: 2)..qrToken = 'tok';
      await _pumpCard(tester, d, body: qr);
      expect(find.byKey(const Key('qr-state-notice')), findsNothing);
    });

    testWidgets('an ended pass says when it ended and offers Pay again', (
      tester,
    ) async {
      final d = _data(subscription: _pass(status: 'expired'));
      await _pumpCard(tester, d, body: qr);
      expect(find.textContaining('Your pass ended'), findsOneWidget);
      expect(find.text('Pay again'), findsOneWidget);
    });
  });
}
