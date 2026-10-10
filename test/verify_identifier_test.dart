import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/invitations.dart';
import 'package:fitflexmobile/shared/widgets/verify_identifier.dart';

// Identity V2 · I6a: a FitFlex code proves a mobile number or email once.

class _FakeApi extends ApiClient {
  _FakeApi({this.enabled = true}) : super(baseUrl: 'http://localhost:0');

  final bool enabled;
  List<Map<String, dynamic>> verified = [];
  List<Map<String, dynamic>> unverified = [];
  List<Map<String, dynamic>> invitations = [];
  final requests = <Map<String, dynamic>>[];
  bool resetOn = true;
  final changeRequests = <Map<String, dynamic>>[];
  final changeConfirms = <Map<String, dynamic>>[];
  ApiException? changeError;

  @override
  Future<bool> pinLoginAvailable() async => true;
  @override
  Future<bool> pinResetAvailable() async => resetOn;

  @override
  Future<Map<String, dynamic>> requestIdentifierChange({
    String? phone,
    String? email,
    required String pin,
    String? locale,
  }) async {
    changeRequests.add({'phone': ?phone, 'email': ?email, 'pin': pin});
    final error = changeError;
    changeError = null;
    if (error != null) throw error;
    return {'sent': true};
  }

  @override
  Future<Map<String, dynamic>> confirmIdentifierChange({
    String? phone,
    String? email,
    required String code,
    String? locale,
  }) async {
    changeConfirms.add({'phone': ?phone, 'email': ?email, 'code': code});
    verified = [
      {'type': 'phone', 'value': phone ?? email},
    ];
    return {'changed': true};
  }

  final confirms = <Map<String, dynamic>>[];
  ApiException? requestError;
  ApiException? confirmError;
  String? openError = 'identifier_not_verified';
  int opened = 0;

  @override
  Future<Map<String, dynamic>> myIdentifiers() async {
    if (!enabled) throw ApiException(404, {'error': 'not_found'});
    return {'identifiers': verified, 'unverified': unverified};
  }

  @override
  Future<Map<String, dynamic>> requestIdentifierCode({
    String? phone,
    String? email,
    String? locale,
  }) async {
    requests.add({'phone': ?phone, 'email': ?email, 'locale': ?locale});
    if (requestError != null) throw requestError!;
    return {'sent': true, 'resendAfterSeconds': 0};
  }

  @override
  Future<Map<String, dynamic>> confirmIdentifierCode({
    String? phone,
    String? email,
    required String code,
  }) async {
    confirms.add({'phone': ?phone, 'email': ?email, 'code': code});
    if (confirmError != null) throw confirmError!;
    final value = phone ?? email!;
    verified = [
      ...verified,
      {'type': phone != null ? 'phone' : 'email', 'value': value},
    ];
    unverified = unverified.where((u) => u['value'] != value).toList();
    openError = null;
    return {'verified': true};
  }

  @override
  Future<Map<String, dynamic>> myInvitations() async => {
    'invitations': invitations,
  };

  @override
  Future<Map<String, dynamic>> openInvitation(String token) async {
    opened += 1;
    if (openError != null) {
      throw ApiException(403, {'error': openError, 'identifierType': 'phone'});
    }
    return {'invitation': {}};
  }
}

Future<AuthState> _signedIn(_FakeApi api) async {
  final auth = AuthState(api);
  await auth.signIn('jwt-member', {
    'id': 'usr_member',
    'userType': 'member',
    'approvalStatus': 'approved',
  });
  await auth.refreshIdentifiers();
  return auth;
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
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('identifiers follow the backend flag', () async {
    final off = await _signedIn(_FakeApi(enabled: false));
    expect(off.identifiersEnabled, isFalse);

    final api = _FakeApi()
      ..unverified = [
        {'type': 'phone', 'value': '+255712345678'},
      ];
    final on = await _signedIn(api);
    expect(on.identifiersEnabled, isTrue);
    expect(on.unverifiedIdentifiers.single['value'], '+255712345678');
    await on.signOut();
    expect(on.identifiersEnabled, isFalse);
    expect(on.unverifiedIdentifiers, isEmpty);
  });

  testWidgets('flag off: no profile entry', (tester) async {
    final auth = await _signedIn(_FakeApi(enabled: false));
    await tester.pumpWidget(
      _app(auth, const Scaffold(body: ContactDetailsTile())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact-details-tile')), findsNothing);
  });

  testWidgets('verify a profile mobile number: send the code, confirm it', (
    tester,
  ) async {
    final api = _FakeApi()
      ..unverified = [
        {'type': 'phone', 'value': '+255712345678'},
      ];
    final auth = await _signedIn(api);
    await tester.pumpWidget(
      _app(auth, const Scaffold(body: ContactDetailsTile())),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 not verified yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('contact-details-tile')));
    await tester.pumpAndSettle();
    expect(find.text('Not verified'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verify-+255712345678')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verify-code')), findsNothing);
    await tester.tap(find.byKey(const Key('verify-send')));
    await tester.pumpAndSettle();
    expect(api.requests.single, {'phone': '+255712345678', 'locale': 'en'});
    expect(find.text('We sent a code by SMS. Enter it below.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('verify-code')), '123456');
    await tester.tap(find.byKey(const Key('verify-confirm')));
    await tester.pumpAndSettle();
    expect(api.confirms.single, {'phone': '+255712345678', 'code': '123456'});

    // Back on the list, now verified, and nothing left to add.
    expect(find.text('Verified'), findsOneWidget);
    expect(find.byKey(const Key('add-phone')), findsNothing);
    expect(auth.verifiedIdentifiers.single['value'], '+255712345678');
  });

  testWidgets(
    'a wrong code says how many tries are left and clears the field',
    (tester) async {
      final api = _FakeApi()
        ..confirmError = ApiException(400, {
          'error': 'code_incorrect',
          'attemptsLeft': 2,
        });
      final auth = await _signedIn(api);
      await tester.pumpWidget(
        _app(
          auth,
          const VerifyIdentifierScreen(type: 'email', initialValue: 'a@b.co'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('verify-send')));
      await tester.pumpAndSettle();
      expect(api.requests.single, {'email': 'a@b.co', 'locale': 'en'});
      await tester.enterText(find.byKey(const Key('verify-code')), '000000');
      await tester.tap(find.byKey(const Key('verify-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.text('That code is not right. Tries left: 2.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('verify-code')))
            .controller!
            .text,
        isEmpty,
      );
      expect(auth.verifiedIdentifiers, isEmpty);
    },
  );

  testWidgets('a number verified on another account is refused with a reason', (
    tester,
  ) async {
    final api = _FakeApi()
      ..requestError = ApiException(409, {'error': 'identifier_in_use'});
    final auth = await _signedIn(api);
    await tester.pumpWidget(
      _app(auth, const VerifyIdentifierScreen(type: 'phone')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('verify-value')), '0712345678');
    await tester.tap(find.byKey(const Key('verify-send')));
    await tester.pumpAndSettle();
    expect(
      find.text('This is already verified on another FitFlex account.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('verify-code')), findsNothing);
  });

  testWidgets(
    'an invitation sent to an unverified number offers to verify it',
    (tester) async {
      final api = _FakeApi();
      final auth = await _signedIn(api);
      await tester.pumpWidget(
        _app(auth, const InvitationsScreen(token: 'tok')),
      );
      await tester.pumpAndSettle();
      expect(api.opened, 1);
      await tester.tap(find.byKey(const Key('invitations-verify')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('verify-value')),
        '0712345678',
      );
      await tester.tap(find.byKey(const Key('verify-send')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('verify-code')), '123456');
      await tester.tap(find.byKey(const Key('verify-confirm')));
      await tester.pumpAndSettle();

      // Back on the invitations screen, the link is opened again and now works.
      expect(api.opened, 2);
      expect(find.byKey(const Key('invitations-verify')), findsNothing);
      expect(find.byKey(const Key('invitations-notice')), findsNothing);
    },
  );

  testWidgets(
    'change a verified number: the new one and the PIN, then the code',
    (tester) async {
      final api = _FakeApi()
        ..verified = [
          {'type': 'phone', 'value': '+255712345678'},
        ];
      final auth = await _signedIn(api);
      await auth.loadSignInOptions();
      await tester.pumpWidget(_app(auth, const ContactDetailsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('change-+255712345678')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You sign in with +255712345678'),
        findsOneWidget,
      );

      // Both are needed before anything is sent.
      await tester.enterText(
        find.byKey(const Key('change-value')),
        '0799000111',
      );
      await tester.tap(find.byKey(const Key('change-send')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the new one and your PIN.'), findsOneWidget);
      expect(api.changeRequests, isEmpty);

      // A wrong PIN is said plainly and sends no code.
      api.changeError = ApiException(400, {'error': 'pin_incorrect'});
      await tester.enterText(find.byKey(const Key('change-pin')), '0000');
      await tester.tap(find.byKey(const Key('change-send')));
      await tester.pumpAndSettle();
      expect(find.text('Your current PIN is not right.'), findsOneWidget);
      expect(find.byKey(const Key('change-code')), findsNothing);

      await tester.enterText(find.byKey(const Key('change-pin')), '4821');
      await tester.tap(find.byKey(const Key('change-send')));
      await tester.pumpAndSettle();
      expect(api.changeRequests.last, {'phone': '0799000111', 'pin': '4821'});
      await tester.enterText(find.byKey(const Key('change-code')), '123456');
      await tester.tap(find.byKey(const Key('change-confirm')));
      await tester.pumpAndSettle();
      expect(api.changeConfirms.single, {
        'phone': '0799000111',
        'code': '123456',
      });

      // Back on the list, showing the new number.
      expect(find.text('0799000111'), findsOneWidget);
      expect(find.text('+255712345678'), findsNothing);
      expect(
        find.text('Changed. The old one no longer signs in.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Change is not offered while the backend has it off', (
    tester,
  ) async {
    final api = _FakeApi()
      ..resetOn = false
      ..verified = [
        {'type': 'email', 'value': 'a@b.co'},
      ];
    final auth = await _signedIn(api);
    await auth.loadSignInOptions();
    await tester.pumpWidget(_app(auth, const ContactDetailsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('a@b.co'), findsOneWidget);
    expect(find.byKey(const Key('change-a@b.co')), findsNothing);
  });
}
