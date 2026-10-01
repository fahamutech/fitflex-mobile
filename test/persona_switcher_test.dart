import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/persona_switcher.dart';

Map<String, dynamic> _persona(
  String id,
  String type, {
  String approval = 'approved',
  String status = 'active',
  bool portalOnly = false,
}) => {
  'id': id,
  'userType': type,
  'approvalStatus': approval,
  'accountStatus': status,
  'onboardingCompleted': true,
  'portalOnly': portalOnly,
};

Map<String, dynamic> _user(String id, String type) => {
  'id': id,
  'userType': type,
  'approvalStatus': 'approved',
  'onboardingCompleted': true,
  'gymIds': ['gym_1'],
};

/// Answers the persona endpoints; switching returns the chosen persona.
class _FakeApi extends ApiClient {
  _FakeApi({this.personasStatus = 200}) : super(baseUrl: 'http://localhost:0');

  final int personasStatus;
  final switched = <String>[];
  final added = <String>[];
  List<String> addable = const [];
  bool addConflict = false;
  List<Map<String, dynamic>> personas = [
    _persona('usr_member', 'member'),
    _persona('usr_trainer', 'trainer'),
    _persona('usr_owner', 'gym_operator', approval: 'pending_approval'),
    _persona('usr_old', 'vendor', status: 'suspended'),
    _persona('usr_admin', 'admin', portalOnly: true),
  ];

  @override
  Future<Map<String, dynamic>> switchPersona(String personaId) async {
    switched.add(personaId);
    final p = personas.firstWhere((p) => p['id'] == personaId);
    return {
      'token': 'jwt-$personaId',
      'user': _user(personaId, p['userType'] as String),
      'personas': personas,
      'activePersonaId': personaId,
      'addablePersonaTypes': addable,
    };
  }

  @override
  Future<Map<String, dynamic>> myPersonas() async {
    if (personasStatus != 200) {
      throw ApiException(personasStatus, {'error': 'not_found'});
    }
    return {
      'personas': personas,
      'activePersonaId': 'usr_member',
      'addablePersonaTypes': addable,
    };
  }

  @override
  Future<Map<String, dynamic>> addPersona(String userType) async {
    if (addConflict) {
      throw ApiException(409, {'error': 'persona_identifier_in_use'});
    }
    added.add(userType);
    final persona = _persona('usr_new_$userType', userType);
    personas = [...personas, persona];
    addable = addable.where((t) => t != userType).toList();
    return {
      'created': true,
      'persona': persona,
      'personas': personas,
      'addablePersonaTypes': addable,
    };
  }
}

/// A Person with only a member persona who may add roles (I3).
_FakeApi _soloMemberApi() => _FakeApi()
  ..personas = [_persona('usr_member', 'member')]
  ..addable = ['trainer', 'gym_operator', 'vendor'];

Future<AuthState> _signedIn(_FakeApi api) async {
  final auth = AuthState(api);
  await auth.signIn('jwt-member', _user('usr_member', 'member'));
  await auth.refreshPersonas();
  return auth;
}

Widget _app(AuthState auth, Widget home, {List<RouteBase> extra = const []}) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: AppRoutes.memberHome,
        builder: (_, _) => const Text('member home'),
      ),
      GoRoute(
        path: AppRoutes.trainerHome,
        builder: (_, _) => const Text('trainer home'),
      ),
      ...extra,
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

  test('only usable, other personas are offered for switching', () async {
    final auth = await _signedIn(_FakeApi());
    expect(auth.personas, hasLength(5));
    expect(
      auth.switchablePersonas.map((p) => p['id']),
      ['usr_trainer', 'usr_owner'],
      reason: 'not the current one, suspended or portal-only',
    );
  });

  test('backend V2 off (404) keeps the single-persona app', () async {
    final auth = await _signedIn(_FakeApi(personasStatus: 404));
    expect(auth.personas, isEmpty);
    expect(auth.switchablePersonas, isEmpty);
  });

  test('switching replaces the session with the chosen persona', () async {
    final api = _FakeApi();
    final auth = await _signedIn(api);
    await auth.switchPersona('usr_trainer');
    expect(api.switched, ['usr_trainer']);
    expect(auth.token, 'jwt-usr_trainer');
    expect(auth.user?['userType'], 'trainer');
    expect(auth.role, 'trainer');
    expect(auth.switchablePersonas.map((p) => p['id']), [
      'usr_member',
      'usr_owner',
    ]);
  });

  test('sign-out forgets the personas', () async {
    final auth = await _signedIn(_FakeApi());
    await auth.signOut();
    expect(auth.personas, isEmpty);
  });

  testWidgets('no other persona: the switch tile is not shown', (tester) async {
    final auth = await _signedIn(_FakeApi(personasStatus: 404));
    await tester.pumpWidget(_app(auth, const PersonaSwitcherTile()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persona-switch')), findsNothing);
  });

  testWidgets('the switch tile opens the list and switches role', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _signedIn(api);
    await tester.pumpWidget(_app(auth, const PersonaSwitcherTile()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('persona-switch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persona-usr_trainer')), findsOneWidget);
    expect(find.byKey(const Key('persona-usr_owner')), findsOneWidget);
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.byKey(const Key('persona-usr_old')), findsNothing);
    expect(find.byKey(const Key('persona-usr_admin')), findsNothing);

    await tester.tap(find.byKey(const Key('persona-usr_trainer')));
    await tester.pumpAndSettle();
    expect(api.switched, ['usr_trainer']);
    expect(find.text('trainer home'), findsOneWidget);
  });

  testWidgets('the picker keeps the current persona without a round trip', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _signedIn(api);
    await tester.pumpWidget(_app(auth, const PersonaPickerScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pick-persona-usr_admin')), findsNothing);

    await tester.tap(find.byKey(const Key('pick-persona-usr_member')));
    await tester.pumpAndSettle();
    expect(api.switched, isEmpty);
    expect(auth.personaChoiceRequired, isFalse);
    expect(find.text('member home'), findsOneWidget);
  });

  test('roles the backend says can be added are exposed', () async {
    final auth = await _signedIn(_soloMemberApi());
    expect(auth.switchablePersonas, isEmpty);
    expect(auth.addablePersonaTypes, ['trainer', 'gym_operator', 'vendor']);
  });

  testWidgets(
    'a single-persona user is offered "Add a role" and becomes a trainer',
    (tester) async {
      final api = _soloMemberApi();
      final auth = await _signedIn(api);
      await tester.pumpWidget(_app(auth, const PersonaSwitcherTile()));
      await tester.pumpAndSettle();

      expect(find.text('Roles'), findsOneWidget);
      await tester.tap(find.byKey(const Key('persona-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Become a trainer'), findsOneWidget);
      expect(find.text('Register a gym'), findsOneWidget);
      expect(find.text('Open a store'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-persona-trainer')));
      await tester.pumpAndSettle();
      expect(api.added, ['trainer']);
      expect(api.switched, [
        'usr_new_trainer',
      ], reason: 'continues as the new role');
      expect(auth.user?['userType'], 'trainer');
      expect(auth.addablePersonaTypes, ['gym_operator', 'vendor']);
      expect(find.text('trainer home'), findsOneWidget);
    },
  );

  testWidgets('an email already used for that role explains how to link it', (
    tester,
  ) async {
    final api = _soloMemberApi()..addConflict = true;
    final auth = await _signedIn(api);
    await tester.pumpWidget(_app(auth, const PersonaSwitcherTile()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('persona-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-persona-vendor')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('already has a profile for that role'),
      findsOneWidget,
    );
    expect(api.switched, isEmpty);
    expect(auth.user?['userType'], 'member');
  });
}
