import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/account_recovery.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/screens/pin_flows.dart';
import 'package:fitflexmobile/screens/sign_up_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/firebase_auth_service.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/pin_credentials.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/verify_identifier.dart';

// While FitFlex cannot send email codes (emailCodes=false), email accounts stay
// on Firebase; mobile numbers use FitFlex codes and the FitFlex PIN.

class _Firebase extends FirebaseAuthService {
  final signIns = <String>[];

  @override
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    signIns.add('$email|$password');
    throw StateError('firebase stub');
  }
}

class _FakeApi extends ApiClient {
  _FakeApi({
    this.emailCodes = false,
    this.smsCodes = true,
    this.options404 = false,
  }) : super(baseUrl: 'http://localhost:0');

  final bool emailCodes;
  final bool smsCodes;
  final bool options404;
  final calls = <String>[];
  int probes = 0;

  @override
  Future<Map<String, dynamic>> signInOptions() async {
    if (options404) throw ApiException(404, {'error': 'not_found'});
    return {
      'pinLogin': true,
      'pinReset': true,
      'recovery': true,
      'smsCodes': smsCodes,
      'emailCodes': emailCodes,
    };
  }

  @override
  Future<bool> pinLoginAvailable() async {
    probes++;
    return true;
  }

  @override
  Future<bool> pinResetAvailable() async => true;

  @override
  Future<Map<String, dynamic>> pinLogin(
    Map<String, String> contact,
    String pin, {
    String? locale,
  }) async {
    calls.add('pinLogin');
    throw ApiException(401, {'error': 'invalid_credentials'});
  }

  @override
  Future<Map<String, dynamic>> registerStart(
    Map<String, String> contact,
    String? locale,
  ) async {
    calls.add('registerStart');
    return {
      'sent': true,
      'identifierValue': '+255712345678',
      'resendAfterSeconds': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> pinResetStart(
    Map<String, String> contact,
    String? locale,
  ) async {
    calls.add('resetStart');
    return {'sent': true, 'identifierValue': '+255712345678'};
  }

  @override
  Future<Map<String, dynamic>> recoveryStart(
    Map<String, String> oldContact,
    Map<String, String> newContact,
    String? locale,
  ) async {
    calls.add('recoveryStart');
    return {
      'sent': true,
      'identifierValue': '+255712345678',
      'resendAfterSeconds': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> myIdentifiers() async => {
    'identifiers': [],
    'unverified': [],
    'secondContact': {'missing': 'email'},
  };

  @override
  Future<Map<String, dynamic>> myInvitations() async =>
      throw ApiException(404, {'error': 'not_found'});
}

Future<AuthState> _auth(_FakeApi api, {bool signedIn = false}) async {
  final auth = AuthState(api);
  await auth.loadSignInOptions();
  if (signedIn) {
    await auth.signIn('jwt-member', {
      'id': 'usr_member',
      'userType': 'member',
      'approvalStatus': 'approved',
    });
    await auth.refreshIdentifiers();
  }
  return auth;
}

Widget _app(AuthState auth, Widget home) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [GoRoute(path: '/start', builder: (_, _) => home)],
    errorBuilder: (_, state) => Scaffold(body: Text('opened ${state.uri}')),
  );
  return AppScope(
    api: auth.api,
    auth: auth,
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

void _tall(WidgetTester tester, {double width = 1800}) {
  tester.view.physicalSize = Size(width, 3200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _signUp(WidgetTester tester, _FakeApi api, String contact) async {
  _tall(tester);
  final auth = await _auth(api);
  await tester.pumpWidget(_app(auth, const SignUpScreen()));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, contact);
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FilledButton).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('options set the flags; a 404 falls back to the probes', () async {
    final off = await _auth(_FakeApi());
    expect(off.pinLoginEnabled, isTrue);
    expect(off.emailCodesAvailable, isFalse);
    expect(off.smsCodesAvailable, isTrue);
    expect(usesFitFlexCodes(off, 'amina@example.com'), isFalse);
    expect(usesFitFlexCodes(off, '0712345678'), isTrue);

    final on = await _auth(_FakeApi(emailCodes: true));
    expect(usesFitFlexCodes(on, 'amina@example.com'), isTrue);

    final api = _FakeApi(options404: true);
    final old = await _auth(api);
    expect(api.probes, 1);
    expect(old.pinLoginEnabled, isTrue);
    expect(old.emailCodesAvailable, isTrue);
    expect(old.smsCodesAvailable, isTrue);
  });

  testWidgets('sign-up: an email goes to the Firebase email screen', (
    tester,
  ) async {
    final api = _FakeApi();
    await _signUp(tester, api, 'amina@example.com');
    expect(api.calls, isEmpty);
    expect(find.textContaining('opened /'), findsOneWidget);
    expect(find.textContaining('mode=signup'), findsOneWidget);
  });

  testWidgets('sign-up: a number goes to the FitFlex code flow', (
    tester,
  ) async {
    final api = _FakeApi();
    await _signUp(tester, api, '0712345678');
    expect(api.calls, ['registerStart']);
  });

  testWidgets('sign-up: a number says so when SMS codes are off', (
    tester,
  ) async {
    final api = _FakeApi(smsCodes: false);
    await _signUp(tester, api, '0712345678');
    expect(api.calls, isEmpty);
    expect(find.textContaining('not available yet'), findsOneWidget);
  });

  testWidgets('sign-up: with email codes on, an email uses FitFlex codes', (
    tester,
  ) async {
    final api = _FakeApi(emailCodes: true);
    await _signUp(tester, api, 'amina@example.com');
    expect(api.calls, ['registerStart']);
  });

  testWidgets('sign-in: an email uses Firebase, not FitFlex pinLogin', (
    tester,
  ) async {
    _tall(tester, width: 1080);
    final api = _FakeApi();
    final firebase = _Firebase();
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(
        auth,
        EmailAuthScreen(
          initialEmail: 'amina@example.com',
          authService: firebase,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _typePin(tester, '4821');
    expect(api.calls.contains('pinLogin'), isFalse);
    expect(firebase.signIns, [
      'amina@example.com|${firebasePasswordForPin('4821')}',
    ]);
    // Forgot PIN is not offered for an email.
    expect(find.byKey(const Key('forgot-pin')), findsNothing);
  });

  testWidgets('sign-in: a number uses FitFlex pinLogin and keeps Forgot PIN', (
    tester,
  ) async {
    _tall(tester, width: 1080);
    final api = _FakeApi();
    final firebase = _Firebase();
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(
        auth,
        EmailAuthScreen(initialEmail: '0712345678', authService: firebase),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forgot-pin')), findsOneWidget);
    await _typePin(tester, '4821');
    expect(api.calls, ['pinLogin']);
    expect(firebase.signIns, isEmpty);
  });

  testWidgets('sign-in: with email codes on, an email uses FitFlex pinLogin', (
    tester,
  ) async {
    _tall(tester, width: 1080);
    final api = _FakeApi(emailCodes: true);
    final firebase = _Firebase();
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(
        auth,
        EmailAuthScreen(
          initialEmail: 'amina@example.com',
          authService: firebase,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forgot-pin')), findsOneWidget);
    await _typePin(tester, '4821');
    expect(api.calls, ['pinLogin']);
    expect(firebase.signIns, isEmpty);
  });

  testWidgets('forgot PIN: an email gets a message, a number goes on', (
    tester,
  ) async {
    _tall(tester, width: 1080);
    final api = _FakeApi();
    final auth = await _auth(api);
    await tester.pumpWidget(_app(auth, const ForgotPinScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('pin-flow-contact')),
      'amina@example.com',
    );
    await tester.tap(find.byKey(const Key('pin-flow-send')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Resetting a PIN by email is not available yet. Use your mobile number if you have added one.',
      ),
      findsOneWidget,
    );
    expect(api.calls, isEmpty);

    await tester.enterText(
      find.byKey(const Key('pin-flow-contact')),
      '0712345678',
    );
    await tester.tap(find.byKey(const Key('pin-flow-send')));
    await tester.pumpAndSettle();
    expect(api.calls, ['resetStart']);
  });

  testWidgets('recovery: an email as the NEW contact is refused', (
    tester,
  ) async {
    _tall(tester, width: 1080);
    final api = _FakeApi();
    final auth = await _auth(api);
    await tester.pumpWidget(_app(auth, const AccountRecoveryScreen()));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'old@example.com');
    await tester.enterText(fields.at(1), 'new@example.com');
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-error')), findsOneWidget);
    expect(api.calls, isEmpty);

    // An email as the OLD contact is fine when the new one is a number.
    await tester.enterText(fields.at(1), '0712345678');
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(api.calls, ['recoveryStart']);
  });

  testWidgets('recovery: with email codes on, an email as NEW is sent', (
    tester,
  ) async {
    _tall(tester, width: 1080);
    final api = _FakeApi(emailCodes: true);
    final auth = await _auth(api);
    await tester.pumpWidget(_app(auth, const AccountRecoveryScreen()));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'old@example.com');
    await tester.enterText(fields.at(1), 'new@example.com');
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(api.calls, ['recoveryStart']);
  });

  testWidgets('second-contact card: no email suggestion without email codes', (
    tester,
  ) async {
    _tall(tester, width: 1080);
    final auth = await _auth(_FakeApi(), signedIn: true);
    await tester.pumpWidget(
      _app(auth, const Scaffold(body: ContactDetailsTile())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('second-contact-card')), findsNothing);
  });

  testWidgets('second-contact card: email suggested when email codes are on', (
    tester,
  ) async {
    _tall(tester, width: 1080);
    final auth = await _auth(_FakeApi(emailCodes: true), signedIn: true);
    await tester.pumpWidget(
      _app(auth, const Scaffold(body: ContactDetailsTile())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('second-contact-card')), findsOneWidget);
  });
}
