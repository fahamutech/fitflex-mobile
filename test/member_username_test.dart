import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/widgets/username_sheet.dart';
import 'package:fitflexmobile/screens/owner/members/data/member_models.dart';
import 'package:fitflexmobile/screens/owner/members/widgets/member_list_tile.dart';
import 'package:fitflexmobile/screens/owner/widgets/latest_checkins_card.dart';
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

Future<void> _pumpSheet(
  WidgetTester tester,
  _FakeApi api, {
  String? current,
  DateTime? changeableAt,
}) async {
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
          home: Scaffold(
            body: SingleChildScrollView(
              child: UsernameSheet(
                current: current,
                changeableAt: changeableAt,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('username-field')), text);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.descendant(
    of: find.byKey(const Key('username-save')),
    matching: find.byType(FilledButton),
  ),
);

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

  group('UsernameSheet', () {
    testWidgets('typing checks availability, then Save is enabled', (
      tester,
    ) async {
      final api = _FakeApi();
      await _pumpSheet(tester, api);
      expect(
        _saveButton(tester).onPressed,
        isNull,
        reason: 'nothing typed yet',
      );
      await _type(tester, 'amina_k');
      expect(api.checked, ['amina_k']);
      expect(find.text('Available'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('a taken name says so and cannot be saved', (tester) async {
      final api = _FakeApi(taken: {'juma99'});
      await _pumpSheet(tester, api);
      await _type(tester, 'Juma99');
      expect(find.text('Already taken'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);
    });

    testWidgets('saving sends the handle without any @', (tester) async {
      final api = _FakeApi();
      await _pumpSheet(tester, api);
      await _type(tester, '@amina.k');
      await tester.tap(find.byKey(const Key('username-save')));
      await tester.pump();
      expect(api.saved, ['amina.k']);
    });

    testWidgets(
      'within the 30-day limit: field is locked and the date is shown',
      (tester) async {
        final api = _FakeApi();
        await _pumpSheet(
          tester,
          api,
          current: 'amina_k',
          changeableAt: DateTime.now().add(const Duration(days: 10)),
        );
        expect(find.byKey(const Key('username-cooldown')), findsOneWidget);
        expect(
          find.textContaining('You can change it again on'),
          findsOneWidget,
        );
        expect(_saveButton(tester).onPressed, isNull);
        expect(find.byKey(const Key('username-clear')), findsNothing);
      },
    );

    testWidgets('a server refusal is shown in words, not as a code', (
      tester,
    ) async {
      final api = _FakeApi(
        setError: ApiException(400, {'error': 'username_reserved'}),
      );
      await _pumpSheet(tester, api);
      await _type(tester, 'helper_x');
      await tester.tap(find.byKey(const Key('username-save')));
      await tester.pump();
      await tester.pump();
      expect(find.text("This name can't be used"), findsOneWidget);
      expect(find.textContaining('username_reserved'), findsNothing);
    });

    testWidgets('Remove clears an existing username', (tester) async {
      final api = _FakeApi();
      await _pumpSheet(tester, api, current: 'amina_k');
      await tester.tap(find.byKey(const Key('username-clear')));
      await tester.pump();
      expect(api.cleared, 1);
    });
  });
}
