// The sign-in contact (email or phone) must never be put in the URL: it
// would leak into browser history and logs. It travels as in-memory GoRouter
// `extra`; without it (deep link, reload) the route goes back to sign-in.

import 'dart:convert';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/held_nav_extras.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signs in with a FitFlex PIN; the session it returns is a member.
class _PinApi extends ApiClient {
  _PinApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<Map<String, dynamic>> signInOptions() async => {
    'pinLogin': true,
    'pinReset': true,
    'recovery': true,
    'smsCodes': true,
    'emailCodes': true,
  };

  @override
  Future<bool> pinLoginAvailable() async => true;

  @override
  Future<bool> pinResetAvailable() async => true;

  @override
  Future<Map<String, dynamic>> pinLogin(
    Map<String, String> contact,
    String pin, {
    String? locale,
  }) async => {
    'token': 'jwt-new',
    'user': {
      'id': 'usr_1',
      'userType': 'member',
      'approvalStatus': 'approved',
      'onboardingCompleted': true,
    },
  };
}

Future<GoRouter> _pumpRouter(WidgetTester tester, {ApiClient? client}) async {
  final api = client ?? ApiClient(baseUrl: 'http://localhost:0');
  final auth = AuthState(api);
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
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  const email = 'amina@example.com';

  testWidgets('continuing from sign-in keeps the email out of the URL', (
    tester,
  ) async {
    final router = await _pumpRouter(tester);
    router.go(AppRoutes.auth);
    await _settle(tester);

    await tester.enterText(find.byKey(const Key('login-identifier')), email);
    await tester.pump();
    await tester.tap(find.byKey(const Key('login-continue')));
    await _settle(tester);

    expect(router.state.matchedLocation, AppRoutes.emailAuth);
    expect(router.state.uri.toString(), AppRoutes.emailAuth);
    final reported = _reportedLocation(router);
    expect(reported, isNot(contains('amina')));
    expect(reported, isNot(contains('email=')));

    final screen = tester.widget<EmailAuthScreen>(find.byType(EmailAuthScreen));
    expect(screen.initialEmail, email);
    expect(screen.initialMode, EmailAuthMode.signIn);

    // Back returns to the sign-in entry.
    router.pop();
    await _settle(tester);
    expect(router.state.matchedLocation, AppRoutes.auth);
    await _unmount(tester);
  });

  testWidgets('a deep link without in-memory args goes back to sign-in', (
    tester,
  ) async {
    final router = await _pumpRouter(tester);
    router.go(AppRoutes.emailAuth);
    await _settle(tester);
    expect(router.state.matchedLocation, AppRoutes.auth);
    expect(find.byType(EmailAuthScreen), findsNothing);
    await _unmount(tester);
  });

  testWidgets('an old ?email= link is ignored and goes back to sign-in', (
    tester,
  ) async {
    final router = await _pumpRouter(tester);
    router.go('${AppRoutes.emailAuth}?email=amina%40example.com&mode=signup');
    await _settle(tester);
    expect(router.state.matchedLocation, AppRoutes.auth);
    expect(find.byType(EmailAuthScreen), findsNothing);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      isNot(contains('amina')),
    );
    await _unmount(tester);
  });

  testWidgets('sign-up mode travels in memory too', (tester) async {
    final router = await _pumpRouter(tester);
    router.go(AppRoutes.auth);
    await _settle(tester);
    final ctx = tester.element(find.byKey(const Key('login-identifier')));
    pushEmailAuth(ctx, contact: '0712345678', mode: EmailAuthMode.signUp);
    await _settle(tester);
    final screen = tester.widget<EmailAuthScreen>(find.byType(EmailAuthScreen));
    expect(screen.initialEmail, '0712345678');
    expect(screen.initialMode, EmailAuthMode.signUp);
    expect(router.state.uri.toString(), AppRoutes.emailAuth);
    expect(_reportedLocation(router), isNot(contains('0712345678')));

    // An auth-state refresh round-trips extras through the codec; the
    // contact must survive it.
    AppScope.of(ctx).auth.notifyListeners();
    await _settle(tester);
    expect(
      tester.widget<EmailAuthScreen>(find.byType(EmailAuthScreen)).initialEmail,
      '0712345678',
    );
    await _unmount(tester);
  });

  group('held contact is forgotten', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      EmailAuthExtraCodec.clear();
    });

    Future<RouteInformation> openEmailScreen(
      WidgetTester tester,
      GoRouter router,
    ) async {
      router.go(AppRoutes.auth);
      await _settle(tester);
      final ctx = tester.element(find.byKey(const Key('login-identifier')));
      pushEmailAuth(ctx, contact: '0712345678');
      await _settle(tester);
      expect(find.byType(EmailAuthScreen), findsOneWidget);
      // What the browser keeps for this history entry.
      return router.routeInformationParser.restoreRouteInformation(
        router.routerDelegate.currentConfiguration,
      )!;
    }

    // Browser Back/Forward to an old entry hands its saved state back.
    Future<void> restore(
      WidgetTester tester,
      GoRouter router,
      RouteInformation info,
    ) async {
      router.routeInformationProvider.didPushRouteInformation(info);
      await _settle(tester);
      await _settle(tester);
    }

    testWidgets('after sign-out, an old history entry lands on sign-in', (
      tester,
    ) async {
      final router = await _pumpRouter(tester);
      final entry = await openEmailScreen(tester, router);
      expect(HeldNavExtras.length, 1);

      // User A leaves the screen; the entry stays in browser history.
      router.go(AppRoutes.auth);
      await _settle(tester);
      final auth = AppScope.of(
        tester.element(find.byKey(const Key('login-identifier'))),
      ).auth;
      await auth.signOut();
      await _settle(tester);
      expect(HeldNavExtras.length, 0);

      // User B presses Back to A's entry.
      await restore(tester, router, entry);
      expect(router.state.matchedLocation, AppRoutes.auth);
      expect(find.byType(EmailAuthScreen), findsNothing);
      expect(find.text('0712345678'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('after a successful sign-in the contact is gone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = await _pumpRouter(tester, client: _PinApi());
      final entry = await openEmailScreen(tester, router);
      await tester.pump(const Duration(milliseconds: 100));

      for (final digit in '4821'.split('')) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      await tester.tap(find.text('OK'));
      await _settle(tester);

      final auth = AppScope.of(
        tester.element(find.byType(Router<Object>).first),
      ).auth;
      expect(auth.isSignedIn, isTrue);
      expect(router.state.matchedLocation, isNot(AppRoutes.emailAuth));
      expect(find.byType(EmailAuthScreen), findsNothing);
      expect(HeldNavExtras.length, 0);

      // Signing out and pressing Back to the old entry shows no contact.
      await auth.signOut();
      await _settle(tester);
      await restore(tester, router, entry);
      expect(router.state.matchedLocation, AppRoutes.auth);
      expect(find.byType(EmailAuthScreen), findsNothing);
      expect(find.text('0712345678'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a sign-out during the flow keeps the open screen', (
      tester,
    ) async {
      // A wrong PIN is a 401, and every 401 signs out: the person must stay
      // on the PIN screen with their contact.
      final router = await _pumpRouter(tester);
      await openEmailScreen(tester, router);
      final ctx = tester.element(find.byType(EmailAuthScreen));
      await AppScope.of(ctx).auth.signOut();
      await _settle(tester);
      expect(router.state.matchedLocation, AppRoutes.emailAuth);
      expect(
        tester
            .widget<EmailAuthScreen>(find.byType(EmailAuthScreen))
            .initialEmail,
        '0712345678',
      );
      expect(HeldNavExtras.length, 1);

      // Leaving the screen forgets it.
      router.pop();
      await _settle(tester);
      expect(router.state.matchedLocation, AppRoutes.auth);
      expect(HeldNavExtras.length, 0);
      await _unmount(tester);
    });

    test('AuthState.signOut forgets held contacts', () async {
      const codec = EmailAuthExtraCodec();
      final encoded = codec.encode(const EmailAuthArgs(contact: email));
      expect(codec.decode(encoded), isNotNull);
      await AuthState(ApiClient(baseUrl: 'http://localhost:0')).signOut();
      expect(codec.decode(encoded), isNull);
    });
  });

  group('EmailAuthExtraCodec', () {
    const codec = EmailAuthExtraCodec();

    test('history state holds only an opaque key, never the contact', () {
      const args = EmailAuthArgs(contact: email, mode: EmailAuthMode.signUp);
      final encoded = codec.encode(args);
      expect(jsonEncode(encoded), isNot(contains('amina')));
      expect(identical(codec.decode(encoded), args), isTrue);
    });

    test('keys are random and unique, not sequential', () {
      final keys = <String>{};
      for (var i = 0; i < 20; i++) {
        final encoded =
            codec.encode(EmailAuthArgs(contact: 'c$i@example.com')) as Map;
        final key = encoded['ffMem'] as String;
        expect(key, isNot(matches(RegExp(r'^k\d+$'))));
        // 16 bytes, base64url without padding.
        expect(key, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
        keys.add(key);
      }
      expect(keys.length, 20);
      expect(HeldNavExtras.newKey(), isNot(HeldNavExtras.newKey()));
      EmailAuthExtraCodec.clear();
    });

    test('only the newest unpinned contacts are kept', () {
      EmailAuthExtraCodec.clear();
      final first = codec.encode(const EmailAuthArgs(contact: 'old@x.com'));
      for (var i = 0; i < HeldNavExtras.maxHeld; i++) {
        codec.encode(EmailAuthArgs(contact: 'n$i@x.com'));
      }
      expect(HeldNavExtras.length, HeldNavExtras.maxHeld);
      expect(codec.decode(first), isNull);
      EmailAuthExtraCodec.clear();
    });

    test('an unknown key (e.g. after a reload) decodes to nothing', () {
      expect(codec.decode({'ffMem': 'k-not-held'}), isNull);
    });

    test('other extras keep JSON behaviour', () {
      expect(codec.decode(codec.encode({'a': 1})), {'a': 1});
      expect(codec.encode(null), isNull);
      expect(codec.encode(Object()), isNull);
    });

    test('EmailAuthArgs has no toJson, so JSON encoding refuses it', () {
      expect(
        () => jsonEncode(const EmailAuthArgs(contact: email)),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });
  });
}

/// The location the router reports to the browser (address bar + history).
String _reportedLocation(GoRouter router) {
  final info = router.routeInformationParser.restoreRouteInformation(
    router.routerDelegate.currentConfiguration,
  );
  return info?.uri.toString() ?? '';
}
