// Organisation invitation links keep their token out of the address bar and
// browser history: the token is kept on the device (a day at most) and the
// invitations screen takes it once.

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/pending_org_invite.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/invitations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _member() => {
  'id': 'usr_1',
  'userType': 'member',
  'approvalStatus': 'approved',
  'onboardingCompleted': true,
};

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:0');

  final opened = <String>[];

  @override
  Future<Map<String, dynamic>> myInvitations() async => {'invitations': []};

  @override
  Future<Map<String, dynamic>> openInvitation(String token) async {
    opened.add(token);
    return {};
  }
}

class _SwitchApi extends _Api {
  @override
  Future<Map<String, dynamic>> switchPersona(String personaId) async => {
    'token': 'jwt-$personaId',
    'user': {..._member(), 'id': personaId, 'userType': 'gym_staff'},
    'personas': const [],
  };

  @override
  Future<Map<String, dynamic>> me() async => {'user': _member()};
}

Future<GoRouter> _pumpRouter(WidgetTester tester, AuthState auth) async {
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
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PendingOrgInvite.resetMemory();
  });

  group('PendingOrgInvite', () {
    test('save then take returns the token once', () async {
      await PendingOrgInvite.save('tok-1');
      expect(PendingOrgInvite.hasPending, isTrue);
      expect(await PendingOrgInvite.peek(), 'tok-1');
      expect(await PendingOrgInvite.take(), 'tok-1');
      expect(await PendingOrgInvite.take(), isNull);
      expect(PendingOrgInvite.hasPending, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('a token kept by an earlier run is loaded', () async {
      await PendingOrgInvite.save('tok-2');
      PendingOrgInvite.resetMemory();
      expect(PendingOrgInvite.hasPending, isFalse);
      await PendingOrgInvite.load();
      expect(PendingOrgInvite.hasPending, isTrue);
      expect(await PendingOrgInvite.take(), 'tok-2');
    });

    test('a token older than 24 hours is dropped', () async {
      final saved = DateTime(2026, 10, 18, 9);
      PendingOrgInvite.clock = () => saved;
      await PendingOrgInvite.save('tok-old');
      PendingOrgInvite.clock = () => saved.add(const Duration(hours: 23));
      expect(await PendingOrgInvite.peek(), 'tok-old');
      PendingOrgInvite.clock = () => saved.add(const Duration(hours: 24));
      expect(PendingOrgInvite.hasPending, isFalse);
      expect(await PendingOrgInvite.take(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('clear forgets it', () async {
      await PendingOrgInvite.save('tok-3');
      await PendingOrgInvite.clear();
      expect(await PendingOrgInvite.take(), isNull);
    });
  });

  group('token in a page address', () {
    test('current hash link and legacy path link', () {
      expect(inviteTokenFromPageUri(Uri.parse(inviteLink('a b/c'))), 'a b/c');
      expect(
        inviteTokenFromPageUri(
          Uri.parse('https://fitflex-af-app.web.app/invitations?token=abc'),
        ),
        'abc',
      );
      expect(
        inviteTokenFromPageUri(
          Uri.parse('https://fitflex-af-app.web.app/invitations/?token=abc'),
        ),
        'abc',
      );
    });

    test('anything else has no token', () {
      for (final url in [
        'https://fitflex-af-app.web.app/',
        'https://fitflex-af-app.web.app/#/invitations',
        'https://fitflex-af-app.web.app/#/member/gyms?token=x',
        'https://fitflex-af-app.web.app/friend-invite/abc',
        'https://fitflex-af-app.web.app/invitations?token=',
      ]) {
        expect(inviteTokenFromPageUri(Uri.parse(url)), isNull, reason: url);
      }
    });
  });

  testWidgets('signed out: the link token is kept and leaves the location', (
    tester,
  ) async {
    final auth = AuthState(_Api());
    final router = await _pumpRouter(tester, auth);
    router.go('/invitations?token=abc');
    await _settle(tester);

    expect(_location(router), AppRoutes.language);
    expect(_location(router), isNot(contains('abc')));
    expect(PendingOrgInvite.hasPending, isTrue);
    expect(await PendingOrgInvite.peek(), 'abc');

    // After signing in, the invitations screen comes first.
    await auth.signIn('jwt', _member());
    expect(routeForSignedInUser(auth), AppRoutes.invitations);
  });

  testWidgets(
    'signed in: the link opens the screen without the token, which uses it',
    (tester) async {
      final api = _Api();
      final auth = AuthState(api);
      await auth.signIn('jwt', _member());
      final router = await _pumpRouter(tester, auth);
      router.go('/invitations?token=xyz');
      await _settle(tester);

      expect(_location(router), AppRoutes.invitations);
      expect(api.opened, ['xyz']);
      expect(PendingOrgInvite.hasPending, isFalse);
      expect(routeForSignedInUser(auth), AppRoutes.memberHome);
    },
  );

  group('signing out', () {
    test('a real sign-out clears the kept token', () async {
      final auth = AuthState(_Api());
      await auth.signIn('jwt', _member());
      await PendingOrgInvite.save('tok-a');
      await auth.signOut();
      expect(PendingOrgInvite.hasPending, isFalse);
      PendingOrgInvite.resetMemory();
      await PendingOrgInvite.load();
      expect(await PendingOrgInvite.take(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_org_invite_token'), isNull);
    });

    test('a persona switch clears the kept token', () async {
      final api = _SwitchApi();
      final auth = AuthState(api);
      await auth.signIn('jwt', _member());
      await PendingOrgInvite.save('tok-b');
      await auth.switchPersona('usr_staff');
      expect(PendingOrgInvite.hasPending, isFalse);
      expect(await PendingOrgInvite.take(), isNull);
    });

    test('a sign-in error before any session keeps the token', () async {
      final auth = AuthState(_Api());
      await PendingOrgInvite.save('tok-c');
      await auth.signOut();
      expect(await PendingOrgInvite.take(), 'tok-c');
    });
  });

  test('pending approval or onboarding still wins over a kept link', () async {
    await PendingOrgInvite.save('tok');
    final auth = AuthState(_Api());
    await auth.signIn('jwt', {..._member(), 'onboardingCompleted': false});
    expect(routeForSignedInUser(auth), AppRoutes.memberOnboarding);
    await auth.signIn('jwt', {
      'id': 'usr_2',
      'userType': 'vendor',
      'approvalStatus': 'pending_approval',
    });
    expect(routeForSignedInUser(auth), AppRoutes.vendorHome);
  });
}
