import 'dart:async';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

/// Offline for `/me` until [online] is set; everything else fails too.
class _FlakyApi extends ApiClient {
  bool online = false;

  @override
  Future<Map<String, dynamic>> me() async {
    if (!online) throw http.ClientException('Failed host lookup');
    return {
      'user': {'id': 'u1', 'displayName': 'Amina', 'onboardingCompleted': true},
    };
  }
}

void main() {
  test('network errors are told apart from server errors', () {
    expect(isNetworkError(http.ClientException('x')), isTrue);
    expect(isNetworkError(TimeoutException('x')), isTrue);
    expect(isNetworkError(Exception('SocketException: nope')), isTrue);
    expect(isNetworkError(ApiException(500, {})), isFalse);
    expect(isNetworkError(StateError('bug')), isFalse);
  });

  testWidgets('offline: a banner with Retry, gone once back online', (
    tester,
  ) async {
    final api = _FlakyApi();
    final router = GoRouter(
      initialLocation: '/member',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              MemberShell(state: state, child: child),
          routes: [
            GoRoute(
              path: '/member',
              builder: (_, _) => const Center(child: Text('home')),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      AppScope(
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
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-offline-banner')), findsOneWidget);
    expect(
      find.text("You're offline. Showing what was last loaded."),
      findsOneWidget,
    );

    api.online = true;
    await tester.tap(find.byKey(const Key('member-offline-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-offline-banner')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
