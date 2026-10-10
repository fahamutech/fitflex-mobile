import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/auth_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

Map<String, dynamic> _persona(String id, String type, String approval) => {
  'id': id,
  'userType': type,
  'approvalStatus': approval,
  'accountStatus': 'active',
  'onboardingCompleted': true,
  'portalOnly': false,
};

Map<String, dynamic> _user(String id, String type, String approval) => {
  'id': id,
  'userType': type,
  'approvalStatus': approval,
  'onboardingCompleted': true,
};

/// A member who also applied as a vendor, and is waiting for approval.
class _Api extends ApiClient {
  _Api(this.personas) : super(baseUrl: 'http://localhost:0');

  final List<Map<String, dynamic>> personas;
  final switched = <String>[];

  @override
  Future<Map<String, dynamic>> switchPersona(String personaId) async {
    switched.add(personaId);
    final p = personas.firstWhere((p) => p['id'] == personaId);
    return {
      'token': 'jwt-$personaId',
      'user': _user(
        personaId,
        p['userType'] as String,
        p['approvalStatus'] as String,
      ),
      'personas': personas,
      'activePersonaId': personaId,
      'addablePersonaTypes': const <String>[],
    };
  }

  @override
  Future<Map<String, dynamic>> myPersonas() async => {
    'personas': personas,
    'activePersonaId': 'usr_vendor',
    'addablePersonaTypes': const <String>[],
  };
}

Future<AuthState> _pendingVendor(_Api api) async {
  final auth = AuthState(api);
  await auth.signIn(
    'jwt-vendor',
    _user('usr_vendor', 'vendor', 'pending_approval'),
  );
  await auth.refreshPersonas();
  return auth;
}

Widget _app(AuthState auth) {
  final router = GoRouter(
    initialLocation: AppRoutes.pending,
    routes: [
      GoRoute(
        path: AppRoutes.pending,
        builder: (_, _) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: AppRoutes.memberHome,
        builder: (_, _) => const Text('member home'),
      ),
    ],
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

  testWidgets(
    'a pending vendor who is also a member can switch to the member role',
    (tester) async {
      final api = _Api([
        _persona('usr_member', 'member', 'approved'),
        _persona('usr_vendor', 'vendor', 'pending_approval'),
      ]);
      final auth = await _pendingVendor(api);
      await tester.pumpWidget(_app(auth));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('persona-switch')),
        findsOneWidget,
        reason: 'on the page',
      );
      expect(
        find.byKey(const Key('persona-switch-button')),
        findsOneWidget,
        reason: 'in the app bar',
      );

      await tester.tap(find.byKey(const Key('persona-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('persona-usr_member')));
      await tester.pumpAndSettle();

      expect(api.switched, ['usr_member']);
      expect(auth.user?['userType'], 'member');
      expect(find.text('member home'), findsOneWidget);

      // Stop the approval check that waits in the background.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets('with no other role there is nothing to switch to', (
    tester,
  ) async {
    final api = _Api([_persona('usr_vendor', 'vendor', 'pending_approval')]);
    final auth = await _pendingVendor(api);
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persona-switch')), findsNothing);
    expect(find.byKey(const Key('persona-switch-button')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
