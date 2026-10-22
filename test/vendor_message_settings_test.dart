// Vendors and their staff choose which offers they get (in the app, by push,
// WhatsApp, SMS) on the same message settings page members and trainers use,
// and a tapped gym/FitFlex campaign push opens its message for them too —
// also while the vendor waits for approval.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/member_message_settings_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/inbox/inbox_pages.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:0');

  int prefsLoads = 0;

  @override
  Future<List<dynamic>> vendorProducts() async => const [];
  @override
  Future<List<dynamic>> vendorOrders() async => const [];
  @override
  Future<Map<String, dynamic>> vendorProfile() async => {'status': 'published'};
  @override
  Future<Map<String, dynamic>> vendorPayments() async => const {};
  @override
  Future<List<dynamic>> vendorEnquiries({String? search}) async => const [];
  @override
  Future<List<dynamic>> vendorStaff() async => const [];
  @override
  Future<Map<String, dynamic>> me() async => throw ApiException(500, null);
  @override
  Future<Map<String, dynamic>> myTerms({String? lang, String? role}) async =>
      throw ApiException(500, null);

  @override
  Future<Map<String, dynamic>> communicationPreferences() async {
    prefsLoads++;
    return {
      'preferences': {
        'inAppMarketing': true,
        'pushMarketing': true,
        'whatsappMarketing': false,
        'whatsappAvailable': false,
        'smsMarketing': false,
        'smsTransactional': true,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> notifications() async => {
    'unread': 1,
    'notifications': [
      {
        'id': 'ntf_cmp_1',
        'type': 'campaign',
        'title': 'New in the shop this week',
        'body': 'FitFlex: list your products before Friday.',
        'category': 'marketing',
        'campaignId': 'cmp_1',
        'createdAt': DateTime.now().toIso8601String(),
        'readAt': null,
        'data': {
          'source': 'communication',
          'messageId': 'cmm_1',
          'deepLink': 'message',
          'senderName': 'FitFlex',
        },
      },
    ],
  };

  @override
  Future<void> markNotificationRead(String id) async {}
}

Future<AuthState> _signedIn(
  ApiClient api,
  String userType, {
  String approval = 'approved',
  List<String> permissions = const [],
}) async {
  final auth = AuthState(api);
  await auth.signIn('jwt', {
    'id': 'usr_1',
    'userType': userType,
    'approvalStatus': approval,
    'onboardingCompleted': true,
    'displayName': 'Asha',
    if (userType == 'vendor_staff') 'vendorPermissions': permissions,
  });
  return auth;
}

Widget _scoped(
  _Api api,
  AuthState auth, {
  InboxController? inbox,
  Widget? home,
  GoRouter? router,
}) => AppScope(
  api: api,
  auth: auth,
  inbox: inbox,
  child: ThemeScope(
    notifier: ThemeNotifier(),
    child: FFLocaleScope(
      notifier: FFLocale(),
      child: router != null
          ? MaterialApp.router(theme: buildTheme(), routerConfig: router)
          : MaterialApp(
              theme: buildTheme(),
              supportedLocales: const [Locale('en'), Locale('sw')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: home,
            ),
    ),
  ),
);

Future<void> _bigScreen(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Message settings on the vendor Business tab', () {
    for (final (who, perms) in [
      ('vendor', const <String>[]),
      ('vendor_staff', const ['products', 'staff']),
    ]) {
      testWidgets('$who opens the shared message settings page', (t) async {
        await _bigScreen(t);
        final api = _Api();
        final auth = await _signedIn(api, who, permissions: perms);
        await t.pumpWidget(_scoped(api, auth, home: const VendorHomePage()));
        await t.pumpAndSettle();

        await t.tap(find.byKey(const Key('vendor-nav-business')));
        await t.pumpAndSettle();
        final tile = find.byKey(const Key('vendor-message-settings'));
        await t.scrollUntilVisible(tile, 200);
        expect(tile, findsOneWidget);
        expect(
          find.descendant(of: tile, matching: find.text('Messages & offers')),
          findsOneWidget,
        );

        await t.tap(tile);
        await t.pumpAndSettle();
        expect(find.byType(MemberMessageSettingsPage), findsOneWidget);
        expect(api.prefsLoads, 1);
        expect(find.byKey(const Key('prefs-push-offers')), findsOneWidget);
        expect(find.byKey(const Key('prefs-inapp-offers')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('the entry has its Swahili label', (t) async {
      // Wider: the test font (every glyph a full square) makes the Swahili
      // Staff header row wider than on a phone.
      t.view.physicalSize = const Size(1600, 1600);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      final api = _Api();
      final auth = await _signedIn(api, 'vendor');
      final locale = FFLocale()..set(const Locale('sw'));
      await t.pumpWidget(
        AppScope(
          api: api,
          auth: auth,
          child: ThemeScope(
            notifier: ThemeNotifier(),
            child: FFLocaleScope(
              notifier: locale,
              child: MaterialApp(
                theme: buildTheme(),
                supportedLocales: const [Locale('en'), Locale('sw')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const VendorHomePage(),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('vendor-nav-business')));
      await t.pumpAndSettle();
      final tile = find.byKey(const Key('vendor-message-settings'));
      await t.scrollUntilVisible(tile, 200);
      expect(
        find.descendant(of: tile, matching: find.text('Ujumbe na ofa')),
        findsOneWidget,
      );
    });
  });

  group('Message settings from the inbox', () {
    Future<bool> settingsButtonShown(
      WidgetTester t,
      String who, {
      List<String> permissions = const [],
    }) async {
      final api = _Api();
      final auth = await _signedIn(api, who, permissions: permissions);
      final inbox = InboxController(api);
      await t.pumpWidget(
        _scoped(api, auth, inbox: inbox, home: const InboxPage()),
      );
      await t.pumpAndSettle();
      return find.byKey(const Key('inbox-settings')).evaluate().isNotEmpty;
    }

    testWidgets('vendors and all their staff have the settings button', (
      t,
    ) async {
      expect(await settingsButtonShown(t, 'vendor'), isTrue);
      // Staff with only Orders have no Business tab: the inbox is their way.
      expect(
        await settingsButtonShown(t, 'vendor_staff', permissions: ['orders']),
        isTrue,
      );
      expect(await settingsButtonShown(t, 'member'), isTrue);
      // Unchanged for the other partner sides.
      expect(await settingsButtonShown(t, 'gym_operator'), isFalse);
    });
  });

  group('A tapped campaign push opens the message for vendors', () {
    // The payload the backend sends with a campaign push (delivery-service
    // payload + notificationId): no `type`.
    Map<String, dynamic> campaignPush({String notificationId = 'ntf_cmp_1'}) =>
        {
          'source': 'communication',
          'messageId': 'cmm_1',
          'campaignId': 'cmp_1',
          'deepLink': 'message',
          'gymId': '',
          'category': 'marketing',
          'ctaLabel': '',
          'senderName': 'FitFlex',
          'notificationId': notificationId,
        };

    const message = InboxMessage(
      id: 'ntf_cmp_1',
      type: 'campaign',
      title: 'New in the shop this week',
      body: 'FitFlex: list your products before Friday.',
      data: {'source': 'communication', 'deepLink': 'message'},
    );

    for (final who in ['vendor', 'vendor_staff']) {
      test('$who: the in-app copy opens over the current screen', () {
        final target = pushTargetFor(
          role: who,
          data: campaignPush(),
          message: message,
        );
        expect(target.location, '/inbox/ntf_cmp_1');
        expect(target.go, isFalse);
      });

      test('$who: a push with no in-app copy opens the inbox', () {
        final target = pushTargetFor(
          role: who,
          data: campaignPush(notificationId: ''),
        );
        expect(target.location, '/inbox');
        expect(target.go, isFalse);
      });

      test('$who: vendor news still goes to its screen', () {
        final target = pushTargetFor(
          role: who,
          data: {'type': 'vendor_new_order'},
        );
        expect(target.location, '/vendor/home?open=orders');
        expect(target.go, isTrue);
      });
    }

    test('members keep their own links', () {
      expect(
        pushTargetFor(
          role: 'member',
          data: {'deepLink': 'renewal', 'source': 'communication'},
        ).location,
        '/member/passes',
      );
    });

    testWidgets(
      'a vendor waiting for approval reaches the inbox, the message and the settings',
      (t) async {
        Future<String> landing(String to, {String who = 'vendor'}) async {
          final api = _Api();
          final auth = await _signedIn(api, who, approval: 'pending_approval');
          final inbox = InboxController(api);
          await inbox.load();
          final router = buildRouter(auth);
          addTearDown(router.dispose);
          await t.pumpWidget(_scoped(api, auth, inbox: inbox, router: router));
          router.go(to);
          await t.pump();
          await t.pump();
          final location = router.state.matchedLocation;
          if (to == '/inbox/ntf_cmp_1') {
            await t.pump(const Duration(milliseconds: 500));
            expect(find.byType(InboxMessagePage), findsOneWidget);
            expect(find.text('New in the shop this week'), findsWidgets);
          }
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(seconds: 6));
          return location;
        }

        expect(await landing('/inbox'), '/inbox');
        expect(await landing('/inbox/ntf_cmp_1'), '/inbox/ntf_cmp_1');
        expect(
          await landing(AppRoutes.memberMessageSettings),
          AppRoutes.memberMessageSettings,
        );
        // Everything else still waits.
        expect(await landing(AppRoutes.memberHome), AppRoutes.vendorHome);
        // A pending trainer is unchanged.
        expect(await landing('/inbox', who: 'trainer'), AppRoutes.pending);
      },
    );
  });
}
