// My payouts: a trainer sees each weekly statement, what it pays for, where
// it stands, and whether they can be paid at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/trainer/trainer_payouts_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.statements = const [], this.payoutReady = true})
    : super(baseUrl: 'http://localhost:0');

  final List<Map<String, dynamic>> statements;
  final bool payoutReady;

  @override
  Future<Map<String, dynamic>> trainerStatements() async => {
    'statements': statements,
    'payoutReady': payoutReady,
    'payoutBlockedBy': payoutReady ? null : 'kyc_not_started',
  };

  @override
  Future<Map<String, dynamic>> trainerStatement(String id) async => {
    'statement': statements.firstWhere((s) => s['id'] == id),
    'lines': [
      {
        'bookingId': 'tbk_1',
        'memberName': 'Asha M',
        'date': '2026-10-06',
        'slot': '10:00',
        'basis': 'completed',
        'payoutTzs': 17000,
      },
      {
        'bookingId': 'tbk_2',
        'memberName': 'Juma K',
        'date': '2026-10-08',
        'slot': '07:00',
        'basis': 'took_place',
        'payoutTzs': 17000,
      },
    ],
  };
}

Map<String, dynamic> _statement({
  String id = 'tst_1',
  String status = 'paid',
  bool onHold = false,
}) => {
  'id': id,
  'periodStartDate': '2026-10-05',
  'periodEndDate': '2026-10-11',
  'sessionCount': 2,
  'listTzs': 40000,
  'commissionTzs': 6000,
  'finalNetTzs': 34000,
  'status': status,
  'onHold': onHold,
  'paymentReference': status == 'paid' ? 'MPESA-TR1' : null,
  'paidTo': status == 'paid'
      ? {'provider': 'mpesa', 'accountLast4': '0777'}
      : null,
};

Widget _app(_FakeApi api, {String lang = 'en'}) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale()..set(Locale(lang)),
    child: const MaterialApp(home: TrainerPayoutsPage()),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a paid statement shows its sessions and where the money went', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi(statements: [_statement()]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('TZS 34,000'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.textContaining('2 session(s)'), findsOneWidget);
    expect(find.byKey(const Key('payouts-not-ready')), findsNothing);

    await tester.tap(find.byKey(const Key('payout-tst_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payout-net')), findsOneWidget);
    expect(
      find.textContaining('FitFlex commission: TZS 6,000'),
      findsOneWidget,
    );
    expect(find.textContaining('mpesa ····0777'), findsOneWidget);
    expect(find.textContaining('MPESA-TR1'), findsOneWidget);
    expect(find.text('Asha M'), findsOneWidget);
    expect(find.textContaining('Took place'), findsOneWidget);
  });

  testWidgets('a trainer who cannot be paid yet is told what to do', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi(
      statements: [_statement(status: 'approved', onHold: true)],
      payoutReady: false,
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payouts-not-ready')), findsOneWidget);
    expect(find.byKey(const Key('payouts-verify')), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.textContaining('On hold'), findsOneWidget);
  });

  testWidgets('no statements yet reads plainly, in Swahili too', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_app(_FakeApi(), lang: 'sw'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payouts-empty')), findsOneWidget);
    expect(find.text('Malipo yangu'), findsOneWidget);
    expect(find.textContaining('Bado hakuna taarifa'), findsOneWidget);
  });
}
