// Requests from organisations (fitflex-functions#241): an organisation that
// names a member only by account id asks first; the member accepts or
// declines here, after being told what the organisation will see (A-02).

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/member_benefits_page.dart';
import 'package:fitflexmobile/screens/member/member_requests_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/inbox/inbox_pages.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _request({
  String id = 'b2bmr_1',
  String kind = 'beneficiary',
  String org = 'ABC Insurance',
  String? role,
  List<Map<String, dynamic>>? benefits,
  Map<String, dynamic>? sponsor,
}) => {
  'id': id,
  'kind': kind,
  'status': 'pending',
  'createdAt': '2026-10-22T08:00:00.000Z',
  'expiresAt': '2026-11-05T12:00:00.000Z',
  'decidedAt': null,
  'organization': {
    'id': 'b2borg_1',
    'corporateId': null,
    'name': org,
    'organizationType': 'insurer',
  },
  'role': role,
  'beneficiaryType': kind == 'beneficiary' ? 'policyholder' : null,
  'groupName': kind == 'beneficiary' ? 'Gold scheme' : null,
  'visibility': kind == 'org_user'
      ? {
          'shown': ['name', 'email', 'role'],
          'notShown': ['activity'],
          'en': '$org will see your name and email (EN).',
          'sw': '$org itaona jina lako na barua pepe yako (SW).',
        }
      : {
          'shown': ['gym_visits', 'trainer_sessions', 'steps', 'past_activity'],
          'notShown': ['weight', 'routes'],
          'en': '$org will see your FitFlex activity (EN).',
          'sw': '$org itaona shughuli zako za FitFlex (SW).',
        },
  'benefits':
      benefits ??
      [
        {
          'program': {'id': 'p1', 'name': 'Gold Wellness'},
          'benefit': {
            'id': 'b2bf_1',
            'name': '8 gym visits a month',
            'benefitType': 'gym_access',
            'fundingType': 'full',
            'fundingSummary': 'Sponsor pays 100%',
            'passTier': null,
            'usageLimit': 8,
            'usagePeriod': 'month',
          },
        },
      ],
  'sponsor': sponsor,
};

class _Api extends ApiClient {
  _Api(this.requests) : super(baseUrl: 'http://localhost:0');

  List<Map<String, dynamic>> requests;
  final accepted = <String>[];
  final declined = <String>[];
  int loads = 0;
  int benefitLoads = 0;
  ApiException? listError;
  ApiException? answerError;

  /// Whether /b2b/me/benefits includes `memberRequests` (older backends don't).
  bool benefitsHaveRequests = true;

  @override
  Future<Map<String, dynamic>> myMemberRequests() async {
    loads += 1;
    if (listError case final e?) throw e;
    return {'items': requests};
  }

  Future<Map<String, dynamic>> _answer(List<String> into, String id) async {
    into.add(id);
    final e = answerError;
    // Answered, expired or withdrawn: it is no longer pending either way.
    requests = requests.where((r) => r['id'] != id).toList();
    if (e != null) throw e;
    return {
      'memberRequest': {'id': id},
    };
  }

  @override
  Future<Map<String, dynamic>> acceptMemberRequest(String requestId) =>
      _answer(accepted, requestId);

  @override
  Future<Map<String, dynamic>> declineMemberRequest(String requestId) =>
      _answer(declined, requestId);

  @override
  Future<Map<String, dynamic>> myWellnessBenefits() async {
    benefitLoads += 1;
    return {
      'benefits': const [],
      'asOf': '2026-10-22',
      if (benefitsHaveRequests) 'memberRequests': requests,
    };
  }

  @override
  Future<Map<String, dynamic>> myIdentifiers() async =>
      throw ApiException(404, {'error': 'not_found'});

  @override
  Future<Map<String, dynamic>> myInvitations() async =>
      throw ApiException(404, {'error': 'not_found'});
}

Widget _app(_Api api, {String lang = 'en', Widget? home}) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale()..set(Locale(lang)),
    child: MaterialApp(
      theme: buildTheme(),
      home: home ?? const MemberRequestsPage(),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _accept = Key('member-request-accept-b2bmr_1');
const _decline = Key('member-request-decline-b2bmr_1');
const _confirm = Key('member-request-confirm');
const _cancel = Key('member-request-confirm-cancel');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('list', () {
    testWidgets('shows who asks, what for, what they will see and get', (
      tester,
    ) async {
      final api = _Api([
        _request(),
        _request(
          id: 'b2bmr_2',
          kind: 'org_user',
          org: 'Bima Plus',
          role: 'finance',
        ),
      ]);
      await tester.pumpWidget(_app(api));
      await _settle(tester);

      expect(find.text('ABC Insurance'), findsOneWidget);
      expect(
        find.text('Wants to add you to its wellness programme'),
        findsOneWidget,
      );
      expect(find.text('Group: Gold scheme'), findsOneWidget);
      expect(find.text('What ABC Insurance will see'), findsOneWidget);
      expect(
        find.text('ABC Insurance will see your FitFlex activity (EN).'),
        findsOneWidget,
      );
      expect(find.text('8 gym visits a month'), findsOneWidget);
      expect(find.text('Gold Wellness · Gym access'), findsOneWidget);
      expect(find.text('Up to 8 this month'), findsOneWidget);
      expect(find.text('Sponsor pays 100%'), findsOneWidget);
      expect(find.text('Answer by 5 Nov 2026'), findsWidgets);

      await tester.scrollUntilVisible(find.text('Bima Plus'), 200);
      expect(
        find.text('Wants to give you the finance role in its FitFlex portal'),
        findsOneWidget,
      );
      // A portal role: no benefits section.
      expect(
        find.descendant(
          of: find.byKey(const Key('member-request-b2bmr_2')),
          matching: find.text('What you would get'),
        ),
        findsNothing,
      );
    });

    testWidgets('a staff link shows the company pass and who pays', (
      tester,
    ) async {
      final api = _Api([
        _request(
          kind: 'employee_link',
          org: 'ABC Company',
          benefits: const [],
          sponsor: {'passTier': 'premium', 'subsidyModel': 'copay_70_30'},
        ),
      ]);
      await tester.pumpWidget(_app(api));
      await _settle(tester);

      expect(
        find.text('Wants to link your FitFlex account to your staff record'),
        findsOneWidget,
      );
      expect(find.text('Premium pass'), findsOneWidget);
      expect(find.text('Your employer pays 70%, you pay 30%'), findsOneWidget);
    });

    testWidgets('Swahili: server wording in Swahili, no overflow at 320dp', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _Api([
        _request(),
        _request(id: 'b2bmr_2', kind: 'org_user', role: 'hr'),
      ]);
      await tester.pumpWidget(_app(api, lang: 'sw'));
      await _settle(tester);

      expect(find.text('Maombi kutoka kwa mashirika'), findsOneWidget);
      expect(
        find.text('ABC Insurance itaona shughuli zako za FitFlex (SW).'),
        findsOneWidget,
      );
      expect(find.text('Mdhamini wako analipa yote'), findsOneWidget);
      expect(find.text('Kubali'), findsWidgets);
      expect(find.text('Kataa'), findsWidgets);
      expect(tester.takeException(), isNull);
      // The portal-role card further down lays out too.
      await tester.scrollUntilVisible(
        find.byKey(const Key('member-request-accept-b2bmr_2')),
        200,
      );
      expect(
        find.text(
          'Linataka kukupa nafasi ya rasilimali watu kwenye portal yake ya FitFlex',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(find.byKey(_accept), -200);
      await tester.tap(find.byKey(_accept));
      await _settle(tester);
      expect(
        find.text('Ukubali na kushiriki na ABC Insurance?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Litaona: kuingia gym, vipindi vya trainer, hatua, '
          'shughuli zako za kabla hujajiunga\n'
          'Halitaona: uzito, njia zako',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an older backend without the endpoint shows no error', (
      tester,
    ) async {
      final api = _Api([])..listError = ApiException(404, 'Not Found');
      await tester.pumpWidget(_app(api));
      await _settle(tester);

      expect(find.byKey(const Key('member-requests-empty')), findsOneWidget);
      expect(find.text('No requests waiting'), findsOneWidget);
      expect(find.byKey(const Key('member-requests-retry')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a server error offers a retry', (tester) async {
      final api = _Api([_request()])
        ..listError = ApiException(500, {'error': 'server_error'});
      await tester.pumpWidget(_app(api));
      await _settle(tester);

      expect(find.text('Couldn\'t load requests'), findsOneWidget);
      api.listError = null;
      await tester.tap(find.byKey(const Key('member-requests-retry')));
      await _settle(tester);
      expect(find.text('ABC Insurance'), findsOneWidget);
    });
  });

  group('answering', () {
    testWidgets('accept asks first, restating what is shared, then refreshes', (
      tester,
    ) async {
      final api = _Api([_request()]);
      await tester.pumpWidget(_app(api));
      await _settle(tester);
      expect(api.loads, 1);

      await tester.tap(find.byKey(_accept));
      await _settle(tester);
      expect(find.text('Accept and share with ABC Insurance?'), findsOneWidget);
      final dialog = find.byKey(const Key('member-request-confirm-dialog'));
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(
            'ABC Insurance will see your FitFlex activity (EN).',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(
            'Will see: gym visits, trainer sessions, steps, '
            'your activity from before you joined\n'
            'Won\'t see: weight, routes',
          ),
        ),
        findsOneWidget,
      );

      // Cancel: nothing is sent.
      await tester.tap(find.byKey(_cancel));
      await _settle(tester);
      expect(api.accepted, isEmpty);

      await tester.tap(find.byKey(_accept));
      await _settle(tester);
      await tester.tap(find.byKey(_confirm));
      await _settle(tester);

      expect(api.accepted, ['b2bmr_1']);
      expect(api.loads, 2);
      expect(
        find.text('Done. You are now linked to ABC Insurance.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('member-requests-empty')), findsOneWidget);
      expect(find.byKey(const Key('member-requests-benefits')), findsOneWidget);
    });

    testWidgets('decline sends it without sharing and refreshes', (
      tester,
    ) async {
      final api = _Api([_request()]);
      await tester.pumpWidget(_app(api));
      await _settle(tester);

      await tester.tap(find.byKey(_decline));
      await _settle(tester);

      expect(api.declined, ['b2bmr_1']);
      expect(api.accepted, isEmpty);
      expect(api.loads, 2);
      expect(
        find.text('Declined. Nothing was shared with ABC Insurance.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('member-requests-empty')), findsOneWidget);
      // Nothing accepted: no shortcut to benefits.
      expect(find.byKey(const Key('member-requests-benefits')), findsNothing);
    });

    Future<void> acceptWith(WidgetTester tester, ApiException error) async {
      final api = _Api([_request()])..answerError = error;
      await tester.pumpWidget(_app(api));
      await _settle(tester);
      await tester.tap(find.byKey(_accept));
      await _settle(tester);
      await tester.tap(find.byKey(_confirm));
      await _settle(tester);
      expect(api.accepted, ['b2bmr_1']);
      expect(api.loads, 2, reason: 'the list is refreshed after an error');
      expect(find.text('ABC Insurance'), findsNothing);
    }

    testWidgets('expired: a friendly message', (tester) async {
      await acceptWith(
        tester,
        ApiException(410, {'error': 'member_request_expired'}),
      );
      expect(
        find.text(
          'This request has expired. Ask the organisation to send a new one.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('already answered: a friendly message', (tester) async {
      await acceptWith(
        tester,
        ApiException(409, {
          'error': 'member_request_not_pending',
          'requestStatus': 'cancelled',
        }),
      );
      expect(find.text('This request was already answered.'), findsOneWidget);
    });

    testWidgets('no longer valid: a friendly message', (tester) async {
      await acceptWith(
        tester,
        ApiException(409, {
          'error': 'request_no_longer_valid',
          'memberRequestId': 'b2bmr_1',
        }),
      );
      expect(
        find.text(
          'This request is no longer valid. Ask the organisation to send a new one.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unknown visibility key: the server sentence, no raw key', (
      tester,
    ) async {
      final item = _request();
      (item['visibility'] as Map)['shown'] = [
        'gym_visits',
        'past_activity',
        'heart_rate_zones',
      ];
      final api = _Api([item]);
      await tester.pumpWidget(_app(api));
      await _settle(tester);
      await tester.tap(find.byKey(_accept));
      await _settle(tester);

      final dialog = find.byKey(const Key('member-request-confirm-dialog'));
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(
            'ABC Insurance will see your FitFlex activity (EN).',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('heart_rate_zones'), findsNothing);
      expect(find.textContaining('memberRequests.item'), findsNothing);
      expect(find.textContaining('Will see:'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('error codes map to their messages', () {
      String? key(int status, Object body) =>
          memberRequestErrorKey(ApiException(status, body));
      expect(
        key(404, {'error': 'member_request_not_found'}),
        'memberRequests.error.gone',
      );
      expect(key(404, 'Not Found'), 'memberRequests.error.gone');
      expect(
        key(409, {'error': 'already_enrolled'}),
        'memberRequests.error.alreadyLinked',
      );
      expect(
        key(409, {'error': 'employee_exited'}),
        'memberRequests.error.noLongerValid',
      );
      expect(key(500, {'error': 'server_error'}), isNull);
      expect(memberRequestErrorKey(Exception('x')), isNull);
    });
  });

  group('Benefits page card', () {
    testWidgets('shown when requests wait; opens them; reloads after', (
      tester,
    ) async {
      final api = _Api([_request()]);
      await tester.pumpWidget(_app(api, home: const MemberBenefitsPage()));
      await _settle(tester);

      expect(find.byKey(const Key('benefits-member-requests')), findsOneWidget);
      expect(find.text('An organisation wants to add you'), findsOneWidget);
      expect(api.benefitLoads, 1);

      await tester.tap(find.byKey(const Key('benefits-member-requests-open')));
      await _settle(tester);
      expect(find.byType(MemberRequestsPage), findsOneWidget);

      await tester.tap(find.byKey(_decline));
      await _settle(tester);
      await tester.pageBack();
      await _settle(tester);

      expect(api.benefitLoads, 2);
      expect(find.byKey(const Key('benefits-member-requests')), findsNothing);
    });

    testWidgets('counts several requests', (tester) async {
      final api = _Api([_request(), _request(id: 'b2bmr_2')]);
      await tester.pumpWidget(_app(api, home: const MemberBenefitsPage()));
      await _settle(tester);
      expect(find.text('2 organisations want to add you'), findsOneWidget);
    });

    testWidgets('hidden when none wait, or the backend has none', (
      tester,
    ) async {
      final none = _Api([]);
      await tester.pumpWidget(_app(none, home: const MemberBenefitsPage()));
      await _settle(tester);
      expect(find.byKey(const Key('benefits-member-requests')), findsNothing);

      final older = _Api([_request()])..benefitsHaveRequests = false;
      await tester.pumpWidget(
        _app(older, home: MemberBenefitsPage(key: UniqueKey())),
      );
      await _settle(tester);
      expect(find.byKey(const Key('benefits-member-requests')), findsNothing);
      expect(find.text('No wellness benefits yet'), findsOneWidget);
    });
  });

  group('notification links', () {
    test('the request notice opens the requests screen', () {
      expect(isB2BMemberRequest('b2b_member_request', const {}), isTrue);
      expect(
        isB2BMemberRequest('', const {'open': 'b2b_member_requests'}),
        isTrue,
      );
      expect(isB2BMemberRequest('subscription_renewal', const {}), isFalse);
      expect(opensScreenDirectly('b2b_member_request'), isTrue);
      expect(
        memberRouteFor(deepLink: '', type: 'b2b_member_request'),
        b2bMemberRequestsRoute,
      );
      expect(AppRoutes.memberRequests, '/organisation-requests');
    });

    const requestMessage = InboxMessage(
      id: 'n1',
      type: 'b2b_member_request',
      title: 'ABC Insurance wants to add you',
      body: 'Open to accept or decline.',
      data: {'requestId': 'b2bmr_1', 'open': 'b2b_member_requests'},
    );

    InboxMessage adminAdded(String kind) => InboxMessage(
      id: 'n2',
      type: 'b2b_admin_added',
      title: 'ABC Insurance added you',
      body: 'You were added by FitFlex.',
      data: {
        'kind': kind,
        'organizationId': 'b2borg_1',
        'open': 'b2b_benefits',
        'locale': 'en',
        'titleEn': 'ABC Insurance added you',
        'bodyEn': 'You were added by FitFlex.',
        'titleSw': 'ABC Insurance imekuongeza',
        'bodySw': 'Umeongezwa na FitFlex.',
      },
    );

    Future<(String?, String)> forRole(
      WidgetTester tester,
      String userType, {
      InboxMessage message = requestMessage,
    }) async {
      final api = _Api([]);
      final auth = AuthState(api);
      await auth.signIn('jwt', {'id': 'u1', 'userType': userType});
      late (String?, String) out;
      await tester.pumpWidget(
        AppScope(
          key: UniqueKey(),
          api: api,
          auth: auth,
          child: FFLocaleScope(
            notifier: FFLocale(),
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  out = (
                    routeForMessage(context, message),
                    inboxButtonLabel(context, message),
                  );
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      return out;
    }

    testWidgets('inbox button opens it for members and partners alike', (
      tester,
    ) async {
      for (final role in ['member', 'trainer', 'gym_operator', 'vendor']) {
        final (route, label) = await forRole(tester, role);
        expect(route, b2bMemberRequestsRoute, reason: role);
        expect(label, 'Review request', reason: role);
      }
    });

    test('a request push opens the requests screen on any side', () {
      for (final role in ['member', 'trainer', 'gym_operator', 'vendor']) {
        final target = pushTargetFor(
          role: role,
          data: {...requestMessage.data, 'type': 'b2b_member_request'},
          message: requestMessage,
        );
        expect(target.location, b2bMemberRequestsRoute, reason: role);
        expect(target.go, isTrue, reason: role);
      }
    });

    test('an admin add push: a member\'s benefits, else the message', () {
      Map<String, dynamic> push(String kind) => {
        ...adminAdded(kind).data,
        'type': 'b2b_admin_added',
      };
      expect(memberBenefitsRoute, AppRoutes.memberBenefits);
      for (final kind in ['beneficiary', 'employee_link']) {
        final t = pushTargetFor(
          role: 'member',
          data: push(kind),
          message: adminAdded(kind),
        );
        expect(t.location, '/member/benefits', reason: kind);
        expect(t.go, isTrue);
      }
      // A portal role: the message itself, not Benefits.
      final orgUser = pushTargetFor(
        role: 'member',
        data: push('org_user'),
        message: adminAdded('org_user'),
      );
      expect(orgUser.location, '/inbox/n2');
      // Not signed in as a member: the message, or the inbox without one.
      for (final role in ['trainer', 'gym_operator', 'vendor']) {
        expect(
          pushTargetFor(
            role: role,
            data: push('beneficiary'),
            message: adminAdded('beneficiary'),
          ).location,
          '/inbox/n2',
          reason: role,
        );
      }
      expect(
        pushTargetFor(role: 'trainer', data: push('beneficiary')).location,
        '/inbox',
      );
    });

    testWidgets('an admin add in the inbox: Benefits button for members', (
      tester,
    ) async {
      var (route, label) = await forRole(
        tester,
        'member',
        message: adminAdded('beneficiary'),
      );
      expect(route, '/member/benefits');
      expect(label, 'View my benefits');

      (route, label) = await forRole(
        tester,
        'member',
        message: adminAdded('org_user'),
      );
      expect(route, isNull, reason: 'a portal role shows the message itself');

      (route, label) = await forRole(
        tester,
        'trainer',
        message: adminAdded('employee_link'),
      );
      expect(route, isNull);
    });

    test('an admin add reads in the app language', () {
      final m = adminAdded('beneficiary');
      final sw = localisedNoticeText(
        lang: 'sw',
        data: m.data,
        title: m.title,
        body: m.body,
      );
      expect(sw.title, 'ABC Insurance imekuongeza');
      expect(sw.body, 'Umeongezwa na FitFlex.');
      final en = localisedNoticeText(
        lang: 'en',
        data: m.data,
        title: m.title,
        body: m.body,
      );
      expect(en.title, 'ABC Insurance added you');
    });

    testWidgets('the route opens the requests screen', (tester) async {
      final api = _Api([_request()]);
      final auth = AuthState(api);
      await auth.signIn('jwt', {
        'id': 'usr_1',
        'userType': 'member',
        'approvalStatus': 'approved',
        'onboardingCompleted': true,
      });
      final router = buildRouter(auth);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        AppScope(
          api: api,
          auth: auth,
          child: ThemeScope(
            notifier: ThemeNotifier(),
            child: FFLocaleScope(
              notifier: FFLocale(),
              child: MaterialApp.router(routerConfig: router),
            ),
          ),
        ),
      );
      router.go(AppRoutes.memberRequests);
      await _settle(tester);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/organisation-requests',
      );
      expect(find.byType(MemberRequestsPage), findsOneWidget);
      expect(find.text('ABC Insurance'), findsOneWidget);
    });
  });

  test('every request string exists in English and Swahili', () {
    final en =
        FFLocale.keysOf(
            'en',
          ).where((k) => k.startsWith('memberRequests.')).toSet()
          ..add('inbox.open.memberRequests');
    final sw =
        FFLocale.keysOf(
            'sw',
          ).where((k) => k.startsWith('memberRequests.')).toSet()
          ..add('inbox.open.memberRequests');
    expect(en, isNotEmpty);
    expect(sw, en);
    expect(FFLocale.keysOf('sw'), contains('inbox.open.memberRequests'));
    for (final k in en) {
      expect(
        FFLocale.textOf('sw', k),
        isNot(FFLocale.textOf('en', k)),
        reason: 'sw copies English: $k',
      );
    }
  });

  test('visibility keys the server sends all have words', () {
    final locale = FFLocale();
    const keys = [
      'name',
      'email',
      'role',
      'activity',
      'gym_visits',
      'trainer_sessions',
      'workouts',
      'steps',
      'active_minutes',
      'challenge_progress',
      'sponsored_benefit_use',
      'weight',
      'height',
      'calories',
      'notes',
      'routes',
      'other_sponsors',
    ];
    final item = {
      'visibility': {'shown': keys, 'notShown': const []},
    };
    expect(visibilityLists(locale, item), isNotNull);
    expect(
      visibilityLists(locale, {
        'visibility': {
          'shown': ['gym_visits', 'past_activity'],
          'notShown': const [],
        },
      }),
      'Will see: gym visits, your activity from before you joined',
    );
    // An unknown key falls back to the server's sentence.
    expect(
      visibilityLists(locale, {
        'visibility': {
          'shown': ['new_thing'],
          'notShown': const [],
        },
      }),
      isNull,
    );
  });
}
