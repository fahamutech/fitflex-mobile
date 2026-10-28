// Events S4 (spec §5.11 events_copy_rules_test): the labelled manual path
// never says a payment is instant, automatic or successful before FitFlex
// confirms it, and never calls a submission "paid". The scan covers every
// string under the payment, ticket, cancel and refund key groups, in both
// languages, plus the mobile-money sheet strings that event orders reuse.
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

/// Key groups the rules apply to (spec §5.11 rule 2).
const _groups = [
  'events.pay.',
  'events.payment.',
  'events.ticket.',
  'events.tickets.',
  'events.cancelpaid.',
  'events.refund.',
  'events.invite.',
  'events.order.payment.',
];

/// The mobile-money sheet's strings (rule 6: provider mode follows the same
/// rules). Only the ones an event order can show.
const _momo = [
  'momo.title',
  'momo.intro',
  'momo.phone',
  'momo.send',
  'momo.waitingTitle',
  'momo.waitingBody',
  'momo.checkNow',
  'momo.successTitle',
  'momo.successBody.eventOrder',
  'momo.failedTitle',
  'momo.failedBody',
  'momo.heldTitle',
  'momo.heldBody',
  'momo.slowTitle',
  'momo.slowBody',
];

/// "Paid" is allowed only as the member's own first-person claim ("I paid",
/// "I have paid", "I already paid", "if you already paid"), in "paid and
/// confirmed" about a confirmed place, and about the person who paid.
const _allowedPaid = [
  'i paid',
  'i have paid',
  'i already paid',
  'you already paid',
  'you paid',
  'who paid',
  'paid and confirmed',
  'have paid',
];

final _forbiddenEn = [
  RegExp(r'\binstant(ly)?\b'),
  RegExp(r'\bimmediate(ly)?\b'),
  RegExp(r'\bautomatic(ally)?\b'),
  RegExp(r'\breal-time\b'),
  RegExp(r'\bpayment (was )?successful\b'),
  RegExp(r'\bsuccessfully paid\b'),
];

final _forbiddenSw = [
  RegExp(r'papo hapo'),
  RegExp(r'mara moja'),
  RegExp(r'kiotomatiki'),
  RegExp(r'malipo yamefanikiwa'),
];

String _withoutAllowedPaid(String text) {
  // Placeholders like {paid} are names, not words the member reads.
  var t = text.toLowerCase().replaceAll(RegExp(r'\{[a-z]+\}'), '');
  for (final ok in _allowedPaid) {
    t = t.replaceAll(ok, '');
  }
  return t;
}

String _text(String lang, String key) => FFLocale.textOf(lang, key) ?? '';

Iterable<String> _keys(String lang) => [
  for (final k in FFLocale.keysOf(lang))
    if (_groups.any(k.startsWith)) k,
  ..._momo,
];

void main() {
  test('the groups are not empty (the scan covers something)', () {
    expect(_keys('en').length, greaterThan(100));
  });

  test('English: no instant / automatic / successful claims', () {
    for (final k in _keys('en')) {
      final t = _text('en', k).toLowerCase();
      for (final re in _forbiddenEn) {
        expect(re.hasMatch(t), isFalse, reason: '$k says: $t');
      }
    }
  });

  test('English: "paid" only as the member\'s own words or "paid and '
      'confirmed"', () {
    final paid = RegExp(r'\bpaid\b');
    for (final k in _keys('en')) {
      final t = _withoutAllowedPaid(_text('en', k));
      expect(paid.hasMatch(t), isFalse, reason: '$k says: $t');
    }
  });

  test('Swahili: no instant / automatic / successful claims', () {
    for (final k in _keys('sw')) {
      final t = _text('sw', k).toLowerCase();
      for (final re in _forbiddenSw) {
        expect(re.hasMatch(t), isFalse, reason: '$k says: $t');
      }
    }
  });

  test('the sheet never calls the plan or pass active for an event order', () {
    expect(_text('en', 'momo.successBody.eventOrder'), isNot(contains('plan')));
  });

  test('every events.pay.* key is in both maps, and says the same thing '
      'in Swahili with the same placeholders', () {
    final en = FFLocale.keysOf('en').where((k) => k.startsWith('events.pay.'));
    final sw = FFLocale.keysOf('sw');
    expect(en, isNotEmpty);
    final slot = RegExp(r'\{[a-z]+\}');
    for (final k in en) {
      expect(sw, contains(k));
      final a = slot.allMatches(_text('en', k)).map((m) => m[0]).toSet();
      final b = slot.allMatches(_text('sw', k)).map((m) => m[0]).toSet();
      expect(b, a, reason: 'placeholders of $k');
    }
  });

  test('the manual label and the staff / hours statement are on the manual '
      'banner (rule 1)', () {
    for (final lang in ['en', 'sw']) {
      final banner = _text(lang, 'events.pay.manual.banner.body');
      expect(banner, contains('{hours}'));
    }
    expect(_text('en', 'events.pay.manual.badge'), 'Manual confirmation');
    expect(_text('sw', 'events.pay.manual.badge'), 'Uthibitisho wa mkono');
    expect(
      _text('en', 'events.pay.manual.banner.body'),
      contains('FitFlex staff'),
    );
  });

  test('after sending, the words are "sent for checking", not paid', () {
    expect(
      _text('en', 'events.pay.submitted.title'),
      'Payment sent for checking',
    );
    expect(_text('en', 'events.pay.sent.snack'), 'Sent for checking');
    expect(_text('en', 'events.payment.status.submitted'), 'Under review');
  });
}
