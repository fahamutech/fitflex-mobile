import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/widgets/phone_steps_card.dart';
import 'package:fitflexmobile/shared/activity/phone_steps.dart';
import 'package:fitflexmobile/shared/activity/phone_step_counter.dart';
import 'package:fitflexmobile/shared/activity/step_ledger.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counter implements PhoneStepCounter {
  _Counter({this.grant = true, this.permanent = false});
  bool supported = true, granted = false;
  bool grant, permanent;
  int? value;
  int asked = 0;

  @override
  bool get isSupported => supported;
  @override
  Future<bool> hasPermission() async => granted;
  @override
  Future<bool> requestPermission() async {
    asked += 1;
    granted = grant;
    return grant;
  }

  @override
  Future<bool> isPermanentlyDenied() async => permanent;
  @override
  Future<void> openSettings() async {}
  @override
  Future<int?> readSinceBoot() async => granted ? value : null;
}

class _Store implements StepStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class _Background implements StepBackground {
  bool scheduled = false;
  @override
  Future<void> schedule() async => scheduled = true;
  @override
  Future<void> cancel() async => scheduled = false;
}

class _Api extends ApiClient {
  final sent = <List<Map<String, dynamic>>>[];
  bool offline = false;
  @override
  Future<Map<String, dynamic>> syncDeviceActivities(
    List<Map<String, dynamic>> records,
  ) async {
    if (offline) throw Exception('offline');
    sent.add(records);
    return {'created': records.length};
  }
}

// Thursday 24 Sep 2026, 09:00 local.
DateTime at(int h, [int m = 0, int day = 24]) => DateTime(2026, 9, day, h, m);

void main() {
  group('StepLedger', () {
    test('the first reading is only a starting point', () {
      final l = StepLedger();
      expect(
        l.record(12000, at(9)),
        0,
        reason: 'steps before turning on are not ours to date',
      );
      expect(l.stepsOn(at(9)), 0);
      expect(l.record(12450, at(9, 15)), 450);
      expect(l.record(13000, at(10)), 550);
      expect(l.stepsOn(at(10)), 1000);
    });

    test('a restart is counted from the new reading', () {
      final l = StepLedger()..record(12000, at(9));
      l.record(12500, at(10));
      expect(l.record(300, at(11)), 300, reason: 'counter reset by a reboot');
      expect(l.stepsOn(at(11)), 800);
    });

    test('steps across midnight go to the later day; days are kept apart', () {
      final l = StepLedger()..record(1000, at(23, 50, 23));
      l.record(1100, at(23, 55, 23));
      l.record(1400, at(0, 10, 24));
      expect(l.stepsOn(at(12, 0, 23)), 100);
      expect(l.stepsOn(at(12, 0, 24)), 300);
    });

    test('glitches and the daily limit', () {
      final l = StepLedger()..record(0, at(6));
      expect(
        l.record(250000, at(7)),
        0,
        reason: 'implausible jump is not credited',
      );
      l.record(250000 + 60000, at(8));
      expect(
        l.record(250000 + 60000 + 50000, at(9)),
        40000,
        reason: 'capped at 100,000 a day',
      );
      expect(l.stepsOn(at(9)), maxDailySteps);
      expect(l.record(-5, at(10)), 0);
    });

    test('pending uploads, seeding and saving', () {
      final l = StepLedger()..record(0, at(8, 0, 23));
      l.record(3000, at(20, 0, 23));
      l.record(5000, at(9, 0, 24));
      expect(l.pending().map((p) => (p.key, p.steps)), [
        ('2026-09-23', 3000),
        ('2026-09-24', 2000),
      ]);
      l.markUploaded({'2026-09-23': 3000});
      expect(l.pending().single.key, '2026-09-24');

      final back = StepLedger.fromJson(l.toJson());
      expect(back.lastCount, 5000);
      expect(back.stepsOn(at(9)), 2000);
      expect(back.pending().single.steps, 2000);

      // Turned back on: the server's 6,000 for today is where it continues.
      final again = StepLedger()..seed({'2026-09-24': 6000});
      again.record(100, at(12));
      again.record(400, at(13));
      expect(again.stepsOn(at(13)), 6300);
      expect(again.pending().single.steps, 6300);
    });

    test('keeps about a month', () {
      final l = StepLedger()..record(0, at(8, 0, 1));
      l.record(100, at(9, 0, 1));
      l.record(200, DateTime(2026, 10, 20, 9));
      expect(l.days.keys, ['2026-10-20']);
    });
  });

  group('PhoneSteps', () {
    late _Counter counter;
    late _Store store;
    late _Background bg;
    late _Api api;
    var now = at(9);
    PhoneSteps make() => PhoneSteps(
      counter: counter,
      store: store,
      background: bg,
      now: () => now,
    );

    setUp(() {
      counter = _Counter();
      store = _Store();
      bg = _Background();
      api = _Api();
      now = at(9);
    });

    test(
      'turning on asks for permission, takes a starting point and schedules readings',
      () async {
        counter.value = 5000;
        final s = make();
        await s.load();
        expect(s.enabled, isFalse);
        expect(await s.enable(), isTrue);
        expect(counter.asked, 1);
        expect(s.enabled, isTrue);
        expect(bg.scheduled, isTrue);
        expect(await s.sync(api), isFalse, reason: 'no new steps yet');

        counter.value = 5800;
        now = at(9, 30);
        expect(await s.sync(api), isTrue);
        final rec = api.sent.single.single;
        expect(rec['devicePlatform'], 'phone_sensor');
        expect(rec['externalId'], 'steps:2026-09-24');
        expect(rec['type'], 'walking');
        expect(rec['steps'], 800);
        expect(
          DateTime.parse(rec['startedAt'] as String).toLocal(),
          DateTime(2026, 9, 24),
        );
        expect(s.countedToday, 800);

        expect(await s.sync(api), isFalse, reason: 'nothing new, nothing sent');
        expect(api.sent, hasLength(1));

        // Survives a restart of the app.
        final again = make();
        await again.load();
        expect(again.enabled, isTrue);
        expect(again.countedToday, 800);
      },
    );

    test('offline: kept and sent next time', () async {
      counter.value = 100;
      final s = make();
      await s.load();
      await s.enable();
      counter.value = 400;
      api.offline = true;
      expect(await s.sync(api), isFalse);
      api.offline = false;
      counter.value = 450;
      expect(await s.sync(api), isTrue);
      expect(api.sent.single.single['steps'], 350);
    });

    test('permission refused, or withdrawn in Settings', () async {
      counter.grant = false;
      counter.permanent = true;
      final s = make();
      await s.load();
      expect(await s.enable(), isFalse);
      expect(s.enabled, isFalse);
      expect(s.needsSettings, isTrue);
      expect(bg.scheduled, isFalse);

      counter.grant = true;
      counter.permanent = false;
      expect(await s.enable(), isTrue);
      counter.granted = false;
      final after = make();
      await after.load();
      expect(
        after.enabled,
        isFalse,
        reason: 'permission withdrawn turns it off',
      );
    });

    test(
      'off: nothing read or sent; sign-out forgets the phone\'s days',
      () async {
        counter.value = 100;
        final s = make();
        await s.load();
        await s.enable();
        counter.value = 900;
        await s.sync(api);
        await s.disable();
        counter.value = 5000;
        expect(await s.sync(api), isFalse);
        expect(bg.scheduled, isFalse);

        await s.forget();
        final next = make();
        await next.load();
        expect(next.enabled, isFalse);
        expect(next.countedToday, 0);
        expect((await PhoneSteps.loadLedger(store)).days, isEmpty);
      },
    );

    test('not offered where the phone has no counter', () async {
      counter.supported = false;
      final s = make();
      await s.load();
      expect(s.supported, isFalse);
      expect(await s.enable(), isFalse);
    });
  });

  group('UI', () {
    Widget app(PhoneSteps? steps, Widget child) => AppScope(
      api: _Api(),
      auth: AuthState(_Api()),
      phoneSteps: steps,
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          theme: buildTheme(),
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

    testWidgets('turn on from Home, then it says it is counting', (
      tester,
    ) async {
      final counter = _Counter()..value = 2000;
      final steps = PhoneSteps(
        counter: counter,
        store: _Store(),
        background: _Background(),
        now: () => at(9),
      );
      await steps.load();
      await tester.pumpWidget(
        app(steps, const PhoneStepsCard(dismissible: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Count your steps with this phone'), findsOneWidget);
      await tester.tap(find.byKey(const Key('phone-steps-enable')));
      await tester.pumpAndSettle();
      expect(steps.enabled, isTrue);
      expect(find.byKey(const Key('phone-steps-counting')), findsOneWidget);
      expect(
        find.text('Counting steps on this phone · 0 today'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Counting steps. Walk a little'),
        findsOneWidget,
      );
    });

    testWidgets('"Not now" hides it on Home; hidden when not offered', (
      tester,
    ) async {
      final steps = PhoneSteps(
        counter: _Counter(),
        store: _Store(),
        background: _Background(),
      );
      await steps.load();
      await tester.pumpWidget(
        app(steps, const PhoneStepsCard(dismissible: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('phone-steps-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('phone-steps-prompt')), findsNothing);

      await tester.pumpWidget(app(null, const PhoneStepsCard()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('phone-steps-prompt')), findsNothing);
    });

    testWidgets('denied for good: points to Settings', (tester) async {
      final steps = PhoneSteps(
        counter: _Counter(grant: false, permanent: true),
        store: _Store(),
        background: _Background(),
      );
      await steps.load();
      await tester.pumpWidget(app(steps, const PhoneStepsCard()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('phone-steps-enable')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('phone-steps-settings')), findsOneWidget);
      expect(find.textContaining('Physical activity'), findsWidgets);
    });

    testWidgets('Privacy switch turns it on and off', (tester) async {
      final steps = PhoneSteps(
        counter: _Counter()..value = 10,
        store: _Store(),
        background: _Background(),
      );
      await steps.load();
      await tester.pumpWidget(app(steps, const PhoneStepsSwitch()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('phone-steps-switch')));
      await tester.pumpAndSettle();
      expect(steps.enabled, isTrue);
      await tester.tap(find.byKey(const Key('phone-steps-switch')));
      await tester.pumpAndSettle();
      expect(steps.enabled, isFalse);
    });
  });
}
