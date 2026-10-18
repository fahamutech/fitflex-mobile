// The sign-in contact (email or phone) must never be put in the URL: it
// would leak into browser history and logs. It travels as in-memory GoRouter
// `extra`; without it (deep link, reload) the route goes back to sign-in.

import 'dart:convert';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<GoRouter> _pumpRouter(WidgetTester tester) async {
  final api = ApiClient(baseUrl: 'http://localhost:0');
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

  group('EmailAuthExtraCodec', () {
    const codec = EmailAuthExtraCodec();

    test('history state holds only an opaque key, never the contact', () {
      const args = EmailAuthArgs(contact: email, mode: EmailAuthMode.signUp);
      final encoded = codec.encode(args);
      expect(jsonEncode(encoded), isNot(contains('amina')));
      expect(identical(codec.decode(encoded), args), isTrue);
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
