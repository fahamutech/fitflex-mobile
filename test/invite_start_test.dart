import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/screens/pin_flows.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/invitations.dart';

// Invitation sign-in with a start PIN: someone new signs in with the PIN
// FitFlex sent them, gives their name, chooses their own PIN, then accepts or
// declines. With nothing accepted they choose a role.

Map<String, dynamic> _session(String userType) => {
  'token': 'jwt-new',
  'user': {
    'id': 'usr_1',
    'userType': userType,
    'approvalStatus': 'approved',
    'onboardingCompleted': true,
  },
};

Map<String, dynamic> _step([List<Map<String, dynamic>>? invitations]) => {
  'onboarding': true,
  'onboardingToken': 'onb-token',
  'invitations':
      invitations ??
      [
        {'id': 'inv_1', 'orgName': 'Iron Paradise', 'role': 'staff'},
      ],
};

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0');

  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  Map<String, dynamic> loginResponse = {};
  Map<String, dynamic>? createResponse;
  ApiException? beginError;

  @override
  Future<bool> pinLoginAvailable() async => true;
  @override
  Future<bool> pinResetAvailable() async => true;

  @override
  Future<Map<String, dynamic>> pinLogin(
    Map<String, String> contact,
    String pin, {
    String? locale,
  }) async {
    calls.add('login');
    bodies.add({...contact, 'pin': pin});
    return loginResponse;
  }

  @override
  Future<Map<String, dynamic>> inviteBegin({
    required String startToken,
    required String displayName,
    required String pin,
  }) async {
    calls.add('begin');
    bodies.add({
      'startToken': startToken,
      'displayName': displayName,
      'pin': pin,
    });
    final error = beginError;
    beginError = null;
    if (error != null) throw error;
    return _step();
  }

  @override
  Future<Map<String, dynamic>> onboardingAnswer(
    String onboardingToken,
    String invitationId, {
    required bool accept,
  }) async {
    calls.add(accept ? 'accept' : 'decline');
    bodies.add({
      'onboardingToken': onboardingToken,
      'invitationId': invitationId,
    });
    return accept ? _session('gym_staff') : _step([]);
  }

  @override
  Future<Map<String, dynamic>> onboardingRole(
    String onboardingToken,
    String role,
  ) async {
    calls.add('role');
    bodies.add({'onboardingToken': onboardingToken, 'role': role});
    return _session(role == 'gym_owner' ? 'gym_operator' : role);
  }

  @override
  Future<Map<String, dynamic>> gymLookupPerson(
    String gymId, {
    String? phone,
    String? email,
    String orgType = 'gym',
  }) async => {'found': false, 'maskedName': null};

  @override
  Future<Map<String, dynamic>> gymCreateInvitation(
    String gymId,
    Map<String, dynamic> body, {
    String orgType = 'gym',
  }) async => createResponse!;

  @override
  Future<Map<String, dynamic>> myInvitations() async =>
      throw ApiException(404, {'error': 'not_found'});
  @override
  Future<Map<String, dynamic>> myIdentifiers() async =>
      throw ApiException(404, {'error': 'not_found'});
}

Future<AuthState> _auth(_FakeApi api) async {
  final auth = AuthState(api);
  await auth.loadSignInOptions();
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

Future<void> _typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'start PIN → name → own PIN typed twice → Accept → signed in as the invited role',
    (tester) async {
      _tall(tester);
      final api = _FakeApi()
        ..loginResponse = {
          'startPin': true,
          'startToken': 'start-token',
          'invitation': {'orgType': 'gym', 'role': 'staff'},
        };
      final auth = await _auth(api);
      await tester.pumpWidget(
        _app(auth, const EmailAuthScreen(initialEmail: '0712345678')),
      );
      await tester.pumpAndSettle();
      await _typePin(tester, '6601');
      expect(api.bodies.last, {'phone': '0712345678', 'pin': '6601'});
      expect(find.text('Welcome to FitFlex'), findsOneWidget);
      expect(find.textContaining('invited to join as Staff'), findsOneWidget);
      expect(auth.isSignedIn, isFalse);

      // A name is required before the PIN.
      await tester.tap(find.byKey(const Key('start-name-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('start-name')),
        'Neema Abdallah',
      );
      await tester.tap(find.byKey(const Key('start-name-continue')));
      await tester.pumpAndSettle();

      await _typePin(tester, '4821');
      await _typePin(tester, '4821');
      expect(api.bodies.last, {
        'startToken': 'start-token',
        'displayName': 'Neema Abdallah',
        'pin': '4821',
      });
      expect(auth.isSignedIn, isFalse, reason: 'accepting is a separate step');
      expect(find.text('Iron Paradise'), findsOneWidget);
      expect(find.text('Invites you to join as Staff'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding-accept-inv_1')));
      await tester.pumpAndSettle();
      expect(api.bodies.last, {
        'onboardingToken': 'onb-token',
        'invitationId': 'inv_1',
      });
      expect(auth.isSignedIn, isTrue);
      expect(auth.user?['userType'], 'gym_staff');
      expect(find.textContaining('opened'), findsOneWidget);
    },
  );

  testWidgets('declining leads to the role choice, and choosing signs in', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi();
    final auth = await _auth(api);
    await tester.pumpWidget(_app(auth, OnboardingScreen(step: _step())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding-decline-inv_1')));
    await tester.pumpAndSettle();
    expect(api.calls, ['decline']);
    expect(auth.isSignedIn, isFalse);
    expect(find.text('Iron Paradise'), findsNothing);
    expect(find.text('Gym Member'), findsOneWidget);
    expect(find.text('Personal Trainer'), findsOneWidget);
    expect(find.text('Gym Owner'), findsOneWidget);
    expect(find.text('Fitness Vendor'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-role-gym_owner')));
    await tester.pumpAndSettle();
    expect(api.bodies.last, {
      'onboardingToken': 'onb-token',
      'role': 'gym_owner',
    });
    expect(auth.isSignedIn, isTrue);
    expect(auth.user?['userType'], 'gym_operator');
  });

  testWidgets('signing in with no profile yet opens the same choice', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi()..loginResponse = _step([]);
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(auth, const EmailAuthScreen(initialEmail: 'juma@example.com')),
    );
    await tester.pumpAndSettle();
    await _typePin(tester, '7310');
    expect(auth.isSignedIn, isFalse);
    expect(find.byKey(const Key('onboarding-role-member')), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-role-member')));
    await tester.pumpAndSettle();
    expect(auth.user?['userType'], 'member');
  });

  testWidgets('a start step that took too long says to start again', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi()
      ..beginError = ApiException(401, {'error': 'start_token_invalid'});
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(auth, const InviteStartScreen(startToken: 'old')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('start-name')), 'Neema');
    await tester.tap(find.byKey(const Key('start-name-continue')));
    await tester.pumpAndSettle();
    await _typePin(tester, '4821');
    await _typePin(tester, '4821');
    expect(
      find.text('That took too long. Please start again.'),
      findsOneWidget,
    );
    expect(auth.isSignedIn, isFalse);
  });

  testWidgets('the invite sheet says when FitFlex told the person itself', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi()
      ..createResponse = {
        'created': true,
        'token': 'tok-1',
        'invitation': {'id': 'inv_new'},
        'delivery': {'sent': true, 'channel': 'sms', 'startPin': true},
      };
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(
        auth,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openInvitePersonSheet(
                context,
                gymId: 'gym_1',
                role: 'trainer',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invite-contact')),
      '0712345678',
    );
    await tester.tap(find.byKey(const Key('invite-send')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('FitFlex gave them a start PIN'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('invite-copy-link')), findsOneWidget);
  });
}
