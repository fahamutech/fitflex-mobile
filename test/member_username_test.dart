import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_edit_profile_page.dart';
import 'package:fitflexmobile/screens/owner/members/data/member_models.dart';
import 'package:fitflexmobile/screens/owner/members/widgets/member_list_tile.dart';
import 'package:fitflexmobile/screens/owner/widgets/latest_checkins_card.dart';
import 'package:fitflexmobile/shared/activity/challenge.dart';
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/social.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.taken = const {}, this.setError})
    : super(baseUrl: 'http://x.local');

  final Set<String> taken;
  final ApiException? setError;
  final List<String> saved = [];
  int cleared = 0;
  final List<String> checked = [];
  final List<Map<String, dynamic>> profiles = [];

  @override
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profile,
  ) async {
    profiles.add(profile);
    return {'user': {}};
  }

  @override
  Future<Map<String, dynamic>> usernameAvailable(String handle) async {
    checked.add(handle);
    final isTaken = taken.contains(handle.toLowerCase());
    return {'available': !isTaken, 'reason': isTaken ? 'username_taken' : null};
  }

  @override
  Future<Map<String, dynamic>> setUsername(String handle) async {
    if (setError != null) throw setError!;
    saved.add(handle);
    return {'username': handle};
  }

  @override
  Future<Map<String, dynamic>> clearUsername() async {
    cleared++;
    return {'username': null};
  }
}

MemberMeResponse _me({
  String? current,
  DateTime? changeableAt,
  bool enabled = true,
}) => MemberMeResponse.fromJson({
  'user': {
    'id': 'u1',
    'displayName': 'Amina Said',
    'phone': '+255700000001',
    'email': 'amina@example.com',
    'memberProfile': {
      'fitnessGoals': ['stay_fit'],
      'fitnessLevel': 'beginner',
      'preferredWorkoutTimes': ['morning'],
    },
  },
  if (enabled) 'username': current,
  if (enabled && changeableAt != null)
    'usernameChangeableAt': changeableAt.toIso8601String(),
});

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeApi api, {
  String? current,
  DateTime? changeableAt,
  bool enabled = true,
}) async {
  // The page is one long list; a tall viewport keeps every field built.
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final loc = FFLocale();
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: AuthState(api),
      child: FFLocaleScope(
        notifier: loc,
        child: MaterialApp(
          theme: buildTheme(),
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MemberEditProfilePage(
            me: _me(
              current: current,
              changeableAt: changeableAt,
              enabled: enabled,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.byKey(const Key('username-field')));
  await tester.enterText(find.byKey(const Key('username-field')), text);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('edit-profile-save')));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('parsing', () {
    test('/me with the feature on: username fields are read', () {
      final me = MemberMeResponse.fromJson({
        'user': {'id': 'u1', 'userType': 'member'},
        'visitsUsed': 0,
        'username': 'amina_k',
        'usernameChangeableAt': '2026-11-12T10:00:00.000Z',
      });
      expect(me.usernameEnabled, isTrue);
      expect(me.username, 'amina_k');
      expect(me.usernameChangeableAt, isNotNull);
    });

    test('feature on but no username yet: enabled, no handle', () {
      final me = MemberMeResponse.fromJson({
        'user': {'id': 'u1', 'userType': 'member'},
        'visitsUsed': 0,
        'username': null,
      });
      expect(me.usernameEnabled, isTrue);
      expect(me.username, isNull);
    });

    test('feature off: the server sends nothing, so the UI stays hidden', () {
      final me = MemberMeResponse.fromJson({
        'user': {'id': 'u1', 'userType': 'member'},
        'visitsUsed': 0,
      });
      expect(me.usernameEnabled, isFalse);
    });

    test('a person shows as @username, else the name, else a fallback', () {
      expect(
        SocialPerson.fromJson({
          'id': '1',
          'displayName': 'amina_k',
          'username': 'amina_k',
        }).name,
        '@amina_k',
      );
      expect(
        SocialPerson.fromJson({'id': '1', 'displayName': 'Amina Said'}).name,
        'Amina Said',
      );
      expect(SocialPerson.fromJson({'id': '1'}).name, 'FitFlex member');
    });
  });

  group('partner views show the name with the username beside it', () {
    test('check-in label', () {
      expect(
        checkinVisitorLabel({
          'displayName': 'Amina Said',
          'username': 'amina_k',
          'memberPublicId': 'FM001',
        }),
        'Amina Said (@amina_k)',
      );
      expect(
        checkinVisitorLabel({'username': 'amina_k', 'memberPublicId': 'FM001'}),
        'FM001 (@amina_k)',
      );
      expect(
        checkinVisitorLabel({
          'displayName': 'Amina Said',
          'memberPublicId': 'FM001',
        }),
        'Amina Said',
      );
    });

    testWidgets('members list row', (tester) async {
      final member = OwnerMember.fromJson({
        'id': 'u1',
        'publicId': 'FM001',
        'displayName': 'Amina Said',
        'username': 'amina_k',
        'memberType': 'direct',
        'status': 'active',
      });
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: MemberListTile(member: member, onTap: () {}),
            ),
          ),
        ),
      );
      expect(find.text('Amina Said'), findsOneWidget);
      expect(find.textContaining('@amina_k'), findsOneWidget);
    });
  });

  group('MemberEditProfilePage', () {
    testWidgets('one Save sends details, goals and workout times together', (
      tester,
    ) async {
      final api = _FakeApi();
      await _pumpPage(tester, api, enabled: false);
      expect(find.byKey(const Key('username-field')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('goal-build_muscle')));
      await tester.tap(find.byKey(const Key('goal-build_muscle')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('time-evening')));
      await tester.tap(find.byKey(const Key('time-evening')));
      await tester.pump();
      await _save(tester);
      expect(api.profiles, hasLength(1));
      final sent = api.profiles.single;
      expect(sent['displayName'], 'Amina Said');
      expect(
        sent.containsKey('phone') || sent.containsKey('email'),
        isFalse,
        reason: 'phone and email only change through verification',
      );
      expect(
        sent['fitnessGoals'],
        unorderedEquals(['stay_fit', 'build_muscle']),
      );
      expect(sent['fitnessLevel'], 'beginner');
      expect(
        sent['preferredWorkoutTimes'],
        unorderedEquals(['morning', 'evening']),
      );
      expect(api.saved, isEmpty, reason: 'no username change was made');
    });

    testWidgets('phone and email are shown but cannot be typed into', (
      tester,
    ) async {
      final api = _FakeApi();
      await _pumpPage(tester, api, enabled: false);
      for (final key in const ['edit-profile-phone', 'edit-profile-email']) {
        final field = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(EditableText),
          ),
        );
        expect(field.readOnly, isTrue, reason: key);
      }
      expect(find.text('+255700000001'), findsOneWidget);
      expect(find.text('amina@example.com'), findsOneWidget);
    });

    testWidgets('typing a username checks availability, Save sends it', (
      tester,
    ) async {
      final api = _FakeApi();
      await _pumpPage(tester, api);
      await _type(tester, 'amina_k');
      expect(api.checked, ['amina_k']);
      expect(find.text('Available'), findsOneWidget);
      await _save(tester);
      expect(api.profiles, hasLength(1));
      expect(api.saved, ['amina_k']);
    });

    testWidgets('a taken name says so and blocks Save', (tester) async {
      final api = _FakeApi(taken: {'juma99'});
      await _pumpPage(tester, api);
      await _type(tester, 'Juma99');
      expect(find.text('Already taken'), findsOneWidget);
      await _save(tester);
      expect(api.profiles, isEmpty);
      expect(api.saved, isEmpty);
    });

    testWidgets('saving sends the handle without any @', (tester) async {
      final api = _FakeApi();
      await _pumpPage(tester, api);
      await _type(tester, '@amina.k');
      await _save(tester);
      expect(api.saved, ['amina.k']);
    });

    testWidgets(
      'within the 30-day limit: field is locked, the rest still saves',
      (tester) async {
        final api = _FakeApi();
        await _pumpPage(
          tester,
          api,
          current: 'amina_k',
          changeableAt: DateTime.now().add(const Duration(days: 10)),
        );
        await tester.ensureVisible(find.byKey(const Key('username-cooldown')));
        expect(find.byKey(const Key('username-cooldown')), findsOneWidget);
        expect(
          find.textContaining('You can change it again on'),
          findsOneWidget,
        );
        final field = tester.widget<TextFormField>(
          find.descendant(
            of: find.byKey(const Key('username-field')),
            matching: find.byType(TextFormField),
          ),
        );
        expect(field.enabled, isFalse);
        await _save(tester);
        expect(api.profiles, hasLength(1));
        expect(api.saved, isEmpty);
        expect(api.cleared, 0);
      },
    );

    testWidgets('a server refusal is shown in words, not as a code', (
      tester,
    ) async {
      final api = _FakeApi(
        setError: ApiException(400, {'error': 'username_reserved'}),
      );
      await _pumpPage(tester, api);
      await _type(tester, 'helper_x');
      await _save(tester);
      await tester.ensureVisible(find.byKey(const Key('username-status')));
      expect(find.text("This name can't be used"), findsOneWidget);
      expect(find.textContaining('username_reserved'), findsNothing);
    });

    testWidgets('clearing the field removes an existing username', (
      tester,
    ) async {
      final api = _FakeApi();
      await _pumpPage(tester, api, current: 'amina_k');
      await _type(tester, '');
      await _save(tester);
      expect(api.cleared, 1);
      expect(api.saved, isEmpty);
    });
  });

  group('@username where the server sends a separate field', () {
    test('group members', () {
      expect(
        GroupMember.fromJson({
          'id': '1',
          'displayName': 'amina_k',
          'username': 'amina_k',
        }).name,
        '@amina_k',
      );
      expect(
        GroupMember.fromJson({'id': '1', 'displayName': 'Amina Said'}).name,
        'Amina Said',
      );
    });

    test('reviews', () {
      final withHandle = Review.fromJson({
        'id': 'r1',
        'rating': 5,
        'memberName': 'amina_k',
        'memberUsername': 'amina_k',
      });
      expect(withHandle.memberLabel, '@amina_k');
      final plain = Review.fromJson({
        'id': 'r2',
        'rating': 5,
        'memberName': 'Aisha M.',
      });
      expect(plain.memberLabel, 'Aisha M.');
    });

    test('leaderboard rows', () {
      final board = ChallengeLeaderboard.fromJson({
        'participants': 2,
        'individuals': [
          {
            'rank': 1,
            'name': 'amina_k',
            'username': 'amina_k',
            'progress': 10,
            'fraction': 0.5,
          },
          {'rank': 2, 'name': 'Baraka J.', 'progress': 5, 'fraction': 0.25},
        ],
      });
      expect(board.individuals[0].label, '@amina_k');
      expect(board.individuals[1].label, 'Baraka J.');
    });

    test("a trainer's client: name with the username beside it", () {
      final both = ConnectionPerson.tryParse({
        'id': 'm1',
        'displayName': 'Amina Said',
        'username': 'amina_k',
      })!;
      expect(both.label, 'Amina Said (@amina_k)');
      final plain = ConnectionPerson.tryParse({
        'id': 'm2',
        'displayName': 'Juma Shaban',
      })!;
      expect(plain.label, 'Juma Shaban');
    });
  });
}
