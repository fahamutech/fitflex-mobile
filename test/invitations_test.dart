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
import 'package:fitflexmobile/shared/widgets/invitations.dart';

Map<String, dynamic> _user(String id, String type) => {
  'id': id,
  'userType': type,
  'approvalStatus': 'approved',
  'onboardingCompleted': true,
  'gymIds': ['gym_1'],
};

Map<String, dynamic> _staffInvite() => {
  'id': 'inv_staff',
  'orgName': 'Iron Paradise',
  'role': 'staff',
  'status': 'pending',
};

Map<String, dynamic> _memberInvite() => {
  'id': 'inv_member',
  'orgName': 'Iron Paradise',
  'role': 'member',
  'status': 'pending',
  'plan': {'tier': 'standard', 'endDate': '2026-10-31T00:00:00.000Z'},
  'paidAmountTzs': 50000,
};

class _FakeApi extends ApiClient {
  _FakeApi({this.enabled = true}) : super(baseUrl: 'http://localhost:0');

  final bool enabled;
  List<Map<String, dynamic>> mine = [];
  List<Map<String, dynamic>> personas = [];
  final accepted = <String>[];
  final declined = <String>[];
  final switched = <String>[];
  final created = <Map<String, dynamic>>[];
  final actions = <String>[];
  final lookups = <String>[];
  String? openError;
  List<Map<String, dynamic>> sent = [];

  @override
  Future<Map<String, dynamic>> myInvitations() async {
    if (!enabled) throw ApiException(404, {'error': 'not_found'});
    return {'invitations': mine};
  }

  @override
  Future<Map<String, dynamic>> openInvitation(String token) async {
    if (openError != null) throw ApiException(403, {'error': openError});
    return {'invitation': mine.first};
  }

  @override
  Future<Map<String, dynamic>> acceptInvitation(String id) async {
    accepted.add(id);
    mine = mine.where((i) => i['id'] != id).toList();
    if (id == 'inv_staff') {
      personas = [
        {'id': 'usr_member', 'userType': 'member'},
        {'id': 'usr_staff', 'userType': 'gym_staff'},
      ];
      return {'personaId': 'usr_staff'};
    }
    return {'personaId': 'usr_member'};
  }

  @override
  Future<Map<String, dynamic>> declineInvitation(String id) async {
    declined.add(id);
    mine = mine.where((i) => i['id'] != id).toList();
    return {};
  }

  @override
  Future<Map<String, dynamic>> myPersonas() async => {'personas': personas};

  @override
  Future<Map<String, dynamic>> switchPersona(String personaId) async {
    switched.add(personaId);
    return {
      'token': 'jwt-$personaId',
      'user': _user(personaId, 'gym_staff'),
      'personas': personas,
    };
  }

  @override
  Future<Map<String, dynamic>> gymLookupPerson(
    String gymId, {
    String? phone,
    String? email,
    String orgType = 'gym',
  }) async {
    lookups.add('$orgType:$gymId');
    return {'found': true, 'maskedName': 'N**** A*******'};
  }

  @override
  Future<Map<String, dynamic>> gymCreateInvitation(
    String gymId,
    Map<String, dynamic> body, {
    String orgType = 'gym',
  }) async {
    created.add({
      if (orgType == 'gym') 'gymId': gymId else 'vendorId': gymId,
      ...body,
    });
    return {
      'created': true,
      'token': 'tok-123',
      'invitation': {'id': 'inv_new'},
    };
  }

  @override
  Future<Map<String, dynamic>> gymInvitations(
    String gymId, {
    bool needsResolution = false,
    String orgType = 'gym',
  }) async => {'invitations': sent};

  @override
  Future<Map<String, dynamic>> gymInvitationAction(
    String gymId,
    String invitationId,
    String action, {
    Map<String, dynamic>? body,
    String orgType = 'gym',
  }) async {
    actions.add(
      orgType == 'gym'
          ? '$action:$invitationId'
          : '$orgType:$action:$invitationId',
    );
    sent = [];
    return {};
  }
}

Future<AuthState> _signedIn(_FakeApi api) async {
  final auth = AuthState(api);
  await auth.signIn('jwt-member', _user('usr_member', 'member'));
  await auth.refreshInvitations();
  return auth;
}

Widget _app(AuthState auth, Widget home) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: AppRoutes.ownerHome,
        builder: (_, _) => const Text('owner home'),
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

  group('invitation request body', () {
    final today = DateTime(2026, 10, 1, 15, 30);

    test('a member: phone, plan from today, desk payment', () {
      expect(
        buildInvitationBody(
          role: 'member',
          contact: ' 0712345678 ',
          durationUnit: 'M',
          paidAmount: 50000,
          today: today,
        ),
        {
          'role': 'member',
          'phone': '0712345678',
          'durationUnit': 'M',
          'startDate': '2026-10-01',
          'endDate': '2026-11-01',
          'tier': 'basic',
          'paidAmount': 50000,
        },
      );
    });

    test('week and day plans; nothing paid sends no payment', () {
      final week = buildInvitationBody(
        role: 'member',
        contact: 'a@b.co',
        durationUnit: 'W',
        today: today,
      );
      expect(week['email'], 'a@b.co');
      expect(week['endDate'], '2026-10-08');
      expect(week.containsKey('paidAmount'), isFalse);
      expect(
        buildInvitationBody(
          role: 'member',
          contact: '0712',
          durationUnit: 'D',
          paidAmount: 0,
          today: today,
        )['endDate'],
        '2026-10-02',
      );
    });

    test('staff carry permissions; a trainer needs only the contact', () {
      expect(
        buildInvitationBody(
          role: 'staff',
          contact: 'rec@gym.co',
          aclPermissions: ['members'],
          today: today,
        ),
        {
          'role': 'staff',
          'email': 'rec@gym.co',
          'aclPermissions': ['members'],
        },
      );
      expect(
        buildInvitationBody(role: 'trainer', contact: '0713', today: today),
        {'role': 'trainer', 'phone': '0713'},
      );
    });

    test('shop staff carry the shop role and permissions, no gym fields', () {
      expect(
        buildInvitationBody(
          role: 'staff',
          contact: ' desk@shop.co ',
          aclPermissions: ['members'],
          today: today,
          orgType: 'vendor',
          vendorRole: 'orders_manager',
          vendorPermissions: ['orders', 'customers'],
        ),
        {
          'role': 'staff',
          'email': 'desk@shop.co',
          'vendorRole': 'orders_manager',
          'permissions': ['orders', 'customers'],
        },
      );
    });

    test('the link opens the invitations screen with the token', () {
      expect(
        inviteLink('a b/c'),
        'https://fitflex-af-app.web.app/invitations?token=a+b%2Fc',
      );
    });
  });

  test('invitations follow the backend flag', () async {
    final on = await _signedIn(_FakeApi()..mine = [_staffInvite()]);
    expect(on.invitesEnabled, isTrue);
    expect(on.invitations, hasLength(1));

    final off = await _signedIn(_FakeApi(enabled: false));
    expect(off.invitesEnabled, isFalse);
    expect(off.invitations, isEmpty);
  });

  testWidgets('no invitations: the profile tile is not shown', (tester) async {
    final auth = await _signedIn(_FakeApi());
    await tester.pumpWidget(_app(auth, const InvitationsTile()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invitations-tile')), findsNothing);
  });

  testWidgets(
    'a member invitation shows its plan and payment; accepting it stays put',
    (tester) async {
      final api = _FakeApi()..mine = [_memberInvite()];
      final auth = await _signedIn(api);
      await tester.pumpWidget(_app(auth, const InvitationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Iron Paradise'), findsOneWidget);
      expect(find.text('standard plan, until 2026-10-31'), findsOneWidget);
      expect(find.text('Paid: TZS 50000'), findsOneWidget);

      await tester.tap(find.byKey(const Key('accept-inv_member')));
      await tester.pumpAndSettle();
      expect(api.accepted, ['inv_member']);
      expect(api.switched, isEmpty, reason: 'no new role to switch to');
      expect(find.text('No invitations right now.'), findsOneWidget);
    },
  );

  testWidgets('accepting a staff invitation continues as the new role', (
    tester,
  ) async {
    final api = _FakeApi()..mine = [_staffInvite()];
    final auth = await _signedIn(api);
    await tester.pumpWidget(_app(auth, const InvitationsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept-inv_staff')));
    await tester.pumpAndSettle();
    expect(api.accepted, ['inv_staff']);
    expect(api.switched, ['usr_staff']);
    expect(find.text('owner home'), findsOneWidget);
  });

  testWidgets('declining removes it without creating anything', (tester) async {
    final api = _FakeApi()..mine = [_staffInvite()];
    final auth = await _signedIn(api);
    await tester.pumpWidget(_app(auth, const InvitationsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decline-inv_staff')));
    await tester.pumpAndSettle();
    expect(api.declined, ['inv_staff']);
    expect(api.accepted, isEmpty);
  });

  testWidgets('a link for an identifier not verified here explains why', (
    tester,
  ) async {
    final api = _FakeApi()..openError = 'identifier_not_verified';
    final auth = await _signedIn(api);
    await tester.pumpWidget(_app(auth, const InvitationsScreen(token: 't')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('you have not verified on this account'),
      findsOneWidget,
    );
  });

  testWidgets(
    'inviting staff: check, choose permissions, send, copy the link',
    (tester) async {
      final api = _FakeApi();
      final auth = await _signedIn(api);
      await tester.pumpWidget(
        _app(
          auth,
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openInvitePersonSheet(context, gymId: 'gym_1', role: 'staff'),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('invite-contact')),
        'rec@gym.co',
      );
      await tester.tap(find.byKey(const Key('invite-check')));
      await tester.pumpAndSettle();
      expect(find.text('N**** A******* uses FitFlex.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('invite-scope-members')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('invite-send')));
      await tester.pumpAndSettle();

      expect(api.created.single, {
        'gymId': 'gym_1',
        'role': 'staff',
        'email': 'rec@gym.co',
        'aclPermissions': ['members'],
      });
      expect(find.text('Invitation sent.'), findsOneWidget);
      expect(find.byKey(const Key('invite-copy-link')), findsOneWidget);
      expect(find.byKey(const Key('invite-send')), findsNothing);
    },
  );

  testWidgets('a shop invites staff with a role and permissions, no password', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _signedIn(api);
    await tester.pumpWidget(
      _app(
        auth,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openInvitePersonSheet(
              context,
              gymId: 'usr_vendor',
              role: 'staff',
              orgType: 'vendor',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite-vendor-role')), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(6));
    expect(find.byKey(const Key('invite-scope-members')), findsNothing);
    expect(find.byKey(const Key('vendor-staff-password')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('invite-contact')),
      'desk@shop.co',
    );
    await tester.tap(find.byKey(const Key('invite-check')));
    await tester.pumpAndSettle();
    expect(api.lookups, ['vendor:usr_vendor']);
    await tester.tap(find.byKey(const Key('invite-vendor-permission-orders')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('invite-send')));
    await tester.tap(find.byKey(const Key('invite-send')));
    await tester.pumpAndSettle();

    expect(api.created.single, {
      'vendorId': 'usr_vendor',
      'role': 'staff',
      'email': 'desk@shop.co',
      'vendorRole': 'inventory_manager',
      'permissions': ['products', 'orders'],
    });
    expect(find.byKey(const Key('invite-copy-link')), findsOneWidget);
  });

  testWidgets('a shop\'s sent invitations use the vendor routes', (
    tester,
  ) async {
    final api = _FakeApi()
      ..sent = [
        {
          'id': 'inv_v1',
          'role': 'staff',
          'status': 'pending',
          'identifierValue': 'desk@shop.co',
        },
      ];
    final auth = await _signedIn(api);
    await tester.pumpWidget(
      _app(
        auth,
        const GymInvitationsPage(gymId: 'usr_vendor', orgType: 'vendor'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('desk@shop.co'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-inv_v1')));
    await tester.pumpAndSettle();
    expect(api.actions, ['vendor:cancel:inv_v1']);
  });

  testWidgets('a paid invitation that lapsed can be sent again', (
    tester,
  ) async {
    final api = _FakeApi()
      ..sent = [
        {
          'id': 'inv_lapsed',
          'role': 'member',
          'status': 'expired',
          'identifierValue': '+255712345678',
          'needsResolution': true,
          'paidAmountTzs': 30000,
        },
      ];
    final auth = await _signedIn(api);
    await tester.pumpWidget(
      _app(auth, const GymInvitationsPage(gymId: 'gym_1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lapsed-inv_lapsed')), findsOneWidget);
    expect(
      find.textContaining('Paid TZS 30000 but never accepted'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('refunded-inv_lapsed')), findsOneWidget);
    expect(find.byKey(const Key('cancel-inv_lapsed')), findsNothing);

    await tester.tap(find.byKey(const Key('reissue-inv_lapsed')));
    await tester.pumpAndSettle();
    expect(api.actions, ['reissue:inv_lapsed']);
  });
}
