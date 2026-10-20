// My wellness benefits: the member sees what a sponsor gives them, how much
// is used and what is left. Every number comes from the server.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_benefits_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/widgets/verify_identifier.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this.benefits) : super(baseUrl: 'http://localhost:0');

  List<Map<String, dynamic>> benefits;
  bool fail = false;
  final unlocked = <String>[];
  int loads = 0;

  // Identifier verification (Identity V2) and /auth/options.
  bool identifiersOn = true;
  bool emailCodes = true;
  List<Map<String, dynamic>> verified = [];

  @override
  Future<Map<String, dynamic>> signInOptions() async => {
    'pinLogin': true,
    'pinReset': false,
    'smsCodes': true,
    'emailCodes': emailCodes,
  };

  @override
  Future<Map<String, dynamic>> myIdentifiers() async {
    if (!identifiersOn) throw ApiException(404, {'error': 'not_found'});
    return {'identifiers': verified, 'unverified': const []};
  }

  @override
  Future<Map<String, dynamic>> myInvitations() async =>
      throw ApiException(404, {'error': 'not_found'});

  @override
  Future<Map<String, dynamic>> myWellnessBenefits() async {
    loads += 1;
    if (fail) throw ApiException(500, 'server_error');
    return {'benefits': benefits, 'asOf': '2026-10-05'};
  }

  @override
  Future<Map<String, dynamic>> unlockSponsoredPass(String entitlementId) async {
    unlocked.add(entitlementId);
    for (final b in benefits) {
      final pass = b['pass'] as Map<String, dynamic>?;
      if (pass?['entitlementId'] == entitlementId) {
        pass!['paymentPending'] = true;
      }
    }
    return {};
  }
}

Map<String, dynamic> _benefit({
  String id = 'b2bf_1',
  String name = '8 gym visits a month',
  String type = 'gym_access',
  String fundingType = 'full',
  int? usageLimit = 8,
  String usagePeriod = 'month',
  int used = 3,
  int? remaining = 5,
  Map<String, dynamic> funding = const {},
  String? endDate = '2026-10-31',
}) => {
  'organization': {
    'id': 'o1',
    'name': 'ABC Company',
    'organizationType': 'employer',
  },
  'program': {
    'id': 'p1',
    'name': 'ABC Wellness',
    'startDate': '2026-01-01',
    'endDate': endDate,
  },
  'benefit': {
    'id': id,
    'name': name,
    'benefitType': type,
    'fundingType': fundingType,
    'usageLimit': usageLimit,
    'usagePeriod': usagePeriod,
    'validity': {'startDate': '2026-01-01', 'endDate': endDate},
    ...funding,
  },
  'used': used,
  'remaining': remaining,
};

Widget _app(_FakeApi api) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale(),
    child: const MaterialApp(home: MemberBenefitsPage()),
  ),
);

/// A signed-in member whose identifier verification state comes from [api].
Future<AuthState> _signedIn(_FakeApi api) async {
  final auth = AuthState(api);
  await auth.loadSignInOptions();
  await auth.signIn('jwt-member', {
    'id': 'usr_member',
    'userType': 'member',
    'approvalStatus': 'approved',
  });
  await auth.refreshIdentifiers();
  return auth;
}

Widget _signedInApp(AuthState auth, {String lang = 'en'}) => AppScope(
  api: auth.api,
  auth: auth,
  child: FFLocaleScope(
    notifier: FFLocale()..set(Locale(lang)),
    child: const MaterialApp(home: MemberBenefitsPage()),
  ),
);

const _hint = Key('benefits-confirm-contact');
const _hintAction = Key('benefits-confirm-contact-action');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows allowance used and left, who pays and validity', (
    tester,
  ) async {
    final api = _FakeApi([
      _benefit(),
      _benefit(
        id: 'b2bf_2',
        name: 'Trainer sessions at 60%',
        type: 'trainer_session',
        fundingType: 'sponsor_percentage',
        funding: {'sponsorShareBps': 6000},
        usageLimit: null,
        usagePeriod: 'unlimited',
        used: 2,
        remaining: null,
        endDate: null,
      ),
    ]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('ABC Company · ABC Wellness'), findsNWidgets(2));
    expect(find.text('8 gym visits a month'), findsOneWidget);
    expect(find.text('Used 3 of 8 this month'), findsOneWidget);
    expect(find.text('5 left'), findsOneWidget);
    expect(find.text('Your sponsor pays in full'), findsOneWidget);
    expect(find.text('Valid until 2026-10-31'), findsOneWidget);

    // The member is told what the sponsor can and cannot see.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('benefits-visibility')),
      200,
    );
    expect(find.text('What your sponsor can see'), findsOneWidget);
    expect(
      find.textContaining('cannot see your weight, height'),
      findsOneWidget,
    );

    expect(find.text('No limit on how often you use it'), findsOneWidget);
    expect(
      find.text('Your sponsor pays 60%; you pay the rest'),
      findsOneWidget,
    );
    expect(find.text('No end date'), findsOneWidget);
  });

  testWidgets('a member with no sponsor sees an explanation, not an error', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeApi([])));
    await tester.pumpAndSettle();
    expect(find.text('No wellness benefits yet'), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    final api = _FakeApi([_benefit()])..fail = true;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('8 gym visits a month'), findsNothing);
    api.fail = false;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('5 left'), findsOneWidget);
  });

  testWidgets('a sponsored pass is unlocked by paying the member share once', (
    tester,
  ) async {
    final pass = _benefit(
      id: 'b2bf_pass',
      name: 'Pro pass',
      type: 'sponsored_pass',
      fundingType: 'sponsor_percentage',
      funding: {'sponsorShareBps': 7000, 'passTier': 'pro'},
      usageLimit: null,
      usagePeriod: 'unlimited',
      used: 0,
      remaining: null,
    );
    pass['pass'] = <String, dynamic>{
      'entitlementId': 'b2be_1',
      'status': 'awaiting_member',
      'memberTzs': 45000,
      'canUnlock': true,
      'paymentPending': false,
    };
    final api = _FakeApi([pass]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('Sponsored pass'), findsOneWidget);
    expect(find.text('Unlock for TSh 45,000'), findsOneWidget);
    expect(find.text('No limit on how often you use it'), findsNothing);

    await tester.tap(find.byKey(const Key('unlock-b2be_1')));
    await tester.pumpAndSettle();
    expect(api.unlocked, ['b2be_1']);
    expect(find.byKey(const Key('unlock-b2be_1')), findsNothing);
    expect(
      find.text(
        'Payment requested. Your pass starts when FitFlex confirms it.',
      ),
      findsWidgets,
    );

    // Once the payment is confirmed the pass simply shows as running.
    (pass['pass'] as Map<String, dynamic>)['status'] = 'active';
    await tester.pumpWidget(_app(_FakeApi([pass])));
    await tester.pumpAndSettle();
    expect(
      find.text('Your pass is running until the end of the month'),
      findsOneWidget,
    );
  });

  group('confirm-contact hint on the empty state', () {
    testWidgets('shows when identifier verification is on', (tester) async {
      final api = _FakeApi([]);
      final auth = await _signedIn(api);
      await tester.pumpWidget(_signedInApp(auth));
      await tester.pumpAndSettle();

      expect(find.text('No wellness benefits yet'), findsOneWidget);
      expect(find.byKey(_hint), findsOneWidget);
      expect(
        find.text('Expecting benefits from your employer?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your benefits are added once you confirm the email or mobile number your organisation has for you.',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm email or number'), findsOneWidget);
      // It never claims an invite exists.
      expect(find.textContaining('invit'), findsNothing);
    });

    testWidgets('says mobile number only while email codes are off', (
      tester,
    ) async {
      final api = _FakeApi([])..emailCodes = false;
      final auth = await _signedIn(api);
      await tester.pumpWidget(_signedInApp(auth));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your benefits are added once you confirm the mobile number your organisation has for you.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('the email or mobile'), findsNothing);
    });

    testWidgets('is hidden while identifier verification is off', (
      tester,
    ) async {
      final api = _FakeApi([])..identifiersOn = false;
      final auth = await _signedIn(api);
      await tester.pumpWidget(_signedInApp(auth));
      await tester.pumpAndSettle();

      expect(find.text('No wellness benefits yet'), findsOneWidget);
      expect(find.byKey(_hint), findsNothing);
    });

    testWidgets('is not shown when the member already has benefits', (
      tester,
    ) async {
      final api = _FakeApi([_benefit()]);
      final auth = await _signedIn(api);
      await tester.pumpWidget(_signedInApp(auth));
      await tester.pumpAndSettle();
      expect(find.byKey(_hint), findsNothing);
    });

    testWidgets('opens Contact details; a new verification reloads benefits', (
      tester,
    ) async {
      final api = _FakeApi([]);
      final auth = await _signedIn(api);
      await tester.pumpWidget(_signedInApp(auth));
      await tester.pumpAndSettle();
      expect(api.loads, 1);

      await tester.tap(find.byKey(_hintAction));
      await tester.pumpAndSettle();
      expect(find.byType(ContactDetailsScreen), findsOneWidget);

      // Coming back without verifying anything does not reload.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.loads, 1);

      await tester.tap(find.byKey(_hintAction));
      await tester.pumpAndSettle();
      // The member verifies the number their employer listed; the backend
      // then attaches the sponsored benefit.
      api.verified = [
        {'type': 'phone', 'value': '+255712345678'},
      ];
      api.benefits = [_benefit()];
      await auth.refreshIdentifiers();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(api.loads, 2);
      expect(find.text('8 gym visits a month'), findsOneWidget);
      expect(find.byKey(_hint), findsNothing);
    });

    testWidgets('Swahili fits a small phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _FakeApi([]);
      final auth = await _signedIn(api);
      await tester.pumpWidget(_signedInApp(auth, lang: 'sw'));
      await tester.pumpAndSettle();

      expect(
        find.text('Unatarajia manufaa kutoka kwa mwajiri wako?'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.byKey(_hintAction), 100);
      expect(find.text('Thibitisha barua pepe au namba'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('every confirm-contact string exists in English and Swahili', () {
      const keys = [
        'benefits.confirmContact.title',
        'benefits.confirmContact.body',
        'benefits.confirmContact.bodyPhoneOnly',
        'benefits.confirmContact.action',
      ];
      final en = FFLocale.keysOf('en');
      final sw = FFLocale.keysOf('sw');
      for (final k in keys) {
        expect(en, contains(k), reason: 'en: $k');
        expect(sw, contains(k), reason: 'sw: $k');
        expect(
          FFLocale.textOf('sw', k),
          isNot(FFLocale.textOf('en', k)),
          reason: 'sw copies English: $k',
        );
      }
    });
  });
}
