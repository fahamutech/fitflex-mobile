import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_api.dart';

void main() {
  apiTest('payment summary says the pass starts on approval, no dates', (
    tester,
    api,
  ) async {
    final data = MemberData()
      ..selectedTier = 'pro'
      ..passes = [PassTier(id: 'pro', price: 120000, visitCap: 12)];
    api.on('GET /payments/options', {'enabled': false});
    await pumpPage(
      tester,
      api,
      MemberDataScope(data: data, child: const MemberPaymentPage()),
      user: const {'id': 'm1', 'userType': 'member'},
    );

    // pumpPage is a 360 px phone: the sentence values wrap, no overflow.
    expect(tester.takeException(), isNull);
    expect(find.text('Starts when payment is approved'), findsOneWidget);
    // "From approval" is said once, on the start row.
    expect(find.text('30 days'), findsOneWidget);
    expect(find.textContaining('from approval'), findsNothing);
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
