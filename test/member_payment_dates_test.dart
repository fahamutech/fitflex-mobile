import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('payment summary says the pass starts on approval, no dates', (
    tester,
  ) async {
    final data = MemberData()
      ..selectedTier = 'pro'
      ..passes = [PassTier(id: 'pro', price: 120000, visitCap: 12)];
    // A narrow phone: the sentence values must wrap, not overflow.
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
          home: MemberDataScope(data: data, child: const MemberPaymentPage()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Starts when payment is approved'), findsOneWidget);
    expect(find.text('Lasts 30 days from approval'), findsOneWidget);
    expect(find.text('End date'), findsNothing);
    expect(find.text('Total to pay'), findsOneWidget);
    expect(find.text('Total'), findsNothing);
    // No calendar date is promised before approval.
    final year = '${DateTime.now().year}';
    expect(find.textContaining(year), findsNothing);
  });

  test('payment-summary lines have their own Swahili', () {
    for (final k in const [
      'member.passStartsOnApproval',
      'member.passLength',
      'member.passLastsFromApproval',
      'pass.state.pendingPurchase',
      'pass.state.pendingPurchaseAny',
    ]) {
      expect(FFLocale.textOf('en', k), isNotNull, reason: k);
      expect(FFLocale.textOf('sw', k), isNotNull, reason: k);
      expect(FFLocale.textOf('sw', k), isNot(FFLocale.textOf('en', k)));
    }
    expect(
      FFLocale.textOf('sw', 'member.passLastsFromApproval'),
      contains('{days}'),
    );
    expect(
      FFLocale.textOf('sw', 'pass.state.pendingPurchase'),
      contains('{tier}'),
    );
  });
}
