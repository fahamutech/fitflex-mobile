// Owner statements (settlement Phase 5): the models, the list card on the
// Earnings screen and one statement in full. The page runs on a fake loader,
// so no network is involved.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/owner/owner_statement_page.dart';
import 'package:fitflexmobile/screens/owner/widgets/statement_models.dart';
import 'package:fitflexmobile/shared/i18n.dart';

const _paid = {
  'id': 'st-sep',
  'gymId': 'gym-1',
  'gymName': 'Mikocheni Fitness',
  'periodStartDate': '2026-09-01',
  'periodEndDate': '2026-09-30',
  'status': 'paid',
  'onHold': false,
  'members': 2,
  'visits': 9,
  'earnedTzs': 120000,
  'networkAdjustmentTzs': 15000,
  'adjustmentsTzs': -3500,
  'carriedForwardTzs': 0,
  'payableTzs': 101500,
  // 22:30 UTC on the 5th is already the 6th in East Africa.
  'paidAt': '2026-10-05T22:30:00.000Z',
  'paymentReference': 'MPESA-QK7H2L9',
  'receiptUrl': null,
  'payoutAccountLast4': '4821',
};

const _detail = {
  'statement': _paid,
  'lines': [
    {
      'memberCode': 'FF-1001',
      'funding': 'pass',
      'visits': 5,
      'visitDates': ['2026-09-03', '2026-09-04', '2026-09-12'],
      'bracket': 'weekly',
      'earnedTzs': 70000,
      'networkAdjustmentTzs': 15000,
      'finalTzs': 55000,
    },
    {
      'memberCode': 'FF-1002',
      'funding': 'sponsored',
      'visits': 4,
      'visitDates': <String>[],
      'bracket': 'weekly',
      'earnedTzs': 50000,
      'networkAdjustmentTzs': 0,
      'finalTzs': 50000,
    },
  ],
  'adjustments': [
    {
      'amountTzs': -3500,
      'type': 'clawback',
      'reason': 'Visit voided after last month was paid',
    },
  ],
};

Widget _app(Widget home) => FFLocaleScope(
  notifier: FFLocale(),
  child: MaterialApp(home: home),
);

void main() {
  test('statement models parse the owner API', () {
    final detail = OwnerStatementDetail.fromJson(_detail);
    expect(detail.statement.monthLabel, 'September 2026');
    expect(detail.statement.isPaid, isTrue);
    expect(detail.statement.payableTzs, 101500);
    expect(detail.lines, hasLength(2));
    expect(detail.lines[1].sponsored, isTrue);
    expect(detail.adjustments.single.amountTzs, -3500);

    // Missing or odd values never throw.
    final bare = OwnerStatement.fromJson({'id': 'st-x'});
    expect(bare.monthLabel, 'st-x');
    expect(bare.status, 'preparing');
    expect(statementDay('2026-10-03'), '3 Oct');
    expect(statementDay('soon'), 'soon');
  });

  test('money taken off is shown with a minus sign', () {
    expect(signedCurrency(-3500), '−TZS 3,500');
    expect(signedCurrency(3500), 'TZS 3,500');
    expect(signedCurrency(0), 'TZS 0');
  });

  testWidgets('list card shows the month, status, hold and amount', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: OwnerStatementCard(
            statement: OwnerStatement.fromJson({
              ..._paid,
              'id': 'st-oct',
              'periodStartDate': '2026-10-01',
              'status': 'preparing',
              'onHold': true,
              'payableTzs': 105000,
            }),
            onTap: () => opened++,
          ),
        ),
      ),
    );
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Being prepared'), findsOneWidget);
    expect(find.text('On hold'), findsOneWidget);
    expect(find.text('TZS 105,000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('statement-st-oct')));
    expect(opened, 1);
  });

  testWidgets('a paid statement shows how it was worked out and paid', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        OwnerStatementPage(
          statementId: 'st-sep',
          load: (id) async => OwnerStatementDetail.fromJson(_detail),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('TZS 120,000'), findsOneWidget);
    expect(find.text('−TZS 15,000'), findsOneWidget);
    expect(find.text('TZS 101,500'), findsOneWidget);
    expect(find.text('6 Oct 2026'), findsOneWidget);
    expect(find.text('MPESA-QK7H2L9'), findsOneWidget);
    expect(find.text('····4821'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Visit voided after last month was paid'),
      200,
    );
    expect(find.text('Sponsored'), findsOneWidget);
    expect(find.text('3 Sep · 4 Sep · 12 Sep'), findsOneWidget);
    expect(find.text('Clawback'), findsOneWidget);
  });

  testWidgets('a statement that cannot be loaded says so', (tester) async {
    await tester.pumpWidget(
      _app(
        OwnerStatementPage(
          statementId: 'st-gone',
          load: (id) async => throw Exception('not found'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load this statement.'), findsOneWidget);
  });
}
