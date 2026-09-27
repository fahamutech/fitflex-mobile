import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/verify_email_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/firebase_auth_service.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

/// Firebase stand-in: verification flips to true once [verifyNow] is called.
class _FakeFirebase extends FirebaseAuthService {
  int sent = 0;
  bool verified = false;
  bool signedOut = false;

  @override
  String? get currentEmail => 'owner@example.com';

  @override
  Future<void> sendEmailVerification() async => sent++;

  @override
  Future<bool> reloadEmailVerified() async => verified;

  @override
  Future<String?> freshIdToken() async => 'fresh-token';

  @override
  Future<void> signOut() async => signedOut = true;
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0');

  final calls = <(String, String?)>[];

  @override
  Future<Map<String, dynamic>> firebaseSession(
    String idToken,
    String? requestedRole,
  ) async {
    calls.add((idToken, requestedRole));
    return {
      'token': 'fitflex-jwt',
      'user': {
        'id': 'usr_owner',
        'userType': 'gym_operator',
        'approvalStatus': 'approved',
        'onboardingCompleted': true,
        'gymIds': ['gym_1'],
      },
    };
  }
}

Widget _app({
  required _FakeApi api,
  required _FakeFirebase firebase,
  String? role,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.verifyEmail,
    routes: [
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) =>
            VerifyEmailScreen(requestedRole: role, authService: firebase),
      ),
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const Text('auth screen'),
      ),
      GoRoute(
        path: AppRoutes.ownerHome,
        builder: (context, state) => const Text('owner home'),
      ),
    ],
  );
  return AppScope(
    api: api,
    auth: AuthState(api),
    child: ThemeScope(
      notifier: ThemeNotifier(),
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp.router(
          theme: buildTheme(),
          routerConfig: router,
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('recognises the backend email-verification refusal only', () {
    expect(
      requiresEmailVerification({'error': 'email_verification_required'}),
      isTrue,
    );
    expect(
      requiresEmailVerification({'error': 'invalid_firebase_token'}),
      isFalse,
    );
    expect(requiresEmailVerification(null), isFalse);
    expect(requiresEmailVerification('email_verification_required'), isFalse);
  });

  test('the verify step carries the sign-up role, not a sign-in', () {
    expect(AppRoutes.verifyEmailFor(null), '/auth/verify-email');
    expect(AppRoutes.verifyEmailFor(''), '/auth/verify-email');
    expect(
      AppRoutes.verifyEmailFor('gym_owner'),
      '/auth/verify-email?role=gym_owner',
    );
  });

  testWidgets('sends the link, waits for verification, then signs in', (
    tester,
  ) async {
    final api = _FakeApi();
    final firebase = _FakeFirebase();
    await tester.pumpWidget(
      _app(api: api, firebase: firebase, role: 'gym_owner'),
    );
    await tester.pumpAndSettle();

    expect(firebase.sent, 1, reason: 'the link is sent when the step opens');
    expect(find.textContaining('owner@example.com'), findsOneWidget);

    // Not verified yet: no session attempt, and the person is told why.
    await tester.tap(find.byKey(const Key('verify-email-continue')));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(
      find.text(
        'That email is not verified yet. Open the link we sent, then try again.',
      ),
      findsOneWidget,
    );

    // Verified: retries with a fresh token and the sign-up role, then routes.
    firebase.verified = true;
    await tester.tap(find.byKey(const Key('verify-email-continue')));
    await tester.pumpAndSettle();
    expect(api.calls, [('fresh-token', 'gym_owner')]);
    expect(find.text('owner home'), findsOneWidget);
  });

  testWidgets('resend sends another link; other account signs out', (
    tester,
  ) async {
    final firebase = _FakeFirebase();
    await tester.pumpWidget(_app(api: _FakeApi(), firebase: firebase));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('verify-email-resend')));
    await tester.pumpAndSettle();
    expect(firebase.sent, 2);

    await tester.tap(find.text('Use a different account'));
    await tester.pumpAndSettle();
    expect(firebase.signedOut, isTrue);
    expect(find.text('auth screen'), findsOneWidget);
  });
}
