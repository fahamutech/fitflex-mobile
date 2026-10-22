// Date of birth rule shared by onboarding and Edit profile, matching the
// backend (fitflex-functions src/shared/date-of-birth.mjs): strict
// YYYY-MM-DD, a real day, 1901-01-01 to today in East Africa; the server's
// refusal is 400 { error: 'invalid_field', field: 'dateOfBirth' }.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_onboarding_controller.dart';
import 'package:fitflexmobile/screens/member/member_onboarding_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/date_of_birth.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

ApiException get _dobRefused =>
    ApiException(400, {'error': 'invalid_field', 'field': 'dateOfBirth'});

void main() {
  group('dateOfBirthProblemKey', () {
    // 2026-10-21 23:30 UTC is already 2026-10-22 in Dar es Salaam.
    final now = DateTime.utc(2026, 10, 21, 23, 30);

    test('empty is fine (it clears the date)', () {
      expect(dateOfBirthProblemKey('', now: now), isNull);
      expect(dateOfBirthProblemKey('   ', now: now), isNull);
      expect(dateOfBirthProblemKey(null, now: now), isNull);
    });

    test('a real day from 1901-01-01 to today (East Africa) is fine', () {
      expect(dateOfBirthProblemKey('1901-01-01', now: now), isNull);
      expect(dateOfBirthProblemKey('1990-05-10', now: now), isNull);
      expect(dateOfBirthProblemKey('2026-10-22', now: now), isNull);
    });

    test('not a real YYYY-MM-DD day, or before 1901: invalid', () {
      for (final bad in [
        '2011/05/03',
        '03/05/2011',
        '2011-5-3',
        '1990-02-30',
        '1900-12-31',
        'abc',
      ]) {
        expect(
          dateOfBirthProblemKey(bad, now: now),
          'member.dobInvalid',
          reason: bad,
        );
      }
    });

    test('after today in East Africa: future', () {
      expect(dateOfBirthProblemKey('2026-10-23', now: now), 'member.dobFuture');
      expect(dateOfBirthProblemKey('2999-01-01', now: now), 'member.dobFuture');
    });
  });

  group('server error mapping', () {
    test('400 invalid_field dateOfBirth maps to the date-of-birth line', () {
      final loc = FFLocale();
      expect(isDateOfBirthError(_dobRefused), isTrue);
      expect(
        dateOfBirthErrorMessage(loc, _dobRefused),
        'Enter a real date of birth.',
      );
      loc.set(const Locale('sw'));
      expect(
        dateOfBirthErrorMessage(loc, _dobRefused),
        'Weka tarehe sahihi ya kuzaliwa.',
      );
    });

    test('other errors are not mapped', () {
      final loc = FFLocale();
      final other = ApiException(400, {
        'error': 'invalid_field',
        'field': 'heightCm',
      });
      expect(isDateOfBirthError(other), isFalse);
      expect(dateOfBirthErrorMessage(loc, other), isNull);
      expect(isDateOfBirthError(ApiException(500, 'oops')), isFalse);
      expect(isDateOfBirthError(Exception('x')), isFalse);
    });

    test('both messages exist in English and Swahili', () {
      for (final key in ['member.dobInvalid', 'member.dobFuture']) {
        final loc = FFLocale();
        final en = loc.t(key);
        loc.set(const Locale('sw'));
        final sw = loc.t(key);
        expect(en, isNot(key));
        expect(sw, isNot(key));
        expect(sw, isNot(en));
      }
    });

    test('onboarding submit shows the date-of-birth line, not a generic '
        'error', () async {
      final api = _FakeApi(error: _dobRefused);
      final loc = FFLocale()..set(const Locale('sw'));
      final controller = MemberOnboardingController(
        api: api,
        auth: AuthState(api),
        locale: loc,
      );
      addTearDown(controller.dispose);
      controller.dobCtrl.text = '1990-05-10';
      String? shown;
      await controller.submit(onSuccess: () {}, onError: (m) => shown = m);
      expect(api.profiles.single['dateOfBirth'], '1990-05-10');
      expect(shown, 'Weka tarehe sahihi ya kuzaliwa.');
    });
  });

  testWidgets('onboarding: the picker allows 1901-01-01 to today (East '
      'Africa) and fills YYYY-MM-DD', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeApi();
    final loc = FFLocale();
    await tester.pumpWidget(
      AppScope(
        api: api,
        auth: AuthState(api),
        child: ThemeScope(
          notifier: ThemeNotifier(),
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
              home: const MemberOnboardingPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Step 0: pick a goal, go on to the personal step.
    await tester.tap(find.text(loc.t('onboarding.goal_lose_weight')));
    await tester.pump();
    await tester.tap(find.text(loc.t('onboarding.next')));
    await tester.pumpAndSettle();

    await tester.tap(
      find
          .ancestor(
            of: find.text(loc.t('onboarding.dob')),
            matching: find.byType(TextField),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.firstDate, DateTime(1901));
    expect(dialog.lastDate, eastAfricaToday());
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final today = eastAfricaToday();
    final picked = DateTime(today.year - 25, today.month, 15);
    expect(find.text(formatDateOfBirth(picked)), findsOneWidget);
    expect(
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(formatDateOfBirth(picked)),
      isTrue,
    );
  });
}
