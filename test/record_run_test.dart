import 'dart:async';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_record_run_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/run_widgets.dart';
import 'package:fitflexmobile/shared/activity/gps_source.dart';
import 'package:fitflexmobile/shared/activity/phone_steps.dart' show StepStore;
import 'package:fitflexmobile/shared/activity/run_metrics.dart';
import 'package:fitflexmobile/shared/activity/run_recorder.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 9, 25, 5);
const deg100m = 0.0009;

/// A run due north at [secPer100m], one point per 100 m (as the server spec).
List<TrackPoint> run(
  int meters, {
  int secPer100m = 30,
  double lat0 = -6.8,
  DateTime? start,
  double Function(int)? alt,
  double acc = 5,
}) => [
  for (var i = 0; i <= meters ~/ 100; i++)
    TrackPoint(
      lat0 + i * deg100m,
      39.28,
      alt?.call(i) ?? 20,
      (start ?? t0).add(Duration(seconds: i * secPer100m)),
      acc,
    ),
];

class _Gps implements GpsSource {
  _Gps({this.access = GpsAccess.granted});
  GpsAccess access;
  StreamController<TrackPoint>? ctrl;
  int starts = 0;

  @override
  bool get isSupported => true;
  @override
  Future<GpsAccess> ensureAccess() async => access;
  @override
  Stream<TrackPoint> track({
    required String notificationTitle,
    required String notificationText,
  }) {
    starts += 1;
    ctrl = StreamController<TrackPoint>();
    return ctrl!.stream;
  }

  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationSettings() async {}
}

class _Store implements StepStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class _Api extends ApiClient {
  Map<String, dynamic>? sent;
  Object? fail;
  @override
  Future<Map<String, dynamic>> recordRun(Map<String, dynamic> body) async {
    if (fail != null) throw fail!;
    sent = body;
    return {
      'activity': {
        'id': 'act_run',
        'userId': 'm1',
        'type': 'running',
        'source': 'fitflex',
        'startedAt': t0.toIso8601String(),
        'distanceKm': 2.0,
        'movingSeconds': 600,
        'hasRoute': true,
        'splits': [300, 300],
      },
    };
  }
}

Future<void> _feed(_Gps gps, List<TrackPoint> pts) async {
  for (final p in pts) {
    gps.ctrl!.add(p);
  }
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('run metrics (same fixtures as the server spec)', () {
    test('distance, moving time and per-km splits', () {
      final m = trackMetrics(cleanTrack([run(3000)]));
      expect(m.distanceKm, closeTo(3.0, 0.02));
      expect(m.movingSeconds, 900);
      expect(m.splits, hasLength(3));
      for (final s in m.splits) {
        expect(s, closeTo(300, 2));
      }
      expect(formatPace(m.paceSecPerKm), '5:00');
      expect(m.speedKmh, closeTo(12, 0.1));
    });

    test('pauses are left out; jumps and unsure points dropped', () {
      final a = run(1000);
      final b = run(
        1000,
        lat0: a.last.lat,
        start: a.last.time.add(const Duration(minutes: 10)),
      );
      final m = trackMetrics(cleanTrack([a, b]));
      expect(m.distanceKm, closeTo(2.0, 0.02));
      expect(m.movingSeconds, 600);

      final pts = run(1000);
      pts.insert(
        5,
        TrackPoint(
          pts[4].lat + 0.05,
          39.28,
          20,
          pts[4].time.add(const Duration(seconds: 1)),
          5,
        ),
      );
      pts[7] = TrackPoint(pts[7].lat, pts[7].lng, 20, pts[7].time, 80);
      final clean = cleanTrack([pts]);
      expect(clean.single, hasLength(pts.length - 2));
    });

    test('climb and calories', () {
      final noisy = run(2000, alt: (i) => 20 + (i.isOdd ? 1.5 : -1.5));
      expect(elevationGainM(noisy), 0);
      final hill = run(
        2000,
        alt: (i) => i <= 10 ? 20.0 + i * 5 : 70.0 - (i - 10) * 5,
      );
      expect(elevationGainM(hill), inInclusiveRange(40, 50));

      final kcal = runCalories(
        distanceKm: 5,
        movingSeconds: 1800,
        weightKg: 70,
      )!;
      expect(kcal, inInclusiveRange(370, 400));
      expect(
        runCalories(distanceKm: 5, movingSeconds: 1800),
        isNull,
        reason: 'no weight, no estimate',
      );
      expect(formatDuration(3725), '1:02:05');
      expect(formatDuration(610), '10:10');
    });

    test('points round-trip in the server\'s format', () {
      final p = TrackPoint(-6.8, 39.28, 12.5, t0, 4);
      final back = TrackPoint.fromWire(p.toWire())!;
      expect(back.lat, -6.8);
      expect(back.altitude, 12.5);
      expect(back.time.isAtSameMomentAs(t0), isTrue);
      expect(TrackPoint.fromWire(['x']), isNull);
    });
  });

  group('RunRecorder', () {
    late _Gps gps;
    late _Store store;
    late _Api api;
    var clock = t0;
    RunRecorder make() => RunRecorder(gps: gps, store: store, now: () => clock);
    Future<bool> start(RunRecorder r) =>
        r.start(notificationTitle: 't', notificationText: 'x');

    setUp(() {
      gps = _Gps();
      store = _Store();
      api = _Api();
      clock = t0;
    });

    test('start → points → pause → resume → finish → save', () async {
      final r = make();
      expect(await start(r), isTrue);
      expect(r.state, RunState.recording);
      final a = run(1000);
      await _feed(gps, a);
      expect(r.metrics.distanceKm, closeTo(1.0, 0.02));

      clock = t0.add(const Duration(minutes: 5));
      await r.pause();
      expect(r.state, RunState.paused);
      expect(r.elapsed, const Duration(minutes: 5));

      clock = t0.add(const Duration(minutes: 15));
      await r.resume(notificationTitle: 't', notificationText: 'x');
      expect(gps.starts, 2);
      await _feed(gps, run(1000, lat0: a.last.lat, start: clock));
      clock = clock.add(const Duration(minutes: 5));
      await r.finish();
      expect(r.state, RunState.finished);
      expect(r.segments, hasLength(2));
      expect(r.metrics.distanceKm, closeTo(2.0, 0.03));
      expect(r.metrics.movingSeconds, 600);
      expect(
        r.elapsed,
        const Duration(minutes: 10),
        reason: 'the 10-minute pause is not counted',
      );

      final saved = await r.save(api, notes: ' Coco beach ');
      expect(api.sent!['type'], 'running');
      expect(api.sent!['notes'], 'Coco beach');
      final segs = api.sent!['segments'] as List;
      expect(segs, hasLength(2));
      expect((segs.first as List).first, hasLength(5));
      expect(saved.isRecordedRun, isTrue);
      expect(saved.hasRoute, isTrue);
      expect(r.state, RunState.idle);
    });

    test('an interrupted run comes back paused', () async {
      final r = make();
      await start(r);
      await _feed(gps, run(1200));
      clock = t0.add(const Duration(minutes: 6));
      await r.pause();

      final after = make();
      await after.restore();
      expect(after.state, RunState.paused);
      expect(after.restored, isTrue);
      expect(after.metrics.distanceKm, closeTo(1.2, 0.02));
      expect(after.elapsed, const Duration(minutes: 6));
    });

    test('a failed save keeps the run; discard clears it', () async {
      final r = make();
      await start(r);
      await _feed(gps, run(1000));
      await r.finish();
      api.fail = Exception('offline');
      await expectLater(r.save(api), throwsException);
      expect(r.state, RunState.finished);
      await r.discard();
      expect(r.state, RunState.idle);
      final again = make();
      await again.restore();
      expect(again.state, RunState.idle);
    });

    test('no location: says why and does not start', () async {
      gps.access = GpsAccess.deniedForever;
      final r = make();
      expect(await start(r), isFalse);
      expect(r.state, RunState.idle);
      expect(r.access, GpsAccess.deniedForever);
      expect(gps.starts, 0);
    });
  });

  group('screens', () {
    Widget app(RunRecorder? r, Widget child, {ApiClient? api}) {
      final a = api ?? _Api();
      return AppScope(
        api: a,
        auth: AuthState(a),
        runRecorder: r,
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
            home: MemberDataScope(
              data: MemberData(),
              child: Scaffold(body: child),
            ),
          ),
        ),
      );
    }

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets(
      'Record a run button: hidden when not offered, live while running',
      (tester) async {
        await tester.pumpWidget(app(null, const RecordRunButton()));
        expect(find.byKey(const Key('record-run-open')), findsNothing);

        final gps = _Gps();
        final r = RunRecorder(gps: gps, store: _Store());
        await tester.pumpWidget(app(r, const RecordRunButton()));
        expect(find.text('Record a run'), findsOneWidget);
        await tester.runAsync(
          () => r.start(notificationTitle: 't', notificationText: 'x'),
        );
        await tester.pump();
        expect(find.text('Run in progress · 0.00 km'), findsOneWidget);
        await tester.runAsync(r.discard);
      },
    );

    testWidgets('start, pause, finish and save from the run screen', (
      tester,
    ) async {
      tall(tester);
      final gps = _Gps();
      final api = _Api();
      final r = RunRecorder(gps: gps, store: _Store());
      await tester.pumpWidget(app(r, const MemberRecordRunPage(), api: api));
      await tester.pump();
      expect(find.textContaining('Press Start when you'), findsOneWidget);

      await tester.tap(find.byKey(const Key('run-start')));
      await tester.pump();
      expect(r.state, RunState.recording);
      await tester.runAsync(
        () => _feed(gps, run(1000, start: DateTime.now().toUtc())),
      );
      await tester.pump();
      expect(find.text('1.00 km'), findsOneWidget);

      await tester.tap(find.byKey(const Key('run-pause')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(r.state, RunState.paused);
      await tester.tap(find.byKey(const Key('run-finish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run-finish-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run-save')), findsOneWidget);
      expect(find.text('Add your weight for calories'), findsOneWidget);
      expect(find.byKey(const Key('run-splits')), findsOneWidget);
      expect(find.textContaining('Your route is private'), findsOneWidget);
    });

    testWidgets('location refused: explains and offers Settings', (
      tester,
    ) async {
      tall(tester);
      final r = RunRecorder(
        gps: _Gps(access: GpsAccess.denied),
        store: _Store(),
      );
      await tester.pumpWidget(app(r, const MemberRecordRunPage()));
      await tester.tap(find.byKey(const Key('run-start')));
      await tester.pump();
      expect(find.byKey(const Key('run-access')), findsOneWidget);
      expect(find.textContaining('needs your location'), findsOneWidget);
    });

    testWidgets('not offered: says so', (tester) async {
      await tester.pumpWidget(app(null, const MemberRecordRunPage()));
      expect(find.text('Recording runs isn\'t available here'), findsOneWidget);
    });
  });
}
