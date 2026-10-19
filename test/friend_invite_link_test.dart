// Friend invitation links keep their token out of server / CDN logs, the
// address bar, browser history and the route location: the token is kept on
// the device (a day at most) and the invitation page reads it from there.

import 'dart:convert';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/friend_invites.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/pending_org_invite.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Shaped like a real token (43 base64url characters).
const _tok = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcde';
const _tok2 = 'zyxwvutsrqponmlkjihgfedcba9876543210-_ZYXWV';

Map<String, dynamic> _member() => {
  'id': 'usr_1',
  'userType': 'member',
  'approvalStatus': 'approved',
  'onboardingCompleted': true,
};

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:0');

  final previewed = <String>[];
  final claimed = <String>[];
  String previewStatus = 'pending';

  @override
  Future<Map<String, dynamic>> previewFriendInvitation(String token) async {
    previewed.add(token);
    return {
      'invitation': {'status': previewStatus, 'inviterName': 'Asha'},
    };
  }

  @override
  Future<Map<String, dynamic>> claimFriendInvitation(String token) async {
    claimed.add(token);
    return {
      'invitation': {'status': 'pending'},
    };
  }

  @override
  Future<Map<String, dynamic>> myInvitations() async => {'invitations': []};

  @override
  Future<Map<String, dynamic>> notifications() async => {
    'notifications': [],
    'unread': 0,
  };
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
    PendingFriendInvite.resetMemory();
    PendingOrgInvite.resetMemory();
  });

  group('token in a friend-invitation link', () {
    test('new fragment link, as a path or a full address', () {
      for (final url in [
        'https://fitflex-af-app.web.app/friend-invite/#$_tok',
        'https://fitflex-af-app.web.app/friend-invite#$_tok',
        '/friend-invite/#$_tok',
        '/friend-invite#$_tok',
      ]) {
        final link = friendInviteLinkFrom(Uri.parse(url));
        expect(link, isNotNull, reason: url);
        expect(link!.token, _tok, reason: url);
      }
    });

    test('legacy path link, with or without a trailing slash', () {
      for (final url in [
        'https://fitflex-af-app.web.app/friend-invite/$_tok',
        'https://fitflex-af-app.web.app/friend-invite/$_tok/',
        '/friend-invite/$_tok',
      ]) {
        expect(friendInviteTokenFromUri(Uri.parse(url)), _tok, reason: url);
      }
    });

    test('a malformed token is a link with no token', () {
      for (final url in [
        '/friend-invite/#short',
        '/friend-invite/#${'a' * 129}',
        '/friend-invite/#abc%20defghijklmnopqrstuvwxyz',
        '/friend-invite/bad.token.with.dots.abcdefgh',
        '/friend-invite/$_tok/extra',
      ]) {
        final link = friendInviteLinkFrom(Uri.parse(url));
        expect(link, isNotNull, reason: url);
        expect(link!.token, isNull, reason: url);
      }
    });

    test('anything else is not a friend-invitation link', () {
      for (final url in [
        'https://fitflex-af-app.web.app/',
        'https://fitflex-af-app.web.app/#/friend-invite',
        'https://fitflex-af-app.web.app/friend-invite',
        'https://fitflex-af-app.web.app/friend-invite/',
        '/friend-invite',
        '/friend-invites/$_tok',
        '/invitations?token=$_tok',
      ]) {
        expect(friendInviteLinkFrom(Uri.parse(url)), isNull, reason: url);
      }
    });
  });

  group('PendingFriendInvite', () {
    test('save, peek, then take returns the token once', () async {
      await PendingFriendInvite.save(_tok);
      expect(PendingFriendInvite.hasPending, isTrue);
      expect(await PendingFriendInvite.peek(), _tok);
      expect(await PendingFriendInvite.take(), _tok);
      expect(await PendingFriendInvite.take(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('a token kept by an earlier run is loaded', () async {
      await PendingFriendInvite.save(_tok);
      PendingFriendInvite.resetMemory();
      expect(PendingFriendInvite.hasPending, isFalse);
      await PendingFriendInvite.load();
      expect(PendingFriendInvite.hasPending, isTrue);
    });

    test('a token older than 24 hours is dropped', () async {
      final saved = DateTime(2026, 10, 19, 9);
      PendingFriendInvite.clock = () => saved;
      await PendingFriendInvite.save(_tok);
      PendingFriendInvite.clock = () => saved.add(const Duration(hours: 23));
      expect(await PendingFriendInvite.peek(), _tok);
      PendingFriendInvite.clock = () => saved.add(const Duration(hours: 24));
      expect(PendingFriendInvite.hasPending, isFalse);
      expect(await PendingFriendInvite.take(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('a token kept by an older build (no saved time) is dropped', () async {
      SharedPreferences.setMockInitialValues({
        'pending_friend_invite_token': _tok,
      });
      expect(await PendingFriendInvite.peek(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('kept apart from the organisation invitation token', () async {
      await PendingFriendInvite.save(_tok);
      await PendingOrgInvite.save('org-tok');
      await PendingOrgInvite.clear();
      expect(await PendingFriendInvite.peek(), _tok);
    });
  });

  group('signing out', () {
    test('a real sign-out clears the kept token', () async {
      final auth = AuthState(_Api());
      await auth.signIn('jwt', _member());
      await PendingFriendInvite.save(_tok);
      await auth.signOut();
      expect(PendingFriendInvite.hasPending, isFalse);
      PendingFriendInvite.resetMemory();
      expect(await PendingFriendInvite.peek(), isNull);
    });

    test('a persona switch clears the kept token', () async {
      final auth = AuthState(_SwitchApi());
      await auth.signIn('jwt', _member());
      await PendingFriendInvite.save(_tok);
      await auth.switchPersona('usr_staff');
      expect(await PendingFriendInvite.peek(), isNull);
    });

    test('a sign-in error before any session keeps the token', () async {
      final auth = AuthState(_Api());
      await PendingFriendInvite.save(_tok);
      await auth.signOut();
      expect(await PendingFriendInvite.peek(), _tok);
    });
  });

  group('router', () {
    for (final link in [
      '/friend-invite/#$_tok',
      'https://fitflex-af-app.web.app/friend-invite/#$_tok',
      '/friend-invite/$_tok',
    ]) {
      testWidgets('signed out: $link keeps the token and drops it from the '
          'location', (tester) async {
        final api = _Api();
        final auth = AuthState(api);
        final router = await _pumpRouter(tester, auth);
        router.go(link);
        await _settle(tester);

        expect(_location(router), AppRoutes.friendInvite);
        expect(_location(router), isNot(contains(_tok)));
        expect(await PendingFriendInvite.peek(), _tok);
        // The page shows who invited them, reading the kept token.
        expect(api.previewed, [_tok]);
        expect(find.byKey(const Key('invite-continue')), findsOneWidget);
        expect(find.textContaining('Asha'), findsOneWidget);
      });
    }

    testWidgets('signed out: a newer link replaces an older kept token', (
      tester,
    ) async {
      await PendingFriendInvite.save(_tok);
      final api = _Api();
      final router = await _pumpRouter(tester, AuthState(api));
      router.go('/friend-invite/#$_tok2');
      await _settle(tester);
      expect(await PendingFriendInvite.peek(), _tok2);
      expect(api.previewed, [_tok2]);
    });

    testWidgets('signed out: a malformed link forgets any kept token', (
      tester,
    ) async {
      await PendingFriendInvite.save(_tok);
      final api = _Api();
      final router = await _pumpRouter(tester, AuthState(api));
      router.go('/friend-invite/#short');
      await _settle(tester);
      expect(_location(router), AppRoutes.friendInvite);
      expect(await PendingFriendInvite.peek(), isNull);
      expect(api.previewed, isEmpty);
      expect(find.text('This invitation is not valid'), findsOneWidget);
    });

    testWidgets('signed out: an answered invitation is not kept', (
      tester,
    ) async {
      final api = _Api()..previewStatus = 'accepted';
      final router = await _pumpRouter(tester, AuthState(api));
      router.go('/friend-invite/#$_tok');
      await _settle(tester);
      expect(await PendingFriendInvite.peek(), isNull);
    });

    testWidgets('signed out: the plain page stays open (public)', (
      tester,
    ) async {
      final router = await _pumpRouter(tester, AuthState(_Api()));
      router.go(AppRoutes.friendInvite);
      await _settle(tester);
      expect(_location(router), AppRoutes.friendInvite);
    });

    for (final link in ['/friend-invite/#$_tok', '/friend-invite/$_tok']) {
      testWidgets('signed in: $link is claimed and opens Notifications', (
        tester,
      ) async {
        final api = _Api();
        final auth = AuthState(api);
        await auth.signIn('jwt', _member());
        final router = await _pumpRouter(tester, auth);
        router.go(link);
        await _settle(tester);

        expect(api.claimed, [_tok]);
        expect(PendingFriendInvite.hasPending, isFalse);
        expect(_location(router), AppRoutes.inbox);
      });
    }
  });

  group('preview request', () {
    Future<List<http.Request>> run(
      List<http.Response> responses,
      Future<void> Function(ApiClient api) body,
    ) async {
      final seen = <http.Request>[];
      var i = 0;
      final client = MockClient((req) async {
        seen.add(req);
        return responses[i++];
      });
      await http.runWithClient(
        () => body(ApiClient(baseUrl: 'http://api')),
        () => client,
      );
      return seen;
    }

    final okBody = jsonEncode({
      'invitation': {'status': 'pending', 'inviterName': 'Asha'},
    });

    test('POSTs the token in the body, not the address', () async {
      late Map<String, dynamic> res;
      final seen = await run([http.Response(okBody, 200)], (api) async {
        res = await api.previewFriendInvitation(_tok);
      });
      expect(seen, hasLength(1));
      expect(seen[0].method, 'POST');
      expect(seen[0].url.path, '/friend-invitations/preview');
      expect(seen[0].url.toString(), isNot(contains(_tok)));
      expect(jsonDecode(seen[0].body), {'token': _tok});
      expect((res['invitation'] as Map)['inviterName'], 'Asha');
    });

    test('falls back to the GET when the server has no POST route', () async {
      late Map<String, dynamic> res;
      final seen = await run([
        http.Response(
          '<!DOCTYPE html><pre>Cannot POST /friend-invitations/preview</pre>',
          404,
          headers: {'content-type': 'text/html'},
        ),
        http.Response(okBody, 200),
      ], (api) async => res = await api.previewFriendInvitation(_tok));
      expect(seen.map((r) => r.method), ['POST', 'GET']);
      expect(seen[1].url.path, '/friend-invitations/preview/$_tok');
      expect((res['invitation'] as Map)['status'], 'pending');
    });

    test('an HTML error page keeps its status but not its HTML', () async {
      Object? error;
      await run(
        [
          http.Response(
            '<!DOCTYPE html><html><body><pre>Error: boom\n    at '
            'Layer.handle (/app/node_modules/express/router.js:95)</pre>'
            '</body></html>',
            502,
            headers: {'content-type': 'text/html'},
          ),
        ],
        (api) async {
          try {
            await api.previewFriendInvitation(_tok);
          } catch (e) {
            error = e;
          }
        },
      );
      final e = error as ApiException;
      expect(e.status, 502);
      expect(e.code, isNull);
      expect(e.body, isNull);
      for (final lang in ['en', 'sw']) {
        final locale = FFLocale()..set(Locale(lang));
        final text = errorMessage(locale, e);
        expect(text, locale.t('error.requestFailed'), reason: lang);
        expect(text, isNot(contains('<')), reason: lang);
        expect(text, isNot(contains('express')), reason: lang);
      }
    });

    test('falls back on a 404 not_found too', () async {
      final seen = await run([
        http.Response(jsonEncode({'error': 'not_found'}), 404),
        http.Response(okBody, 200),
      ], (api) => api.previewFriendInvitation(_tok));
      expect(seen.map((r) => r.method), ['POST', 'GET']);
    });

    test('an invalid invitation is an answer, not retried', () async {
      Object? error;
      final seen = await run(
        [
          http.Response(jsonEncode({'error': 'invalid_invitation'}), 404),
        ],
        (api) async {
          try {
            await api.previewFriendInvitation(_tok);
          } catch (e) {
            error = e;
          }
        },
      );
      expect(seen.map((r) => r.method), ['POST']);
      expect(error, isA<ApiException>());
      expect((error as ApiException).code, 'invalid_invitation');
    });

    test('other errors are not retried', () async {
      Object? error;
      final seen = await run(
        [
          http.Response(jsonEncode({'error': 'rate_limited'}), 429),
        ],
        (api) async {
          try {
            await api.previewFriendInvitation(_tok);
          } catch (e) {
            error = e;
          }
        },
      );
      expect(seen, hasLength(1));
      expect((error as ApiException).status, 429);
    });
  });
}
