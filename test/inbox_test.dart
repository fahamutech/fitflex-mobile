// The inbox: messages from the app, the member's gym and FitFlex, with read
// and tap tracking, push taps, links to app screens, and message settings.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_message_settings_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/inbox/inbox_pages.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0');

  final calls = <String>[];
  Map<String, dynamic> prefs = {
    'inAppMarketing': true,
    'pushMarketing': true,
    'whatsappMarketing': false,
    'whatsappAvailable': false,
  };
  List<Map<String, dynamic>> rows = [
    {
      'id': 'ntf_offer',
      'type': 'campaign',
      'title': '20% off in October',
      'body': 'Hi Asha, 20% off this month at Kilele Fitness.',
      'category': 'marketing',
      'gymId': 'gym_1',
      'campaignId': 'cmp_1',
      'createdAt': DateTime.now().toIso8601String(),
      'readAt': null,
      'data': {
        'source': 'communication',
        'messageId': 'cmm_1',
        'deepLink': 'gym',
        'ctaLabel': 'See the gym',
        'senderName': 'Kilele Fitness',
      },
    },
    {
      'id': 'ntf_renew',
      'type': 'campaign',
      'title': 'Your plan ends soon',
      'body': 'Hi Asha, your plan ends on 01/10/2026.',
      'category': 'transactional',
      'gymId': 'gym_1',
      'createdAt': DateTime.now().toIso8601String(),
      'readAt': null,
      'data': {
        'source': 'communication',
        'messageId': 'cmm_2',
        'deepLink': 'renewal',
        'ctaLabel': 'Renew now',
        'senderName': 'Kilele Fitness',
      },
    },
    {
      'id': 'ntf_old',
      'type': 'subscription_activated',
      'title': 'Payment confirmed',
      'body': 'Your Pro pass is active.',
      'createdAt': DateTime(2026, 9, 1).toIso8601String(),
      'readAt': DateTime(2026, 9, 1).toIso8601String(),
      'data': {'type': 'subscription_activated'},
    },
  ];

  @override
  Future<Map<String, dynamic>> notifications() async {
    calls.add('list');
    return {
      'notifications': rows,
      'unread': rows.where((r) => r['readAt'] == null).length,
    };
  }

  @override
  Future<void> markNotificationRead(String id) async => calls.add('read:$id');

  @override
  Future<void> clickNotification(String id, {String via = 'inbox'}) async =>
      calls.add('click:$id:$via');

  @override
  Future<void> pushMessageOpened(String messageId) async =>
      calls.add('pushOpened:$messageId');

  @override
  Future<Map<String, dynamic>> communicationPreferences() async => {
    'preferences': prefs,
  };

  @override
  Future<Map<String, dynamic>> updateCommunicationPreferences(
    Map<String, dynamic> changes,
  ) async {
    calls.add('prefs:$changes');
    prefs = {...prefs, ...changes};
    return {'preferences': prefs};
  }
}

void main() {
  group('inbox controller', () {
    test('loads messages and the unread count', () async {
      final api = _FakeApi();
      final inbox = InboxController(api);
      await inbox.load();
      expect(inbox.messages, hasLength(3));
      expect(inbox.unread, 2);
      expect(inbox.byId('ntf_offer')!.senderName, 'Kilele Fitness');
      expect(inbox.byId('ntf_offer')!.ctaLabel, 'See the gym');
    });

    test('reading a message once counts once', () async {
      final api = _FakeApi();
      final inbox = InboxController(api)..load();
      await Future<void>.delayed(Duration.zero);
      await inbox.markRead('ntf_offer');
      await inbox.markRead('ntf_offer');
      await inbox.markRead('ntf_old'); // already read
      expect(inbox.unread, 1);
      expect(api.calls.where((c) => c.startsWith('read:')), ['read:ntf_offer']);
    });

    test(
      'tapping the button records a click; mark all read clears the badge',
      () async {
        final api = _FakeApi();
        final inbox = InboxController(api);
        await inbox.load();
        await inbox.click('ntf_renew');
        expect(api.calls, contains('click:ntf_renew:inbox'));
        expect(inbox.byId('ntf_renew')!.unread, isFalse);
        await inbox.markAllRead();
        expect(inbox.unread, 0);
        expect(api.calls, contains('read:all'));
      },
    );

    test(
      'a tapped push records the push opened and the message read',
      () async {
        final api = _FakeApi();
        final inbox = InboxController(api);
        final m = await inbox.openFromPush({
          'source': 'communication',
          'messageId': 'cmm_push_1',
          'notificationId': 'ntf_renew',
        });
        expect(m?.id, 'ntf_renew');
        expect(
          api.calls,
          containsAllInOrder([
            'pushOpened:cmm_push_1',
            'list',
            'read:ntf_renew',
          ]),
        );
        expect(
          api.calls.any((c) => c.startsWith('click:')),
          isFalse,
          reason: 'opening is not tapping the button',
        );
      },
    );

    test(
      'a push with no inbox copy records the open and returns nothing',
      () async {
        final api = _FakeApi();
        final m = await InboxController(api).openFromPush({
          'source': 'communication',
          'messageId': 'cmm_9',
          'notificationId': '',
        });
        expect(m, isNull);
        expect(api.calls, ['pushOpened:cmm_9']);
      },
    );

    test('signing out clears everything', () async {
      final inbox = InboxController(_FakeApi());
      await inbox.load();
      inbox.clear();
      expect(inbox.messages, isEmpty);
      expect(inbox.unread, 0);
    });

    test('messages are grouped for the filters', () async {
      final inbox = InboxController(_FakeApi());
      await inbox.load();
      expect(inbox.byId('ntf_offer')!.kind, InboxCategory.offers);
      expect(inbox.byId('ntf_renew')!.kind, InboxCategory.membership);
      expect(inbox.byId('ntf_old')!.kind, InboxCategory.membership);
    });
  });

  test('links go only to fixed member screens', () {
    expect(
      memberRouteFor(deepLink: 'renewal', type: 'campaign'),
      '/member/passes',
    );
    expect(
      memberRouteFor(deepLink: 'membership', type: 'campaign'),
      '/member/passes',
    );
    expect(
      memberRouteFor(deepLink: 'payment', type: 'campaign'),
      '/member/payment',
    );
    expect(
      memberRouteFor(deepLink: 'gym', type: 'campaign', gymId: 'gym_1'),
      '/member/gyms/gym_1',
    );
    expect(
      memberRouteFor(deepLink: 'gym', type: 'campaign'),
      isNull,
      reason: 'no gym to open',
    );
    expect(memberRouteFor(deepLink: 'message', type: 'campaign'), isNull);
    expect(
      memberRouteFor(deepLink: 'https://evil.example', type: 'campaign'),
      isNull,
    );
    expect(
      memberRouteFor(deepLink: '', type: 'subscription_renewal'),
      '/member/passes',
    );
    expect(
      memberRouteFor(deepLink: '', type: 'trainer_booking_confirmed'),
      isNull,
    );
  });

  group('screens', () {
    Widget app({
      required _FakeApi api,
      required InboxController inbox,
      String initial = '/inbox',
    }) {
      final router = GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(path: '/inbox', builder: (_, _) => const InboxPage()),
          GoRoute(
            path: '/inbox/:id',
            builder: (_, s) =>
                InboxMessagePage(messageId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/member/passes',
            builder: (_, _) => const Scaffold(body: Text('PASSES')),
          ),
          GoRoute(
            path: '/member/gyms/:gymId',
            builder: (_, s) =>
                Scaffold(body: Text('GYM ${s.pathParameters['gymId']}')),
          ),
          GoRoute(
            path: '/member/message-settings',
            builder: (_, _) => const MemberMessageSettingsPage(),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: InboxBellButton()),
          ),
        ],
      );
      return AppScope(
        api: api,
        auth: AuthState(api),
        inbox: inbox,
        child: FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
    }

    testWidgets('the bell shows how many messages are unread', (tester) async {
      final api = _FakeApi();
      final inbox = InboxController(api);
      await inbox.load();
      await tester.pumpWidget(app(api: api, inbox: inbox, initial: '/home'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('open a message, read it, and follow its button', (
      tester,
    ) async {
      final api = _FakeApi();
      final inbox = InboxController(api);
      await tester.pumpWidget(app(api: api, inbox: inbox));
      await tester.pumpAndSettle();
      expect(find.text('20% off in October'), findsOneWidget);
      expect(find.text('Payment confirmed'), findsOneWidget);

      await tester.tap(find.byKey(const Key('inbox-filter-offers')));
      await tester.pumpAndSettle();
      expect(find.text('20% off in October'), findsOneWidget);
      expect(find.text('Your plan ends soon'), findsNothing);

      await tester.tap(find.byKey(const Key('inbox-ntf_offer')));
      await tester.pumpAndSettle();
      expect(
        find.text('Hi Asha, 20% off this month at Kilele Fitness.'),
        findsOneWidget,
      );
      expect(api.calls, contains('read:ntf_offer'));
      await tester.tap(find.byKey(const Key('inbox-cta')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('click:ntf_offer:inbox'));
      expect(find.text('GYM gym_1'), findsOneWidget);
    });

    testWidgets('a message that links nowhere has no button', (tester) async {
      final api = _FakeApi();
      final inbox = InboxController(api);
      await tester.pumpWidget(
        app(api: api, inbox: inbox, initial: '/inbox/ntf_old'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your Pro pass is active.'), findsOneWidget);
      // subscription_activated links to membership for members.
      expect(find.byKey(const Key('inbox-cta')), findsOneWidget);
      api.rows = [
        {
          ...api.rows.last,
          'id': 'ntf_trainer',
          'type': 'trainer_booking_confirmed',
          'data': {},
        },
      ];
      await inbox.load();
      await tester.pumpWidget(
        app(api: api, inbox: inbox, initial: '/inbox/ntf_trainer'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inbox-cta')), findsNothing);
    });

    testWidgets(
      'message settings: offers switch off; WhatsApp offers need agreement',
      (tester) async {
        final api = _FakeApi();
        await tester.pumpWidget(
          app(
            api: api,
            inbox: InboxController(api),
            initial: '/member/message-settings',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('prefs-inapp-offers')));
        await tester.pumpAndSettle();
        expect(api.calls, contains('prefs:{inAppMarketing: false}'));

        await tester.tap(find.byKey(const Key('prefs-whatsapp-offers')));
        await tester.pumpAndSettle();
        expect(find.text('Get offers on WhatsApp?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('whatsapp-agree')));
        await tester.pumpAndSettle();
        expect(api.calls, contains('prefs:{whatsappMarketing: true}'));
        expect(
          find.textContaining('always come to your Messages'),
          findsOneWidget,
        );
      },
    );
  });

  test('every inbox and message-settings string has a Swahili translation', () {
    final en = FFLocale.keysOf(
      'en',
    ).where((k) => k.startsWith('inbox.') || k.startsWith('msgPrefs.'));
    final sw = FFLocale.keysOf('sw');
    expect(en, isNotEmpty);
    expect(en.where((k) => !sw.contains(k)), isEmpty);
  });
}
