// Edit profile → date of birth (Shop Phase 2 S2 review): a real date picker
// sending YYYY-MM-DD (not in the future, from 1900 on), and the server's
// 400 invalid_field dateOfBirth shown under the field. The date of birth
// decides whether shop personalisation is available (under 18 = off).
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_edit_profile_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.error}) : super(baseUrl: 'http://x.local');

  final ApiException? error;
  final List<Map<String, dynamic>> profiles = [];

  @override
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profile,
  ) async {
    profiles.add(profile);
    if (error != null) throw error!;
    return {'user': {}};
  }
}

MemberMeResponse _me(String? dob) => MemberMeResponse.fromJson({
  'user': {
    'id': 'u1',
    'displayName': 'Amina Said',
    'memberProfile': {
      'fitnessGoals': ['stay_fit'],
      'fitnessLevel': 'beginner',
      'preferredWorkoutTimes': ['morning'],
      'dateOfBirth': ?dob,
    },
  },
});

Future<FFLocale> _pump(WidgetTester tester, _FakeApi api, String? dob) async {
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
          home: MemberEditProfilePage(me: _me(dob)),
        ),
      ),
    ),
  );
  await tester.pump();
  return loc;
}

Finder get _dob => find.byKey(const Key('edit-profile-dob'));

String _dobText(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(of: _dob, matching: find.byType(TextField)),
    )
    .controller!
    .text;

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('edit-profile-save')));
  await tester.pumpAndSettle();
}

void main() {
  group('helpers', () {
    test('parse accepts only real calendar days', () {
      expect(parseDateOfBirth('1990-05-10'), DateTime(1990, 5, 10));
      expect(parseDateOfBirth('2026-02-30'), isNull);
      expect(parseDateOfBirth('1990/05/10'), isNull);
      expect(parseDateOfBirth('10-05-1990'), isNull);
      expect(formatDateOfBirth(DateTime(1990, 5, 1)), '1990-05-01');
      expect(normaliseDateOfBirth('1990-05-10T00:00:00.000Z'), '1990-05-10');
      expect(normaliseDateOfBirth('1990/05/10'), '1990/05/10');
    });

    test('today is the East Africa day (UTC+3), whatever the device zone', () {
      expect(
        eastAfricaToday(now: DateTime.utc(2026, 10, 21, 22, 30)),
        DateTime(2026, 10, 22),
      );
      expect(
        eastAfricaToday(now: DateTime.utc(2026, 10, 21, 20, 59)),
        DateTime(2026, 10, 21),
      );
    });
  });

  testWidgets('a stored timestamp shows as YYYY-MM-DD; typing is '
      'YYYY-MM-DD only (digits and dashes, 10 characters)', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api, '1990-05-10T00:00:00.000Z');
    expect(_dobText(tester), '1990-05-10');
    expect(
      tester.getSize(find.byKey(const Key('edit-profile-dob-pick'))).height,
      greaterThanOrEqualTo(48),
    );
    final input = find.descendant(of: _dob, matching: find.byType(TextField));
    await tester.enterText(input, '12/05/1988abc');
    await tester.pump();
    expect(_dobText(tester), '12051988');
    await tester.enterText(input, '1988-05-12-99');
    await tester.pump();
    expect(_dobText(tester), '1988-05-12');
    await _save(tester);
    expect(api.profiles.single['dateOfBirth'], '1988-05-12');
  });

  testWidgets('a typed date in another order is refused with the format '
      'message', (tester) async {
    final api = _FakeApi();
    final loc = await _pump(tester, api, null);
    final input = find.descendant(of: _dob, matching: find.byType(TextField));
    await tester.enterText(input, '05-12-1988');
    await _save(tester);
    expect(api.profiles, isEmpty);
    expect(
      find.text(
        '${loc.t('member.dobFormat')} ${loc.t('member.dobNoPersonalisation')}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the picker is calendar-only (no locale typed entry), its '
      'buttons are 48dp, and Save and Close are labelled and 48dp', (
    tester,
  ) async {
    await _pump(tester, _FakeApi(), '1990-05-10');
    expect(
      tester.getSize(find.byKey(const Key('edit-profile-save'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('edit-profile-close')))
          .tooltip,
      'Close',
    );
    expect(find.bySemanticsLabel('Change profile photo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-profile-dob-pick')));
    await tester.pumpAndSettle();
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.initialEntryMode, DatePickerEntryMode.calendarOnly);
    // No switch to the typed (M/D/YYYY) entry.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    final ok = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    );
    for (final label in [ok.okButtonLabel, ok.cancelButtonLabel]) {
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(TextButton),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
        reason: label,
      );
    }
  });

  testWidgets('picking a day sends YYYY-MM-DD', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api, '1990-05-10');
    await tester.tap(find.byKey(const Key('edit-profile-dob-pick')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_dobText(tester), '1990-05-15');
    await _save(tester);
    expect(api.profiles.single['dateOfBirth'], '1990-05-15');
  });

  testWidgets('the picker allows 1900 to today only', (tester) async {
    await _pump(tester, _FakeApi(), null);
    await tester.tap(find.byKey(const Key('edit-profile-dob-pick')));
    await tester.pumpAndSettle();
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.firstDate, DateTime(1901));
    expect(dialog.lastDate, eastAfricaToday());
  });

  testWidgets('clearing sends "" (null would keep the stored date)', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api, '1990-05-10');
    await tester.tap(find.byKey(const Key('edit-profile-dob-clear')));
    await tester.pump();
    expect(_dobText(tester), '');
    await _save(tester);
    expect(api.profiles.single['dateOfBirth'], '');
  });

  for (final stored in [
    '1990/05/01',
    '2999-01-01',
    '1900-12-31',
    '1990-02-30',
  ]) {
    testWidgets('a stored "$stored" is flagged on open and not sent', (
      tester,
    ) async {
      final api = _FakeApi();
      final loc = await _pump(tester, api, stored);
      await tester.pumpAndSettle();
      final key = parseDateOfBirth(stored) == null
          ? 'member.dobFormat'
          : 'member.dobInvalid';
      final message = '${loc.t(key)} ${loc.t('member.dobNoPersonalisation')}';
      // Shown at once, before Save.
      expect(find.text(message), findsOneWidget);
      await _save(tester);
      expect(api.profiles, isEmpty);
      expect(find.text(message), findsOneWidget);
    });
  }

  for (final lang in ['en', 'sw']) {
    testWidgets('server 400 invalid_field dateOfBirth shows under the field '
        '($lang)', (tester) async {
      final api = _FakeApi(
        error: ApiException(400, {
          'error': 'invalid_field',
          'field': 'dateOfBirth',
        }),
      );
      final loc = await _pump(tester, api, '1990-05-10');
      loc.set(Locale(lang));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(api.profiles, hasLength(1));
      final message =
          '${loc.t('member.dobInvalid')} '
          '${loc.t('member.dobNoPersonalisation')}';
      expect(loc.t('member.dobInvalid'), isNot('member.dobInvalid'));
      expect(
        find.descendant(of: _dob, matching: find.text(message)),
        findsOneWidget,
      );
      // Choosing a new date clears it.
      await tester.tap(find.byKey(const Key('edit-profile-dob-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12'));
      await tester.tap(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(DatePickerDialog)),
          ).okButtonLabel,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
    });
  }
}
