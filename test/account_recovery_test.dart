import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/account_recovery.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/verify_identifier.dart';

// Identity V2 · account recovery (member path) and the "add a second
// contact" reminder.

class _FakeApi extends ApiClient {
  _FakeApi({this.recoveryOn = true}) : super(baseUrl: 'http://localhost:0');

  final bool recoveryOn;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  final errors = <String, ApiException>{};
  Map<String, dynamic> status = {
    'status': 'open',
    'waitUntil': '2026-10-06T08:00:00.000Z',
    'answered': <String>[],
  };
  Map<String, dynamic> mine = {'open': false};
  Map<String, dynamic>? secondContact;

  Map<String, dynamic> _do(
    String name,
    Map<String, dynamic> body,
    Map<String, dynamic> ok,
  ) {
    calls.add(name);
    bodies.add(body);
    final error = errors.remove(name);
    if (error != null) throw error;
    return ok;
  }

  @override
  Future<bool> pinLoginAvailable() async => recoveryOn;
  @override
  Future<bool> pinResetAvailable() async => recoveryOn;

  @override
  Future<Map<String, dynamic>> recoveryStart(
    Map<String, String> oldContact,
    Map<String, String> newContact,
    String? locale,
  ) async => _do(
    'start',
    {'old': oldContact, 'new': newContact},
    {'sent': true, 'identifierValue': '+255712345678', 'resendAfterSeconds': 0},
  );

  @override
  Future<Map<String, dynamic>> recoveryConfirm(
    Map<String, String> oldContact,
    Map<String, String> newContact,
    String code,
    String name,
    String? locale,
  ) async => _do(
    'confirm',
    {'old': oldContact, 'new': newContact, 'code': code, 'name': name},
    {
      'requested': true,
      'status': 'open',
      'waitHours': 24,
      'requestToken': 'req-token',
      'questions': ['homeGym'],
    },
  );

  @override
  Future<Map<String, dynamic>> recoveryEvidence(
    String requestToken,
    Map<String, String> answers,
  ) async => _do('evidence', {
    'requestToken': requestToken,
    'answers': answers,
  }, status);

  @override
  Future<Map<String, dynamic>> recoveryStatus(String requestToken) async =>
      _do('status', {'requestToken': requestToken}, status);

  @override
  Future<Map<String, dynamic>> recoveryCancel(String requestToken) async {
    status = {'status': 'cancelled'};
    return _do('cancel', {'requestToken': requestToken}, {'cancelled': true});
  }

  @override
  Future<Map<String, dynamic>> myRecovery() async {
    if (!recoveryOn) throw ApiException(404, {'error': 'not_found'});
    return mine;
  }

  @override
  Future<Map<String, dynamic>> cancelMyRecovery() async {
    mine = {'open': false};
    return _do('cancelMine', {}, {'cancelled': true});
  }

  @override
  Future<Map<String, dynamic>> pinResetStart(
    Map<String, String> contact,
    String? locale,
  ) async => _do(
    'resetStart',
    {...contact},
    {'sent': true, 'identifierValue': '+255712345678', 'resendAfterSeconds': 0},
  );

  @override
  Future<Map<String, dynamic>> myIdentifiers() async => {
    'identifiers': [
      {'type': 'email', 'value': 'amina@example.com', 'verified': true},
    ],
    'unverified': <Map<String, dynamic>>[],
    'secondContact': secondContact,
  };

  @override
  Future<Map<String, dynamic>> myInvitations() async =>
      throw ApiException(404, {'error': 'not_found'});
}

Widget _app(AuthState auth, Widget home) {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => home)],
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
          builder: (context, child) =>
              RecoveryBannerHost(child: child ?? const SizedBox.shrink()),
        ),
      ),
    ),
  );
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

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _openScreen(
  WidgetTester tester,
  _FakeApi api,
  Widget screen,
) async {
  _tall(tester);
  final auth = await _auth(api);
  // Pushed from a first page, so a screen can pop back to something.
  await tester.pumpWidget(
    _app(
      auth,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('open-screen'),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => screen)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-screen')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the sign-in link shows only while recovery is on', (
    tester,
  ) async {
    await _openScreen(
      tester,
      _FakeApi(recoveryOn: false),
      const EmailAuthScreen(initialEmail: 'amina@example.com'),
    );
    expect(find.byKey(const Key('recovery-link')), findsNothing);

    await _openScreen(
      tester,
      _FakeApi(),
      const EmailAuthScreen(initialEmail: 'amina@example.com'),
    );
    expect(find.text("I can't access my number or email"), findsOneWidget);
    expect(find.byKey(const Key('recovery-check')), findsNothing);
  });

  testWidgets('a saved request token adds "Check my recovery request"', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'recovery_request_token': 'req-token',
    });
    await _openScreen(
      tester,
      _FakeApi(),
      const EmailAuthScreen(initialEmail: 'amina@example.com'),
    );
    await tester.tap(find.byKey(const Key('recovery-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-open')), findsOneWidget);
  });

  testWidgets('details, code and name, questions, then the status', (
    tester,
  ) async {
    final api = _FakeApi();
    await _openScreen(tester, api, const AccountRecoveryScreen());

    await tester.enterText(
      find.byKey(const Key('recovery-old')),
      'old@example.com',
    );
    await tester.enterText(find.byKey(const Key('recovery-new')), '0712345678');
    await tester.tap(find.byKey(const Key('recovery-request')));
    await tester.pumpAndSettle();
    expect(api.bodies.last, {
      'old': {'email': 'old@example.com'},
      'new': {'phone': '0712345678'},
    });

    await tester.enterText(
      find.byKey(const Key('recovery-name')),
      'Asha Mushi',
    );
    await tester.enterText(find.byKey(const Key('pin-flow-code')), '123456');
    await tester.tap(find.byKey(const Key('pin-flow-code-continue')));
    await tester.pumpAndSettle();
    expect(api.bodies.last['code'], '123456');
    expect(api.bodies.last['name'], 'Asha Mushi');
    expect(
      (await SharedPreferences.getInstance()).getString(
        'recovery_request_token',
      ),
      'req-token',
    );

    // At least one answer is needed.
    await tester.tap(find.byKey(const Key('recovery-send-answers')));
    await tester.pumpAndSettle();
    expect(find.text('Answer at least one question.'), findsOneWidget);
    expect(api.calls.contains('evidence'), isFalse);

    await tester.enterText(
      find.byKey(const Key('recovery-answer-homeGym')),
      'Fit Zone',
    );
    await tester.tap(find.byKey(const Key('recovery-send-answers')));
    await tester.pumpAndSettle();
    expect(api.bodies[api.calls.indexOf('evidence')], {
      'requestToken': 'req-token',
      'answers': {'homeGym': 'Fit Zone'},
    });
    expect(find.byKey(const Key('recovery-open')), findsOneWidget);
  });

  testWidgets('a name is required with the code', (tester) async {
    final api = _FakeApi();
    await _openScreen(tester, api, const AccountRecoveryScreen());
    await tester.enterText(find.byKey(const Key('recovery-old')), 'a@b.co');
    await tester.enterText(find.byKey(const Key('recovery-new')), '0712345678');
    await tester.tap(find.byKey(const Key('recovery-request')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-flow-code')), '123456');
    await tester.tap(find.byKey(const Key('pin-flow-code-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the full name on your account.'), findsOneWidget);
    expect(api.calls.contains('confirm'), isFalse);
  });

  testWidgets('errors are explained: blocked, and staff accounts', (
    tester,
  ) async {
    final api = _FakeApi();
    await _openScreen(tester, api, const AccountRecoveryScreen());
    await tester.enterText(find.byKey(const Key('recovery-old')), 'a@b.co');
    await tester.enterText(find.byKey(const Key('recovery-new')), '0712345678');

    api.errors['start'] = ApiException(429, {
      'error': 'recovery_blocked',
      'retryAfterSeconds': 3 * 86400 - 60,
    });
    await tester.tap(find.byKey(const Key('recovery-request')));
    await tester.pumpAndSettle();
    expect(
      find.text('A recent request was closed. Please try again in 3 days.'),
      findsOneWidget,
    );

    api.errors['start'] = ApiException(409, {
      'error': 'staff_recovery_not_available',
    });
    await tester.tap(find.byKey(const Key('recovery-request')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ask your gym or vendor'), findsOneWidget);

    api.errors['start'] = ApiException(409, {
      'error': 'partner_recovery_not_available',
    });
    await tester.tap(find.byKey(const Key('recovery-request')));
    await tester.pumpAndSettle();
    expect(find.text('Please contact FitFlex support.'), findsOneWidget);
  });

  testWidgets('status: open shows the wait and what is answered; cancel', (
    tester,
  ) async {
    final api = _FakeApi()
      ..status = {
        'status': 'open',
        'waitUntil': '2026-10-06T08:00:00.000Z',
        'answered': ['homeGym'],
      };
    await _openScreen(
      tester,
      api,
      const RecoveryStatusScreen(requestToken: 'req-token'),
    );
    expect(find.byKey(const Key('recovery-open')), findsOneWidget);
    expect(find.textContaining('Answered: '), findsOneWidget);

    await tester.tap(find.byKey(const Key('recovery-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recovery-cancel-yes')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('cancel'));
    expect(find.byKey(const Key('recovery-cancelled')), findsOneWidget);
  });

  testWidgets('status: refused gives a general reason and when to retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'recovery_request_token': 'req-token',
    });
    final api = _FakeApi()
      ..status = {
        'status': 'refused',
        'reason': 'evidence_insufficient',
        'retryAfter': '2026-10-13T08:00:00.000Z',
      };
    await _openScreen(
      tester,
      api,
      const RecoveryStatusScreen(requestToken: 'req-token'),
    );
    expect(find.byKey(const Key('recovery-refused')), findsOneWidget);
    expect(find.textContaining('not enough'), findsOneWidget);
    expect(find.textContaining('You can ask again after'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recovery-ack')));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        'recovery_request_token',
      ),
      isNull,
    );
  });

  testWidgets('status: completed leads to Forgot PIN for the new number', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'recovery_request_token': 'req-token',
    });
    final api = _FakeApi()
      ..status = {
        'status': 'completed',
        'next': 'forgot_pin',
        'identifierType': 'phone',
        'identifierValue': '+255712345678',
      };
    await _openScreen(
      tester,
      api,
      const RecoveryStatusScreen(requestToken: 'req-token'),
    );
    await tester.tap(find.byKey(const Key('recovery-set-pin')));
    await tester.pumpAndSettle();
    expect(find.text('Reset your PIN'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('pin-flow-contact')))
          .controller!
          .text,
      '+255712345678',
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        'recovery_request_token',
      ),
      isNull,
    );
  });

  testWidgets('a signed-in device shows the banner and can cancel', (
    tester,
  ) async {
    final api = _FakeApi()
      ..mine = {
        'open': true,
        'waitUntil': '2026-10-06T08:00:00.000Z',
        'newIdentifierType': 'phone',
        'newIdentifier': '+255•••••678',
      };
    _tall(tester);
    final auth = await _auth(api, signedIn: true);
    await tester.pumpWidget(_app(auth, const Scaffold(body: Text('home'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-banner')), findsOneWidget);
    expect(find.textContaining('+255•••••678'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recovery-banner-cancel')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('cancelMine'));
    expect(find.byKey(const Key('recovery-banner')), findsNothing);
  });

  testWidgets('no banner when nothing is open, signed out, or flag off', (
    tester,
  ) async {
    _tall(tester);
    var api = _FakeApi();
    await tester.pumpWidget(
      _app(await _auth(api, signedIn: true), const Scaffold(body: Text('h'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-banner')), findsNothing);

    api = _FakeApi(recoveryOn: false)..mine = {'open': true};
    await tester.pumpWidget(
      _app(await _auth(api, signedIn: true), const Scaffold(body: Text('h'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-banner')), findsNothing);
  });

  testWidgets('the reminder shows for secondContact, not when null', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi()..secondContact = {'missing': 'phone'};
    var auth = await _auth(api, signedIn: true);
    await tester.pumpWidget(
      _app(auth, const Scaffold(body: ContactDetailsTile())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('second-contact-card')), findsOneWidget);
    expect(
      find.text('Add a mobile number too, so you can always get back in'),
      findsOneWidget,
    );

    // The button opens the verify screen for that kind.
    await tester.tap(find.byKey(const Key('second-contact-add')));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyIdentifierScreen), findsOneWidget);
    expect(
      tester
          .widget<VerifyIdentifierScreen>(find.byType(VerifyIdentifierScreen))
          .type,
      'phone',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Dismissed for the session.
    await tester.tap(find.byKey(const Key('second-contact-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('second-contact-card')), findsNothing);

    api.secondContact = null;
    auth = await _auth(api, signedIn: true);
    await tester.pumpWidget(
      _app(auth, const Scaffold(body: ContactDetailsTile())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('second-contact-card')), findsNothing);
  });
}
