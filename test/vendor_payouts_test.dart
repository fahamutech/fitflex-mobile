// My payouts for a vendor: weekly statements for delivered orders, after
// FitFlex's commission, on the page shared with trainers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/widgets/partner_payouts_page.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.statements = const [], this.payoutReady = true})
    : super(baseUrl: 'http://localhost:0');

  final List<Map<String, dynamic>> statements;
  final bool payoutReady;

  @override
  Future<Map<String, dynamic>> vendorPayoutStatements() async => {
    'statements': statements,
    'payoutReady': payoutReady,
  };

  @override
  Future<Map<String, dynamic>> vendorPayoutStatement(String id) async => {
    'statement': statements.firstWhere((s) => s['id'] == id),
    'lines': [
      {
        'orderId': 'ord_1',
        'deliveredOn': '2026-10-07',
        'itemCount': 2,
        'salesTzs': 80000,
        'commissionTzs': 8000,
        'payoutTzs': 72000,
      },
      {
        'orderId': 'ord_2',
        'deliveredOn': '2026-10-11',
        'itemCount': 1,
        'salesTzs': 10000,
        'commissionTzs': 1000,
        'payoutTzs': 9000,
      },
    ],
  };
}

Map<String, dynamic> _statement({String status = 'paid'}) => {
  'id': 'vst_1',
  'periodStartDate': '2026-10-05',
  'periodEndDate': '2026-10-11',
  'orderCount': 2,
  'salesTzs': 90000,
  'commissionTzs': 9000,
  'finalNetTzs': 81000,
  'status': status,
  'onHold': false,
  'paymentReference': status == 'paid' ? 'CRDB-V1' : null,
  'paidTo': status == 'paid'
      ? {'provider': 'CRDB', 'accountLast4': '1234'}
      : null,
};

Widget _app(_FakeApi api, {String lang = 'en'}) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale()..set(Locale(lang)),
    child: const MaterialApp(home: PartnerPayoutsPage(kind: PayoutKind.vendor)),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a paid vendor statement shows its orders, commission and bank', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_app(_FakeApi(statements: [_statement()])));
    await tester.pumpAndSettle();
    expect(find.text('TZS 81,000'), findsOneWidget);
    expect(find.textContaining('2 order(s)'), findsOneWidget);
    expect(find.textContaining('delivered'), findsOneWidget);

    await tester.tap(find.byKey(const Key('payout-vst_1')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Sales of your items: TZS 90,000'),
      findsOneWidget,
    );
    expect(
      find.textContaining('FitFlex commission: TZS 9,000'),
      findsOneWidget,
    );
    expect(find.textContaining('CRDB ····1234'), findsOneWidget);
    expect(find.textContaining('CRDB-V1'), findsOneWidget);
    expect(find.byKey(const Key('payout-line-ord_1')), findsOneWidget);
    expect(find.textContaining('2 item(s)'), findsOneWidget);
    expect(find.text('TZS 72,000'), findsOneWidget);
  });

  testWidgets('a vendor who cannot be paid yet is told, in Swahili too', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(
        _FakeApi(
          statements: [_statement(status: 'approved')],
          payoutReady: false,
        ),
        lang: 'sw',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payouts-not-ready')), findsOneWidget);
    expect(find.text('Imeidhinishwa'), findsOneWidget);
    expect(find.textContaining('Oda 2'), findsOneWidget);
  });

  testWidgets('no statements yet explains when the first one appears', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_app(_FakeApi()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payouts-empty')), findsOneWidget);
    expect(find.textContaining('first delivered order'), findsOneWidget);
  });
}
