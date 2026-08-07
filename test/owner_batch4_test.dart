// Batch 4 (B1/B2/B4) — owner ops: invoice month ordering, add-member
// credential fields, tappable member stats, days-left on rows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/screens/owner/widgets/invoice_utils.dart';
import 'package:fitflexmobile/screens/owner/members/data/member_models.dart';
import 'package:fitflexmobile/screens/owner/members/widgets/member_list_tile.dart';

Widget _wrap(Widget child) {
  final locale = FFLocale();
  return FFLocaleScope(
    notifier: locale,
    child: MaterialApp(
      theme: buildTheme(),
      supportedLocales: const [Locale('en'), Locale('sw')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}

OwnerInvoice _invoice(
  String id, {
  String? periodStart,
  String status = 'unpaid',
}) => OwnerInvoice.fromJson({
  'id': id,
  'gymId': 'gym_1',
  'gymName': 'Gym One',
  'amount': 10000,
  'status': status,
  'periodStart': periodStart,
});

void main() {
  group('B1 — invoice month ordering', () {
    test('sorts invoices from the current month backwards', () {
      final rows = sortInvoicesCurrentMonthBackwards([
        _invoice('feb', periodStart: '2026-02-01'),
        _invoice('jul', periodStart: '2026-07-01'),
        _invoice('mar', periodStart: '2026-03-01'),
      ]);
      expect(rows.map((i) => i.id), ['jul', 'mar', 'feb']);
    });

    test('undated invoices sink to the end', () {
      final rows = sortInvoicesCurrentMonthBackwards([
        _invoice('undated'),
        _invoice('jun', periodStart: '2026-06-01'),
      ]);
      expect(rows.map((i) => i.id), ['jun', 'undated']);
    });

    test('month label renders from periodStart', () {
      expect(_invoice('x', periodStart: '2026-03-01').monthLabel, 'March 2026');
    });
  });

  group('B4 — member row shows days remaining', () {
    OwnerMember member({required String status, int? daysLeft}) =>
        OwnerMember.fromJson({
          'id': 'usr_1',
          'publicId': 'FF-0001',
          'displayName': 'Amina Said',
          'memberType': 'direct',
          'tier': 'basic',
          'status': status,
          'daysLeft': daysLeft,
        });

    testWidgets('expiring-soon rows show days left', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MemberListTile(
            member: member(status: 'expiring_soon', daysLeft: 3),
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('3 days left'), findsOneWidget);
    });

    testWidgets('expired rows show how long ago they expired', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MemberListTile(
            member: member(status: 'expired', daysLeft: -5),
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('Expired 5 days ago'), findsOneWidget);
    });

    testWidgets('active rows show no day counter', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MemberListTile(
            member: member(status: 'active', daysLeft: 20),
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('days left'), findsNothing);
    });
  });
}
