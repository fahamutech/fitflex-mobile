import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/owner/owner_staff_page.dart';
import 'package:fitflexmobile/screens/pin_flows.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

import 'support/recording_api.dart';

// Phase B · B3 (mobile): gym staff whose PIN their owner chose must choose
// their own before anything else, and owners can reset a staff PIN.
// Backend contract: fitflex-functions#260 (flag STAFF_PIN_CHANGE_REQUIRED).

const _heldStaff = <String, dynamic>{
  'id': 'stf_1',
  'userType': 'gym_staff',
  'approvalStatus': 'approved',
  'displayName': 'Neema',
  'passwordChangeRequired': true,
};

/// A gym staff user; [held] null leaves the field out (server flag off).
Map<String, dynamic> _staff({bool? held}) => {
  ...Map.of(_heldStaff)..remove('passwordChangeRequired'),
  'passwordChangeRequired': ?held,
};

Map<String, dynamic> _changedSession() => {
  'token': 'jwt-after-change',
  'user': {..._heldStaff, 'passwordChangeRequired': false},
  'partnerVerified': null,
};

final _ownerHomeRoute = GoRoute(
  path: AppRoutes.ownerHome,
  builder: (_, _) => const Scaffold(body: Text('ROUTE-OWNER-HOME')),
);

Future<void> _typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Chooses [pin] and confirms it on the PIN pad.
Future<void> _chooseAndConfirm(WidgetTester tester, String pin) async {
  await _typePin(tester, pin);
  await _typePin(tester, pin);
}

Future<PageHost> _pumpScreen(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  Size size = const Size(360, 740),
}) => pumpPage(
  tester,
  api,
  const StaffPinChangeScreen(),
  user: _heldStaff,
  lang: lang,
  size: size,
  extraRoutes: [_ownerHomeRoute],
);

/// The real router (redirects included) around [auth], at [to].
Future<String> _landing(WidgetTester tester, AuthState auth, String to) async {
  final router = buildRouter(auth);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    AppScope(
      api: auth.api,
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
  router.go(to);
  await tester.pump();
  await tester.pump();
  final location = router.state.matchedLocation;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
  return location;
}

Future<AuthState> _signedIn(Map<String, dynamic> user) async {
  final auth = AuthState(ApiClient(baseUrl: 'http://fixtures.local'));
  await auth.signIn('jwt-start', Map<String, dynamic>.from(user));
  return auth;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('contract', () {
    test(
      'the change and the reset send exactly what the server reads',
      () async {
        final api = RecordingApi();
        api.on('POST /auth/pin/change', _changedSession());
        api.on('POST /owner/staff/stf_1/pin', {..._heldStaff});
        await api.run(() async {
          final client = ApiClient(baseUrl: 'http://fixtures.local');
          client.setToken('jwt-start');
          final res = await client.staffChangeStartPin('4821');
          expect(res['token'], 'jwt-after-change');
          await client.ownerResetStaffPin('stf_1', '7777');
        });
        expect(api.only('POST', '/auth/pin/change').body, {'newPin': '4821'});
        expect(api.only('POST', '/owner/staff/stf_1/pin').body, {
          'pin': '7777',
        });
      },
    );
  });

  group('the hold', () {
    test('held staff land on the PIN screen; flag off (field absent or '
        'false) lands as before', () async {
      expect(
        routeForSignedInUser(await _signedIn(_staff(held: true))),
        AppRoutes.staffPinChange,
      );
      expect(
        routeForSignedInUser(await _signedIn(_staff(held: false))),
        AppRoutes.ownerHome,
      );
      final flagOff = await _signedIn(_staff());
      expect(flagOff.pinChangeRequired, isFalse);
      expect(routeForSignedInUser(flagOff), AppRoutes.ownerHome);
      // Only gym staff are held by this screen; other roles are unchanged.
      final member = await _signedIn({
        'id': 'm1',
        'userType': 'member',
        'approvalStatus': 'approved',
        'onboardingCompleted': true,
        'passwordChangeRequired': true,
      });
      expect(member.pinChangeRequired, isFalse);
      expect(routeForSignedInUser(member), AppRoutes.memberHome);
    });

    testWidgets('the router keeps held staff on the PIN screen: no scanner, '
        'no check-ins, no home', (tester) async {
      for (final to in [
        AppRoutes.ownerHome,
        AppRoutes.ownerQrScanner,
        '/owner/gyms/g1/checkins',
        AppRoutes.ownerMembers,
        AppRoutes.inbox,
      ]) {
        final auth = await _signedIn(_staff(held: true));
        expect(
          await _landing(tester, auth, to),
          AppRoutes.staffPinChange,
          reason: to,
        );
      }
      // Not held (flag off): the PIN screen sends them home, and the
      // scanner opens as before.
      final free = await _signedIn(_staff());
      expect(
        await _landing(tester, free, AppRoutes.staffPinChange),
        AppRoutes.ownerHome,
      );
      expect(
        await _landing(
          tester,
          await _signedIn(_staff()),
          AppRoutes.ownerQrScanner,
        ),
        AppRoutes.ownerQrScanner,
      );
    });

    testWidgets('a 403 password_change_required from any route holds the '
        'session and routes to the PIN screen', (tester) async {
      final api = RecordingApi();
      api.fail('GET /owner/staff', 403, {'error': 'password_change_required'});
      api.fail('GET /owner/gyms', 403, {'error': 'forbidden'});
      await api.run(() async {
        final auth = await _signedIn(_staff());
        expect(auth.pinChangeRequired, isFalse);

        // Any other 403 changes nothing.
        await expectLater(auth.api.ownerGyms(), throwsA(isA<ApiException>()));
        expect(auth.pinChangeRequired, isFalse);

        await expectLater(
          auth.api.ownerStaff(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'password_change_required',
            ),
          ),
        );
        expect(auth.pinChangeRequired, isTrue);
        expect(routeForSignedInUser(auth), AppRoutes.staffPinChange);
        expect(
          await _landing(tester, auth, AppRoutes.ownerQrScanner),
          AppRoutes.staffPinChange,
        );
        // Kept on the device: a restart opens on the PIN screen too.
        final prefs = await SharedPreferences.getInstance();
        final kept = jsonDecode(prefs.getString('user')!) as Map;
        expect(kept['passwordChangeRequired'], isTrue);
      });
    });

    test('a 403 for a token that is no longer in use does not hold the new '
        'session, and a 401 for it does not sign it out', () async {
      final api = RecordingApi();
      api.fail('GET /owner/staff', 403, {'error': 'password_change_required'});
      api.fail('GET /me', 401, {'error': 'session_ended'});
      final staffHeld = api.hold('GET /owner/staff');
      final meHeld = api.hold('GET /me');
      await api.run(() async {
        final auth = await _signedIn(_staff());
        final old403 = auth.api.ownerStaff();
        final old401 = auth.api.me();
        // The PIN was changed meanwhile: a new session replaced the old one.
        await auth.signIn('jwt-after-change', _staff(held: false));
        staffHeld.complete();
        meHeld.complete();
        await expectLater(old403, throwsA(isA<ApiException>()));
        await expectLater(old401, throwsA(isA<ApiException>()));
        expect(auth.token, 'jwt-after-change');
        expect(auth.pinChangeRequired, isFalse);
      });
    });

    test('start-up: /me refused with password_change_required keeps the '
        'session and holds it (not "offline")', () async {
      SharedPreferences.setMockInitialValues({
        'token': 'jwt-start',
        'user': jsonEncode(_staff()),
        'role': 'gym_staff',
      });
      final api = RecordingApi();
      api.fail('GET /me', 403, {'error': 'password_change_required'});
      await api.run(() async {
        final auth = AuthState(ApiClient(baseUrl: 'http://fixtures.local'));
        await auth.hydrate();
        expect(auth.isSignedIn, isTrue);
        expect(auth.profileUnconfirmed, isFalse);
        expect(auth.pinChangeRequired, isTrue);
        expect(routeForSignedInUser(auth), AppRoutes.staffPinChange);
      });
    });
  });

  group('choose your own PIN', () {
    apiTest('explains why, sends the PIN, stores the new token at once and '
        'opens the staff home', (tester, api) async {
      api.on('POST /auth/pin/change', _changedSession());
      final host = await _pumpScreen(tester, api);
      expect(
        find.text(
          'Your gym owner set a starting PIN. Choose your own to continue.',
        ),
        findsOneWidget,
      );
      expect(find.text('Choose your own PIN'), findsWidgets);
      // No way back: only sign out.
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.byKey(const Key('staff-pin-sign-out')), findsOneWidget);

      // A mismatch starts again and sends nothing.
      await _typePin(tester, '4821');
      await _typePin(tester, '4822');
      expect(find.text('PINs do not match.'), findsOneWidget);
      expect(api.sent('POST', '/auth/pin/change'), isFalse);

      await _chooseAndConfirm(tester, '4821');
      expect(api.only('POST', '/auth/pin/change').body, {'newPin': '4821'});
      expect(
        api.only('POST', '/auth/pin/change').headers['authorization'],
        'Bearer token',
      );
      expect(host.auth.token, 'jwt-after-change');
      expect(host.auth.pinChangeRequired, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), 'jwt-after-change');
      expect(find.text('ROUTE-OWNER-HOME'), findsOneWidget);
      expect(
        host.snack('Your PIN is set. Use it every time you sign in.'),
        findsOneWidget,
      );
    });

    final retryErrors = <String, (int, String)>{
      'pin_must_be_4_digits': (400, 'PIN must be exactly 4 digits.'),
      'pin_unchanged': (
        400,
        'Choose a PIN different from the one your gym owner set.',
      ),
      'pin_change_in_progress': (
        409,
        'Your PIN is already being changed. Wait a moment, then try again.',
      ),
      'firebase_update_failed': (
        502,
        'We could not change your PIN. Nothing was changed. Try again.',
      ),
      'pin_check_unavailable': (
        503,
        'We couldn\'t check your new PIN right now. Nothing was changed — try again later.',
      ),
    };
    for (final MapEntry(key: code, value: (status, message))
        in retryErrors.entries) {
      apiTest('$code: says why, keeps the session, starts the PIN again', (
        tester,
        api,
      ) async {
        api.fail('POST /auth/pin/change', status, {'error': code});
        final host = await _pumpScreen(tester, api);
        await _chooseAndConfirm(tester, '4821');
        expect(find.text(message), findsOneWidget);
        expect(host.auth.token, 'token');
        expect(host.auth.pinChangeRequired, isTrue);
        expect(find.text('Choose a 4-digit PIN'), findsOneWidget);
        expect(find.text('ROUTE-OWNER-HOME'), findsNothing);
      });
    }

    apiTest('pin_changed_session_failed: the PIN was changed, sign in again', (
      tester,
      api,
    ) async {
      api.fail('POST /auth/pin/change', 500, {
        'error': 'pin_changed_session_failed',
      });
      final host = await _pumpScreen(tester, api);
      await _chooseAndConfirm(tester, '4821');
      expect(find.byKey(const Key('staff-pin-sign-in-again')), findsOneWidget);
      expect(
        find.text('Your PIN was changed. Sign in again with your new PIN.'),
        findsOneWidget,
      );
      expect(host.auth.isSignedIn, isTrue);
      await tester.tap(find.text('Sign in again'));
      await tester.pumpAndSettle();
      expect(host.auth.isSignedIn, isFalse);
    });

    for (final (code, status) in [
      ('pin_change_not_required', 409),
      ('feature_disabled', 404),
    ]) {
      apiTest('$code: the account is read again; no hold, so it moves on', (
        tester,
        api,
      ) async {
        api.fail('POST /auth/pin/change', status, {'error': code});
        api.on('GET /me', {'user': _staff(held: false)});
        final host = await _pumpScreen(tester, api);
        await _chooseAndConfirm(tester, '4821');
        expect(api.sent('GET', '/me'), isTrue);
        expect(host.auth.pinChangeRequired, isFalse);
        expect(host.auth.token, 'token');
      });

      apiTest('$code while the server still holds: says so', (
        tester,
        api,
      ) async {
        api.fail('POST /auth/pin/change', status, {'error': code});
        api.fail('GET /me', 403, {'error': 'password_change_required'});
        final host = await _pumpScreen(tester, api);
        await _chooseAndConfirm(tester, '4821');
        expect(host.auth.pinChangeRequired, isTrue);
        expect(
          find.text(
            code == 'feature_disabled'
                ? 'This part of FitFlex is switched off for now.'
                : 'You no longer need to change your PIN. Sign in again if the app does not continue.',
          ),
          findsOneWidget,
        );
      });
    }

    apiTest('sign out leaves the held session', (tester, api) async {
      final host = await _pumpScreen(tester, api);
      await tester.tap(find.byKey(const Key('staff-pin-sign-out')));
      await tester.pumpAndSettle();
      expect(host.auth.isSignedIn, isFalse);
    });

    apiTest('Swahili at 360 px: fits, explains why, PIN pad works', (
      tester,
      api,
    ) async {
      await loadAppFonts();
      api.on('POST /auth/pin/change', _changedSession());
      final host = await _pumpScreen(tester, api, lang: 'sw');
      expect(find.text(host.tr('staffPin.why')), findsOneWidget);
      expect(
        host.tr('staffPin.why'),
        isNot(
          'Your gym owner set a starting PIN. Choose your own to continue.',
        ),
      );
      expect(find.text(host.tr('home.signout')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _chooseAndConfirm(tester, '4821');
      expect(api.only('POST', '/auth/pin/change').body, {'newPin': '4821'});
      expect(tester.takeException(), isNull);
    });
  });

  group('owner staff page', () {
    void seed(RecordingApi api, List<Map<String, dynamic>> staff) {
      api.on('GET /owner/staff', staff);
      api.on('GET /owner/gyms', [
        {'id': 'g1', 'name': 'Mbezi Gym'},
      ]);
    }

    Map<String, dynamic> row(String id, String name, {bool? held}) => {
      'id': id,
      'displayName': name,
      'email': '$id@example.com',
      'aclPermissions': ['checkins'],
      'accountStatus': 'active',
      'passwordChangeRequired': ?held,
    };

    Future<PageHost> pumpStaff(
      WidgetTester tester,
      RecordingApi api, {
      String lang = 'en',
    }) => pumpPage(
      tester,
      api,
      const OwnerStaffPage(),
      user: {
        'id': 'own_1',
        'userType': 'gym_operator',
        'gymIds': ['g1'],
      },
      lang: lang,
    );

    apiTest('flag off (field absent): no badge, no Reset PIN', (
      tester,
      api,
    ) async {
      seed(api, [row('stf_1', 'Neema')]);
      await pumpStaff(tester, api);
      expect(find.text('Neema'), findsOneWidget);
      expect(find.text('Must change PIN'), findsNothing);
      expect(find.byKey(const Key('staff-reset-pin-stf_1')), findsNothing);
    });

    apiTest('flag on: a held row has the badge; every row can be reset', (
      tester,
      api,
    ) async {
      seed(api, [
        row('stf_1', 'Neema', held: true),
        row('stf_2', 'Juma', held: false),
      ]);
      await pumpStaff(tester, api);
      expect(
        find.byKey(const Key('staff-must-change-pin-stf_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('staff-must-change-pin-stf_2')),
        findsNothing,
      );
      expect(find.byKey(const Key('staff-reset-pin-stf_1')), findsOneWidget);
      expect(find.byKey(const Key('staff-reset-pin-stf_2')), findsOneWidget);
    });

    apiTest(
      'reset: explains, checks the PIN twice, sends it, shows the badge',
      (tester, api) async {
        seed(api, [row('stf_2', 'Juma', held: false)]);
        api.on('POST /owner/staff/stf_2/pin', row('stf_2', 'Juma', held: true));
        final host = await pumpStaff(tester, api);
        await tester.tap(find.byKey(const Key('staff-reset-pin-stf_2')));
        await tester.pumpAndSettle();
        final body = tester.widget<Text>(
          find.byKey(const Key('staff-reset-pin-body')),
        );
        expect(body.data, contains('Juma will be signed out on every device'));
        expect(body.data, contains('they must choose their own PIN'));

        await tester.enterText(
          find.byKey(const Key('staff-reset-pin-new')),
          '77',
        );
        await tester.tap(find.byKey(const Key('staff-reset-pin-save')));
        await tester.pumpAndSettle();
        expect(find.text('PIN must be exactly 4 digits.'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('staff-reset-pin-new')),
          '7777',
        );
        await tester.enterText(
          find.byKey(const Key('staff-reset-pin-again')),
          '7778',
        );
        await tester.tap(find.byKey(const Key('staff-reset-pin-save')));
        await tester.pumpAndSettle();
        expect(find.text('PINs do not match.'), findsOneWidget);
        expect(api.sent('POST', '/owner/staff/stf_2/pin'), isFalse);

        await tester.enterText(
          find.byKey(const Key('staff-reset-pin-again')),
          '7777',
        );
        await tester.tap(find.byKey(const Key('staff-reset-pin-save')));
        await tester.pumpAndSettle();
        expect(api.only('POST', '/owner/staff/stf_2/pin').body, {
          'pin': '7777',
        });
        expect(find.byKey(const Key('staff-reset-pin-dialog')), findsNothing);
        expect(
          find.byKey(const Key('staff-must-change-pin-stf_2')),
          findsOneWidget,
        );
        expect(
          host.snack(
            'PIN reset. Juma must choose their own PIN at the next sign-in.',
          ),
          findsOneWidget,
        );
      },
    );

    final resetErrors = <String, (int, String)>{
      'staff_identity_shared': (
        409,
        'This staff member signs in with their own FitFlex account, so you cannot set their PIN. They can use "Forgot PIN" on the sign-in screen.',
      ),
      'credentials_not_accepted': (
        400,
        'Staff now join by invitation and choose their own PIN. They can use "Forgot PIN" on the sign-in screen.',
      ),
      'feature_disabled': (404, 'Resetting staff PINs is not available yet.'),
      'pin_must_be_4_digits': (400, 'PIN must be exactly 4 digits.'),
      'staff_not_at_your_gym': (
        403,
        'This staff member also works at a gym you don\'t own, so only FitFlex can reset their PIN.',
      ),
      'staff_not_found': (
        404,
        'We could not find this staff member. Pull down to refresh the list.',
      ),
      'firebase_update_failed': (
        502,
        'The new PIN could not be saved. The staff member was signed out; their old PIN still works and they must still choose their own. Try again.',
      ),
    };
    for (final MapEntry(key: code, value: (status, message))
        in resetErrors.entries) {
      apiTest('reset refused with $code: the dialog says why and stays', (
        tester,
        api,
      ) async {
        seed(api, [row('stf_1', 'Neema', held: false)]);
        api.fail('POST /owner/staff/stf_1/pin', status, {'error': code});
        await pumpStaff(tester, api);
        await tester.tap(find.byKey(const Key('staff-reset-pin-stf_1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('staff-reset-pin-new')),
          '7777',
        );
        await tester.enterText(
          find.byKey(const Key('staff-reset-pin-again')),
          '7777',
        );
        await tester.tap(find.byKey(const Key('staff-reset-pin-save')));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(find.byKey(const Key('staff-reset-pin-dialog')), findsOneWidget);
        expect(
          find.byKey(const Key('staff-must-change-pin-stf_1')),
          findsNothing,
        );
      });
    }

    apiTest('Swahili at 360 px: badge, Reset PIN and its dialog fit', (
      tester,
      api,
    ) async {
      await loadAppFonts();
      seed(api, [
        row('stf_1', 'Neema Mwakalinga Kisanga', held: true),
        row('stf_2', 'Juma', held: false),
      ]);
      final host = await pumpStaff(tester, api, lang: 'sw');
      expect(find.text(host.tr('staff.mustChangePin')), findsOneWidget);
      expect(host.tr('staff.mustChangePin'), isNot('Must change PIN'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('staff-reset-pin-stf_1')));
      await tester.pumpAndSettle();
      expect(find.text(host.tr('staff.resetPin')), findsWidgets);
      expect(
        find.text(
          host
              .tr('staff.resetPinBody')
              .replaceAll('{name}', 'Neema Mwakalinga Kisanga'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  test('every new string has Swahili', () {
    final en = FFLocale();
    final sw = FFLocale()..set(const Locale('sw'));
    for (final key in [
      'staffPin.title',
      'staffPin.why',
      'staffPin.done',
      'staffPin.errUnchanged',
      'staffPin.errNotRequired',
      'staffPin.errInProgress',
      'staffPin.errNotSaved',
      'staffPin.errCheckUnavailable',
      'staffPin.errSignInAgain',
      'staffPin.signInAgainTitle',
      'staffPin.signInAgainAction',
      'staff.mustChangePin',
      'staff.resetPin',
      'staff.resetPinBody',
      'staff.newStartPin',
      'staff.resetPinDone',
      'staff.errIdentityShared',
      'staff.errCredentialsNotAccepted',
      'staff.errResetOff',
      'staff.errNotYourStaff',
      'staff.errStaffNotFound',
      'staff.errResetNotSaved',
    ]) {
      expect(en.t(key), isNot(key), reason: key);
      expect(sw.t(key), isNot(key), reason: key);
      expect(sw.t(key), isNot(en.t(key)), reason: key);
    }
  });
}
