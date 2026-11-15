// Custom Gym Passes (phase 4): label fix, flag off, plan list, buy flow
// people limits, error mapping, my passes, claim.
//
// Contract: docs/custom-gym-passes-api.md in fitflex-functions (PR #355).

import 'package:fitflexmobile/screens/member/gym_passes/gym_pass_buy_sheet.dart';
import 'package:fitflexmobile/screens/member/gym_passes/gym_pass_plans_section.dart';
import 'package:fitflexmobile/screens/member/gym_passes/member_gym_passes_page.dart';
import 'package:fitflexmobile/screens/member/widgets/membership_card.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/gym_passes/gym_pass.dart';
import 'package:fitflexmobile/shared/gym_passes/gym_passes_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_api.dart';

Gym _gym() => Gym.fromJson({
  'id': 'gym_1',
  'name': 'Test Gym',
  'tier': 'standard',
  'location': 'Dar es Salaam',
  'perVisitRate': 5000,
  'status': 'active',
});

Map<String, dynamic> _plan(
  String id,
  String category, {
  int limit = 1,
  num price = 90000,
  String? terms,
}) => {
  'id': id,
  'gymId': 'gym_1',
  'name': 'Plan $id',
  'description': null,
  'category': category,
  'durationValue': 3,
  'durationUnit': 'months',
  'beneficiaryLimit': limit,
  'priceTzs': price,
  'currency': 'TZS',
  'startPolicy': 'immediate',
  'terms': terms,
  'termsVersion': 1,
};

GymPassPlan _p(String category, {int limit = 1}) =>
    GymPassPlan.fromJson(_plan('x', category, limit: limit))!;

// English is the default; no preferences are touched when a file is loaded.
FFLocale _en() => FFLocale();
FFLocale _sw() => FFLocale()..set(const Locale('sw'));

ApiException _err(int status, Map<String, dynamic> body) =>
    ApiException(status, body);

Widget _wrap(Widget child) => FFLocaleScope(
  notifier: FFLocale(),
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

/// Opens the buy sheet the way the app does (a modal bottom sheet), so a
/// finished purchase can pop it.
Future<PageHost> _pumpSheet(
  WidgetTester tester,
  RecordingApi api,
  GymPassPlan plan, {
  Future<bool> Function(BuildContext, String?, num)? payOverride,
}) async {
  final host = await pumpPage(
    tester,
    api,
    Builder(
      builder: (context) => TextButton(
        key: const Key('open-sheet'),
        onPressed: () => showGymPassBuySheet(
          context,
          gym: _gym(),
          plan: plan,
          payOverride: payOverride,
        ),
        child: const Text('open'),
      ),
    ),
    user: const {'id': 'm1', 'userType': 'member'},
    size: const Size(400, 1600),
  );
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
  api.clear();
  return host;
}

final _mine = <String, dynamic>{
  'purchased': [
    {
      'id': 'gpp_1',
      'status': 'active',
      'gym': {'id': 'gym_1', 'name': 'Test Gym'},
      'plan': {
        'name': 'Group 3 months',
        'category': 'group',
        'beneficiaryLimit': 4,
      },
      'payment': {'status': 'approved', 'amountTzs': 400000},
      'startsAt': '2027-01-01T00:00:00.000Z',
      'expiresAt': '2027-04-01T00:00:00.000Z',
      'slots': {'used': 3, 'limit': 4},
      'beneficiaries': [
        {
          'id': 'b1',
          'slot': 1,
          'isPurchaser': true,
          'status': 'active',
          'you': true,
          'displayName': 'Amina',
        },
        {
          'id': 'b2',
          'slot': 2,
          'isPurchaser': false,
          'status': 'invited',
          'you': false,
          'displayName': null,
          'contact': '+255 7** *** 678',
        },
        {
          'id': 'b3',
          'slot': 3,
          'isPurchaser': false,
          'status': 'suspended',
          'you': false,
          'displayName': 'J. K.',
        },
        {
          'id': 'b4',
          'slot': 4,
          'isPurchaser': false,
          'status': 'removed',
          'you': false,
        },
      ],
    },
  ],
  'memberships': [
    {
      'purchaseId': 'gpp_9',
      'beneficiaryId': 'b9',
      'status': 'active',
      'purchaseStatus': 'active',
      'gym': {'id': 'gym_2', 'name': 'Other Gym'},
      'plan': {'name': 'Couples 1 month', 'category': 'couples'},
      'startsAt': '2027-01-01T00:00:00.000Z',
      'expiresAt': '2027-02-01T00:00:00.000Z',
      'subscriptionId': 'sub_9',
    },
  ],
};

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugGymCustomPassesOverride = null);

  group('label fix (plan ?? monthly)', () {
    test('a legacy direct row reads exactly as before', () {
      final en = _en();
      expect(
        directSubscriptionLabel(en, plan: 'daily', passPurchaseId: null),
        'Daily plan',
      );
      expect(
        directSubscriptionLabel(en, plan: 'weekly', passPurchaseId: null),
        'Weekly plan',
      );
      expect(
        directSubscriptionLabel(en, plan: 'monthly', passPurchaseId: null),
        'Monthly plan',
      );
      // The old fallback for a legacy row with no plan stays.
      expect(
        directSubscriptionLabel(en, plan: null, passPurchaseId: null),
        'Monthly plan',
      );
      // An empty id is not a pass.
      expect(
        directSubscriptionLabel(en, plan: null, passPurchaseId: ''),
        'Monthly plan',
      );
      expect(
        directSubscriptionLabel(_sw(), plan: 'daily', passPurchaseId: null),
        _sw().t('member.plan_daily'),
      );
    });

    test('a pass row is a gym pass, never Monthly', () {
      expect(
        directSubscriptionLabel(_en(), plan: null, passPurchaseId: 'gpp_1'),
        'Gym pass',
      );
      expect(
        directSubscriptionLabel(
          _en(),
          plan: null,
          passPurchaseId: 'gpp_1',
          passName: 'Couples 3 months',
        ),
        'Couples 3 months',
      );
    });

    test('Subscription reads passPurchaseId', () {
      final pass = Subscription.fromJson({
        'type': 'direct_sub',
        'status': 'active',
        'passPurchaseId': 'gpp_1',
      });
      expect(pass.isGymPass, isTrue);
      expect(pass.directLabel(_en()), 'Gym pass');
      final legacy = Subscription.fromJson({
        'type': 'direct_sub',
        'plan': 'weekly',
        'status': 'active',
      });
      expect(legacy.isGymPass, isFalse);
      expect(legacy.directLabel(_en()), 'Weekly plan');
    });

    testWidgets('MembershipCard: pass says Gym pass, legacy unchanged', (
      tester,
    ) async {
      Subscription sub(Map<String, dynamic> extra) => Subscription.fromJson({
        'type': 'direct_sub',
        'status': 'active',
        'expiresAt': DateTime.now()
            .add(const Duration(days: 20))
            .toIso8601String(),
        'homeGymId': 'gym_1',
        ...extra,
      });
      await tester.pumpWidget(
        _wrap(MembershipCard(subscription: sub({'passPurchaseId': 'gpp_1'}))),
      );
      expect(find.text('Gym pass'), findsOneWidget);
      expect(find.text('Monthly plan'), findsNothing);

      await tester.pumpWidget(
        _wrap(MembershipCard(subscription: sub({'plan': 'monthly'}))),
      );
      expect(find.text('Monthly plan'), findsOneWidget);
      expect(find.text('Gym pass'), findsNothing);

      // No plan and no pass: the old fallback.
      await tester.pumpWidget(_wrap(MembershipCard(subscription: sub({}))));
      expect(find.text('Monthly plan'), findsOneWidget);
    });
  });

  group('flag and availability', () {
    test('off by default in the build', () {
      expect(kGymCustomPasses, isFalse);
      expect(gymCustomPassesEnabled, isFalse);
    });

    test('404 feature_disabled is "not available"', () {
      expect(
        isGymPassesUnavailable(_err(404, {'error': 'feature_disabled'})),
        isTrue,
      );
      expect(
        isGymPassesUnavailable(_err(404, {'error': 'not_found'})),
        isFalse,
      );
      expect(
        isGymPassesUnavailable(_err(500, {'error': 'feature_disabled'})),
        isFalse,
      );
    });

    apiTest('flag off: no section and no request', (tester, api) async {
      api.on('GET /gyms/gym_1/pass-plans', {
        'plans': [_plan('a', 'individual')],
      });
      await pumpPage(
        tester,
        api,
        GymPassPlansSection(gym: _gym()),
        user: const {'id': 'm1', 'userType': 'member'},
      );
      expect(find.byKey(const Key('gym-section-pass-plans')), findsNothing);
      expect(api.requests, isEmpty);
    });

    apiTest('flag on, server says feature_disabled: nothing shows', (
      tester,
      api,
    ) async {
      debugGymCustomPassesOverride = true;
      api.fail('GET /gyms/gym_1/pass-plans', 404, {
        'error': 'feature_disabled',
      });
      await pumpPage(
        tester,
        api,
        GymPassPlansSection(gym: _gym()),
        user: const {'id': 'm1', 'userType': 'member'},
        keepRequests: true,
      );
      expect(find.byKey(const Key('gym-section-pass-plans')), findsNothing);
      expect(api.sent('GET', '/gyms/gym_1/pass-plans'), isTrue);
    });

    apiTest('flag on, no custom plans: nothing shows', (tester, api) async {
      debugGymCustomPassesOverride = true;
      api.on('GET /gyms/gym_1/pass-plans', {'gymId': 'gym_1', 'plans': []});
      await pumpPage(
        tester,
        api,
        GymPassPlansSection(gym: _gym()),
        user: const {'id': 'm1', 'userType': 'member'},
      );
      expect(find.byKey(const Key('gym-section-pass-plans')), findsNothing);
    });
  });

  group('plan list', () {
    apiTest('lists plans with category, duration and the server price', (
      tester,
      api,
    ) async {
      debugGymCustomPassesOverride = true;
      api.on('GET /gyms/gym_1/pass-plans', {
        'gymId': 'gym_1',
        'plans': [
          _plan('a', 'individual', price: 90000),
          _plan('b', 'couples', limit: 2, price: 150000),
          _plan('c', 'group', limit: 6, price: 400000),
          {'id': 'broken'},
        ],
      });
      await pumpPage(
        tester,
        api,
        SingleChildScrollView(child: GymPassPlansSection(gym: _gym())),
        user: const {'id': 'm1', 'userType': 'member'},
      );
      expect(find.text('Gym Membership Plans'), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-plan-a')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-plan-b')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-plan-c')), findsOneWidget);
      // A row the app cannot read is left out, not guessed.
      expect(find.byKey(const Key('gym-pass-plan-broken')), findsNothing);
      expect(find.text('Individual (1 person)'), findsOneWidget);
      expect(find.text('Couples (2 people)'), findsOneWidget);
      expect(find.text('Group (up to 6 people)'), findsOneWidget);
      expect(find.text('3 months'), findsNWidgets(3));
      expect(find.textContaining('90,000'), findsOneWidget);
      expect(find.textContaining('150,000'), findsOneWidget);
    });
  });

  group('people limits', () {
    test('individual takes nobody else', () {
      final p = _p('individual');
      expect(p.takesOthers, isFalse);
      expect(p.minOthers, 0);
      expect(p.maxOthers, 0);
      String tr(String k) => k;
      expect(gymPassPeopleProblem(p, const [], tr), isNull);
      expect(gymPassPeopleProblem(p, const ['0712345678'], tr), isNotNull);
    });

    test('couples needs exactly one other', () {
      final p = _p('couples', limit: 2);
      expect([p.minOthers, p.maxOthers], [1, 1]);
      String tr(String k) => k;
      expect(gymPassPeopleProblem(p, const [], tr), 'gymPass.error.headcount');
      expect(gymPassPeopleProblem(p, const ['0712345678'], tr), isNull);
      expect(
        gymPassPeopleProblem(p, const ['0712345678', 'a@b.co'], tr),
        'gymPass.error.headcount',
      );
    });

    test('group: two up to limit minus one', () {
      final p = _p('group', limit: 5);
      expect([p.minOthers, p.maxOthers], [2, 4]);
      String tr(String k) => k;
      expect(
        gymPassPeopleProblem(p, const ['0712345678'], tr),
        'gymPass.error.headcount',
      );
      expect(
        gymPassPeopleProblem(p, const ['0712345678', 'a@b.co'], tr),
        isNull,
      );
      expect(
        gymPassPeopleProblem(p, const [
          '0712345678',
          'a@b.co',
          'c@d.co',
          'e@f.co',
          'g@h.co',
        ], tr),
        'gymPass.error.headcount',
      );
    });

    test('the same contact twice, or a bad contact, is refused', () {
      final p = _p('group', limit: 4);
      String tr(String k) => k;
      expect(
        gymPassPeopleProblem(p, const ['0712345678', '+255712345678'], tr),
        'gymPass.error.contactProblem',
      );
      expect(
        gymPassPeopleProblem(p, const ['A@B.co', 'a@b.co'], tr),
        'gymPass.error.contactProblem',
      );
      expect(
        gymPassPeopleProblem(p, const ['0712345678', 'nope'], tr),
        'gymPass.error.contactProblem',
      );
      // A blank box in the list is a problem too.
      expect(
        gymPassPeopleProblem(p, const ['0712345678', 'a@b.co', ''], tr),
        'gymPass.error.contactProblem',
      );
    });

    test('contacts are sent as phone or email, never ids', () {
      expect(gymPassContactBody('a@b.co'), {'email': 'a@b.co'});
      expect(gymPassContactBody(' 0712 345 678 '), {'phone': '0712345678'});
      expect(gymPassContactBody('abc'), isNull);
      expect(gymPassContactBody(''), isNull);
    });

    apiTest('couples sheet: one box, no "add another", price from server', (
      tester,
      api,
    ) async {
      final plan = GymPassPlan.fromJson(
        _plan('b', 'couples', limit: 2, price: 150000),
      )!;
      await _pumpSheet(tester, api, plan);
      expect(find.byKey(const Key('gym-pass-person-0')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-person-1')), findsNothing);
      expect(find.byKey(const Key('gym-pass-add-person')), findsNothing);
      expect(find.byKey(const Key('gym-pass-covers-you')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-notify-note')), findsOneWidget);
      expect(find.textContaining('150,000'), findsWidgets);
    });

    apiTest('group sheet: starts at 2 boxes, grows to the limit', (
      tester,
      api,
    ) async {
      final plan = GymPassPlan.fromJson(_plan('c', 'group', limit: 4))!;
      await _pumpSheet(tester, api, plan);
      expect(find.byKey(const Key('gym-pass-person-0')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-person-1')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-person-2')), findsNothing);
      await tester.tap(find.byKey(const Key('gym-pass-add-person')));
      await tester.pump();
      expect(find.byKey(const Key('gym-pass-person-2')), findsOneWidget);
      // 4 people with the buyer = 3 boxes: no more.
      expect(find.byKey(const Key('gym-pass-add-person')), findsNothing);
      // The first two cannot be removed (the plan needs them), the third can.
      expect(find.byKey(const Key('gym-pass-person-remove-0')), findsNothing);
      expect(find.byKey(const Key('gym-pass-person-remove-2')), findsOneWidget);
    });

    apiTest('a wrong headcount sends nothing', (tester, api) async {
      final plan = GymPassPlan.fromJson(_plan('b', 'couples', limit: 2))!;
      await _pumpSheet(tester, api, plan);
      api.clear();
      await tester.tap(find.byKey(const Key('gym-pass-buy')));
      await tester.pumpAndSettle();
      expect(api.sent('POST', '/me/gym-pass-purchases'), isFalse);
    });

    apiTest('buying sends the plan and contacts, once, with no price', (
      tester,
      api,
    ) async {
      final held = api.hold('POST /me/gym-pass-purchases');
      api.on('POST /me/gym-pass-purchases', {
        'purchase': {'id': 'gpp_1', 'status': 'pending_payment'},
        'paymentRequest': {'id': 'pay_1', 'amountTzs': 150000},
      });
      final plan = GymPassPlan.fromJson(_plan('b', 'couples', limit: 2))!;
      await _pumpSheet(tester, api, plan);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('gym-pass-person-0')),
          matching: find.byType(EditableText),
        ),
        '0712 345 678',
      );
      await tester.tap(find.byKey(const Key('gym-pass-buy')));
      await tester.pump();
      // A second tap while the first is in flight does nothing.
      await tester.tap(
        find.byKey(const Key('gym-pass-buy')),
        warnIfMissed: false,
      );
      await tester.pump();
      held.complete();
      await tester.pump(const Duration(milliseconds: 50));
      final sent = api.where('POST', '/me/gym-pass-purchases');
      expect(sent, hasLength(1));
      final body = sent.single.body as Map;
      expect(body['planId'], 'b');
      expect(body['beneficiaries'], [
        {'phone': '0712345678'},
      ]);
      expect(body.containsKey('priceTzs'), isFalse);
      expect(body.containsKey('amountTzs'), isFalse);
    });

    apiTest('terms: needs the box ticked, then sends the version', (
      tester,
      api,
    ) async {
      api.on('POST /me/gym-pass-purchases', {
        'purchase': {'id': 'gpp_1'},
        'paymentRequest': {'id': 'pay_1', 'amountTzs': 90000},
      });
      final plan = GymPassPlan.fromJson(
        _plan('a', 'individual', terms: 'No refunds.'),
      )!;
      await _pumpSheet(tester, api, plan);
      await tester.tap(find.byKey(const Key('gym-pass-buy')));
      await tester.pumpAndSettle();
      expect(api.sent('POST', '/me/gym-pass-purchases'), isFalse);
      expect(find.text('Accept the terms to continue.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gym-pass-terms')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('gym-pass-buy')));
      await tester.pump(const Duration(milliseconds: 50));
      final body = api.only('POST', '/me/gym-pass-purchases').body as Map;
      expect(body['termsVersion'], 1);
      expect(body.containsKey('beneficiaries'), isFalse);
    });

    apiTest('invalid_beneficiaries shows the generic message only', (
      tester,
      api,
    ) async {
      api.fail('POST /me/gym-pass-purchases', 400, {
        'error': 'invalid_beneficiaries',
      });
      final plan = GymPassPlan.fromJson(_plan('b', 'couples', limit: 2))!;
      await _pumpSheet(tester, api, plan);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('gym-pass-person-0')),
          matching: find.byType(EditableText),
        ),
        'someone@example.com',
      );
      await tester.tap(find.byKey(const Key('gym-pass-buy')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('gym-pass-error')),
          matching: find.textContaining("can't be added to this pass"),
        ),
        findsOneWidget,
      );
      // The same sheet can be used again after a refusal.
      expect(find.byKey(const Key('gym-pass-buy')), findsOneWidget);
    });
  });

  group('error mapping', () {
    final en = _en();
    String msg(ApiException e) => gymPassErrorMessage(en, e, errorMessage);

    test('invalid_beneficiaries is generic and names no one', () {
      final m = msg(_err(400, {'error': 'invalid_beneficiaries'}));
      expect(m, en.t('gymPass.error.invalidBeneficiaries'));
      expect(m.toLowerCase(), isNot(contains('account')));
      expect(m.toLowerCase(), isNot(contains('member')));
    });

    test('429 rate_limited says how long', () {
      expect(
        msg(_err(429, {'error': 'rate_limited', 'retryAfterSeconds': 45})),
        'Too many attempts. Try again in 45 seconds.',
      );
      expect(
        msg(_err(429, {'error': 'rate_limited', 'retryAfterSeconds': 3600})),
        'Too many attempts. Try again in 60 minutes.',
      );
      expect(
        msg(_err(429, {'error': 'rate_limited'})),
        en.t('gymPass.error.rateLimited'),
      );
    });

    test('409 cannot_add_person is its own message', () {
      expect(
        msg(_err(409, {'error': 'cannot_add_person'})),
        en.t('gymPass.error.cannotAddPerson'),
      );
    });

    test('the rest of the contract codes are mapped', () {
      for (final (code, key) in [
        ('removed_by_owner', 'removedByOwner'),
        ('suspended_by_other', 'suspendedByOther'),
        ('replacement_limit_reached', 'replacementLimit'),
        ('beneficiary_limit_exceeded', 'limitExceeded'),
        ('duplicate_beneficiary', 'contactProblem'),
        ('cannot_add_yourself', 'contactProblem'),
        ('invalid_contact', 'contactProblem'),
        ('couples_needs_two_people', 'headcount'),
        ('group_needs_minimum', 'headcount'),
        ('beneficiaries_not_allowed', 'headcount'),
        ('plan_not_available', 'planUnavailable'),
        ('terms_changed', 'termsChanged'),
        ('payment_already_pending', 'paymentPending'),
        ('too_soon', 'tooSoon'),
        ('cannot_remove_purchaser', 'cannotRemoveBuyer'),
        ('feature_disabled', 'unavailable'),
      ]) {
        expect(
          msg(_err(409, {'error': code})),
          en.t('gymPass.error.$key'),
          reason: code,
        );
      }
    });

    test('anything else falls back to the shared message', () {
      expect(
        msg(_err(403, {'error': 'some_other_code'})),
        errorMessage(en, _err(403, {'error': 'some_other_code'})),
      );
    });
  });

  group('my passes', () {
    final mine = _mine;

    test('parses purchased and memberships', () {
      final m = GymPassesMine.fromJson(mine);
      expect(m.purchased.single.onPass.map((p) => p.id), ['b1', 'b2', 'b3']);
      expect(m.purchased.single.canAddPerson, isTrue);
      expect(m.memberships.single.isRunning, isTrue);
      expect(GymPassesMine.fromJson(const {}).isEmpty, isTrue);
    });

    apiTest('shows each person, the shared expiry, QR and leave', (
      tester,
      api,
    ) async {
      api.on('GET /me/gym-passes', mine);
      await pumpPage(
        tester,
        api,
        const MemberGymPassesPage(),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(400, 1600),
      );
      expect(find.text('Group 3 months'), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-person-row-b1')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-person-row-b2')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-person-row-b3')), findsOneWidget);
      // A removed person is off the list.
      expect(find.byKey(const Key('gym-pass-person-row-b4')), findsNothing);
      // The buyer slot has no menu; the others do.
      expect(find.byKey(const Key('gym-pass-person-menu-b1')), findsNothing);
      expect(find.byKey(const Key('gym-pass-person-menu-b2')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-expiry-gpp_1')), findsOneWidget);
      expect(find.text('Invited'), findsOneWidget);
      expect(find.text('Suspended'), findsOneWidget);
      // The free slot can be filled.
      expect(find.byKey(const Key('gym-pass-add-gpp_1')), findsOneWidget);
      // A covered person: own QR and leave.
      expect(find.byKey(const Key('gym-pass-qr-b9')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-leave-gpp_9')), findsOneWidget);
    });

    apiTest('leave asks first and says it is permanent', (tester, api) async {
      api.on('GET /me/gym-passes', mine);
      await pumpPage(
        tester,
        api,
        const MemberGymPassesPage(),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(400, 1600),
      );
      await tester.ensureVisible(find.byKey(const Key('gym-pass-leave-gpp_9')));
      await tester.tap(find.byKey(const Key('gym-pass-leave-gpp_9')));
      await tester.pumpAndSettle();
      expect(find.textContaining('This is permanent'), findsOneWidget);
      expect(api.sent('POST', '/me/gym-passes/gpp_9/leave'), isFalse);
      await tester.tap(find.byKey(const Key('gym-pass-leave-confirm')));
      await tester.pumpAndSettle();
      expect(api.sent('POST', '/me/gym-passes/gpp_9/leave'), isTrue);
    });

    apiTest('remove asks first; suspend sends the route', (tester, api) async {
      api.on('GET /me/gym-passes', mine);
      await pumpPage(
        tester,
        api,
        const MemberGymPassesPage(),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(400, 1600),
      );
      await tester.tap(find.byKey(const Key('gym-pass-person-menu-b2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gym-pass-action-suspend')));
      await tester.pumpAndSettle();
      expect(
        api.sent(
          'POST',
          '/me/gym-pass-purchases/gpp_1/beneficiaries/b2/suspend',
        ),
        isTrue,
      );
      // A person the buyer suspended can be let back in.
      await tester.tap(find.byKey(const Key('gym-pass-person-menu-b3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gym-pass-action-resume')), findsOneWidget);
      await tester.tap(find.byKey(const Key('gym-pass-action-remove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove this person?'), findsOneWidget);
      expect(
        api.sent(
          'POST',
          '/me/gym-pass-purchases/gpp_1/beneficiaries/b3/remove',
        ),
        isFalse,
      );
      await tester.tap(find.byKey(const Key('gym-pass-remove-confirm')));
      await tester.pumpAndSettle();
      expect(
        api.sent(
          'POST',
          '/me/gym-pass-purchases/gpp_1/beneficiaries/b3/remove',
        ),
        isTrue,
      );
    });

    apiTest('flag off on the server: "not available", no crash', (
      tester,
      api,
    ) async {
      api.fail('GET /me/gym-passes', 404, {'error': 'feature_disabled'});
      await pumpPage(
        tester,
        api,
        const MemberGymPassesPage(),
        user: const {'id': 'm1', 'userType': 'member'},
      );
      expect(find.byKey(const Key('gym-passes-unavailable')), findsOneWidget);
    });
  });

  group('review fixes', () {
    apiTest('1: the sheet re-reads the plan and shows the fresh price', (
      tester,
      api,
    ) async {
      api.on('GET /gyms/gym_1/pass-plans', {
        'gymId': 'gym_1',
        'plans': [_plan('a', 'individual', price: 120000)],
      });
      final stale = GymPassPlan.fromJson(
        _plan('a', 'individual', price: 90000),
      )!;
      await tester.runAsync(() async {});
      await _pumpSheet(tester, api, stale);
      expect(find.byKey(const Key('gym-pass-buy-price')), findsOneWidget);
      expect(find.textContaining('120,000'), findsWidgets);
      expect(find.textContaining('90,000'), findsNothing);
    });

    apiTest('1: a plan that is gone cannot be bought', (tester, api) async {
      api.on('GET /gyms/gym_1/pass-plans', {'gymId': 'gym_1', 'plans': []});
      final plan = GymPassPlan.fromJson(_plan('a', 'individual'))!;
      await _pumpSheet(tester, api, plan);
      expect(find.text("This pass isn't available any more."), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('gym-pass-buy')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(api.sent('POST', '/me/gym-pass-purchases'), isFalse);
    });

    apiTest('1: the people boxes follow a changed headcount rule', (
      tester,
      api,
    ) async {
      api.on('GET /gyms/gym_1/pass-plans', {
        'gymId': 'gym_1',
        'plans': [_plan('c', 'group', limit: 5)],
      });
      final listed = GymPassPlan.fromJson(_plan('c', 'group', limit: 4))!;
      await _pumpSheet(tester, api, listed);
      // 5 people with the buyer = up to 4 boxes.
      expect(find.byKey(const Key('gym-pass-person-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('gym-pass-add-person')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('gym-pass-add-person')));
      await tester.pump();
      expect(find.byKey(const Key('gym-pass-person-3')), findsOneWidget);
      expect(find.byKey(const Key('gym-pass-add-person')), findsNothing);
    });

    apiTest('2: a payment step that throws still ends as a purchase', (
      tester,
      api,
    ) async {
      api.on('GET /gyms/gym_1/pass-plans', {
        'gymId': 'gym_1',
        'plans': [_plan('a', 'individual')],
      });
      api.on('POST /me/gym-pass-purchases', {
        'purchase': {'id': 'gpp_1'},
        'paymentRequest': {'id': 'pay_1', 'amountTzs': 90000},
      });
      final plan = GymPassPlan.fromJson(_plan('a', 'individual'))!;
      await _pumpSheet(
        tester,
        api,
        plan,
        payOverride: (_, _, _) async => throw StateError('boom'),
      );
      await tester.tap(find.byKey(const Key('gym-pass-buy')));
      await tester.pumpAndSettle();
      expect(api.where('POST', '/me/gym-pass-purchases'), hasLength(1));
      // The sheet closed (a purchase exists) and the member was told.
      expect(find.byKey(const Key('gym-pass-buy')), findsNothing);
      expect(find.textContaining('Finish the payment'), findsOneWidget);
    });

    apiTest('2: no swipe or outside tap, Close is off while busy', (
      tester,
      api,
    ) async {
      api.on('GET /gyms/gym_1/pass-plans', {
        'gymId': 'gym_1',
        'plans': [_plan('a', 'individual')],
      });
      final held = api.hold('POST /me/gym-pass-purchases');
      api.on('POST /me/gym-pass-purchases', {
        'purchase': {'id': 'gpp_1'},
        'paymentRequest': {'id': 'pay_1', 'amountTzs': 90000},
      });
      final plan = GymPassPlan.fromJson(_plan('a', 'individual'))!;
      await _pumpSheet(tester, api, plan, payOverride: (_, _, _) async => true);
      await tester.tap(find.byKey(const Key('gym-pass-buy')));
      await tester.pump();
      final close = tester.widget<IconButton>(
        find.byKey(const Key('gym-pass-close')),
      );
      expect(close.onPressed, isNull);
      // A tap on the barrier does not close it.
      await tester.tapAt(const Offset(200, 20));
      await tester.pump();
      expect(find.byKey(const Key('gym-pass-buy')), findsOneWidget);
      held.complete();
      await tester.pumpAndSettle();
    });

    test('3: reload when an active pass is not already loaded', () {
      final mine = GymPassesMine.fromJson({
        'memberships': [
          {
            'purchaseId': 'p1',
            'beneficiaryId': 'b1',
            'status': 'active',
            'purchaseStatus': 'active',
            'subscriptionId': 'sub_new',
          },
        ],
      });
      // The member already has another subscription: still reload.
      expect(gymPassNeedsProfileReload(mine, {'sub_old'}), isTrue);
      expect(gymPassNeedsProfileReload(mine, {'sub_old', 'sub_new'}), isFalse);
      expect(gymPassNeedsProfileReload(const GymPassesMine(), {}), isFalse);
      final suspended = GymPassesMine.fromJson({
        'memberships': [
          {
            'purchaseId': 'p1',
            'beneficiaryId': 'b1',
            'status': 'suspended',
            'purchaseStatus': 'active',
            'subscriptionId': 'sub_x',
          },
        ],
      });
      expect(gymPassNeedsProfileReload(suspended, {}), isFalse);
    });

    test('3: /me lists the subscriptions it already knows', () {
      final me = MemberMeResponse.fromJson({
        'user': {'id': 'u1'},
        'subscription': {'id': 'sub_a', 'status': 'active'},
        'entitlements': {
          'gymSubscriptions': [
            {'id': 'sub_b'},
          ],
        },
      });
      expect(me.knownSubscriptionIds, {'sub_a', 'sub_b'});
      expect(
        MemberMeResponse.fromJson(<String, dynamic>{}).knownSubscriptionIds,
        isEmpty,
      );
    });

    test('5: user-fixable codes have their own message', () {
      final en = _en();
      for (final (code, key) in [
        ('payment_reference_duplicate', 'referenceDuplicate'),
        ('already_beneficiary', 'alreadyBeneficiary'),
        ('too_many_attempts', 'tooManyAttempts'),
        ('cannot_modify_purchaser', 'cannotModifyBuyer'),
        ('not_allowed', 'notAllowed'),
      ]) {
        expect(
          gymPassErrorMessage(en, _err(409, {'error': code}), errorMessage),
          en.t('gymPass.error.$key'),
          reason: code,
        );
        expect(en.t('gymPass.error.$key'), isNot('gymPass.error.$key'));
        expect(
          _sw().t('gymPass.error.$key'),
          startsWith('[SW pending review]'),
        );
      }
    });

    test('6: a missing status is neutral, unknown labels exist', () {
      expect(GymPassPerson.fromJson({'id': 'x'})!.status, 'unknown');
      expect(_en().t('gymPass.status.unknown'), 'Unknown');
      expect(_en().t('gymPass.person.unknown'), 'Unknown');
      expect(_sw().t('gymPass.person.unknown'), startsWith('[SW pending'));
    });

    apiTest('6: an unknown status never shows raw server text', (
      tester,
      api,
    ) async {
      api.on('GET /me/gym-passes', {
        'purchased': [
          {
            'id': 'gpp_1',
            'status': 'weird_state',
            'plan': {'name': 'P', 'category': 'group'},
            'slots': {'used': 2, 'limit': 3},
            'beneficiaries': [
              {
                'id': 'b2',
                'slot': 2,
                'isPurchaser': false,
                'status': 'quantum_flux',
              },
            ],
          },
        ],
      });
      await pumpPage(
        tester,
        api,
        const MemberGymPassesPage(),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(400, 1600),
      );
      expect(find.textContaining('weird'), findsNothing);
      expect(find.textContaining('quantum'), findsNothing);
      expect(find.text('Unknown'), findsNWidgets(2));
    });
  });

  group('long text', () {
    // Swahili placeholders are the longest strings; a narrow phone at a large
    // text size must not overflow (a Flutter overflow fails the test).
    for (final lang in ['en', 'sw']) {
      apiTest('my passes and the buy sheet fit a narrow phone ($lang)', (
        tester,
        api,
      ) async {
        api.on('GET /me/gym-passes', _mine);
        await pumpPage(
          tester,
          api,
          const MemberGymPassesPage(),
          user: const {'id': 'm1', 'userType': 'member'},
          lang: lang,
          textScale: 1.5,
          size: const Size(320, 900),
        );
        expect(tester.takeException(), isNull);
        final plan = GymPassPlan.fromJson(
          _plan('c', 'group', limit: 5, terms: 'Terms text. ' * 20),
        )!;
        await pumpPage(
          tester,
          api,
          Builder(
            builder: (context) => TextButton(
              key: const Key('open-sheet'),
              onPressed: () =>
                  showGymPassBuySheet(context, gym: _gym(), plan: plan),
              child: const Text('open'),
            ),
          ),
          user: const {'id': 'm1', 'userType': 'member'},
          lang: lang,
          textScale: 1.5,
          size: const Size(320, 900),
        );
        await tester.tap(find.byKey(const Key('open-sheet')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('gym-pass-buy')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('strings', () {
    test('every gymPass key exists in English and Swahili', () {
      final en = _en();
      final sw = _sw();
      for (final key in const [
        'gymPass.sectionTitle',
        'gymPass.genericLabel',
        'gymPass.error.invalidBeneficiaries',
        'gymPass.error.cannotAddPerson',
        'gymPass.error.rateLimitedSeconds',
        'gymPass.leaveBody',
        'gymPass.mineTitle',
        'gymPass.action.suspend',
        'gymPass.person.invited',
      ]) {
        expect(en.t(key), isNot(key), reason: key);
        expect(sw.t(key), isNot(key), reason: 'sw $key');
      }
    });

    test('Swahili is a marked placeholder, not new translation', () {
      expect(
        _sw().t('gymPass.sectionTitle'),
        startsWith('[SW pending review]'),
      );
    });
  });
}
