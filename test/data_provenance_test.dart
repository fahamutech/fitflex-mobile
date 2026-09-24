import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/widgets/activity_widgets.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/activity_provider.dart';
import 'package:fitflexmobile/shared/activity/mock/mock_activity_provider.dart';
import 'package:fitflexmobile/shared/activity/providers/apple_health_provider.dart';
import 'package:fitflexmobile/shared/activity/providers/health_connect_provider.dart';
import 'package:fitflexmobile/shared/activity/providers/wearable_provider.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Activity _a(
  String id,
  ActivitySource source, {
  DevicePlatform? platform,
  String? externalId,
  String? deviceName,
  bool sample = false,
}) => Activity(
  id: id,
  userId: 'u1',
  type: ActivityType.walking,
  source: source,
  startedAt: DateTime(2026, 9, 24, 7),
  steps: 5000,
  devicePlatform: platform,
  externalId: externalId,
  deviceName: deviceName,
  isSample: sample,
);

Widget _app(Widget child) {
  final api = ApiClient();
  return AppScope(
    api: api,
    auth: AuthState(api),
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
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  group('origin', () {
    test('three kinds: device, FitFlex and manual', () {
      expect(
        _a(
          'd',
          ActivitySource.device,
          platform: DevicePlatform.appleHealth,
        ).origin,
        DataOrigin.device,
      );
      expect(_a('f', ActivitySource.fitflex).origin, DataOrigin.fitflex);
      for (final s in [
        ActivitySource.manual,
        ActivitySource.trainer,
        ActivitySource.gym,
      ]) {
        expect(_a('m', s).origin, DataOrigin.manual, reason: s.wire);
      }
    });

    test('a "device" record that names no platform is not device data', () {
      expect(_a('x', ActivitySource.device).origin, DataOrigin.manual);
      final parsed = Activity.fromJson({
        'id': 'x',
        'type': 'walking',
        'source': 'device',
        'startedAt': '2026-09-24T05:00:00Z',
        'steps': 90000,
      });
      expect(parsed.origin, DataOrigin.manual);
      expect(
        Activity.fromJson({
          'id': 'y',
          'type': 'walking',
          'source': 'telepathy',
          'startedAt': '2026-09-24T05:00:00Z',
        }).origin,
        DataOrigin.manual,
        reason: 'unknown sources are the least trusted',
      );
    });

    test('device provenance round-trips; sample never leaves the app', () {
      final a = _a(
        'd',
        ActivitySource.device,
        platform: DevicePlatform.healthConnect,
        externalId: 'hc-1',
        deviceName: 'Pixel Watch',
        sample: true,
      );
      final json = a.toJson();
      expect(json['devicePlatform'], 'health_connect');
      expect(json['externalId'], 'hc-1');
      expect(json['deviceName'], 'Pixel Watch');
      expect(json.containsKey('isSample'), isFalse);
      final back = Activity.fromJson(json);
      expect(back.devicePlatform, DevicePlatform.healthConnect);
      expect(back.isSample, isFalse);
    });

    test('generated history is all marked sample', () async {
      final acts = await MockActivityProvider(
        clock: () => DateTime(2026, 9, 24, 12),
      ).getActivities(from: DateTime(2026, 8, 1), to: DateTime(2026, 9, 25));
      expect(acts, isNotEmpty);
      expect(acts.every((a) => a.isSample), isTrue);
      expect(acts.any((a) => a.origin == DataOrigin.device), isFalse);
    });
  });

  group('device providers', () {
    test('only genuine device records get through', () {
      const hk = DevicePlatform.appleHealth;
      final ok = _a('ok', ActivitySource.device, platform: hk, externalId: '1');
      final records = [
        ok,
        _a('noId', ActivitySource.device, platform: hk),
        _a(
          'other',
          ActivitySource.device,
          platform: DevicePlatform.fitbit,
          externalId: '2',
        ),
        _a('typed', ActivitySource.manual, platform: hk, externalId: '3'),
        _a('fitflex', ActivitySource.fitflex, externalId: '4'),
        _a(
          'fake',
          ActivitySource.device,
          platform: hk,
          externalId: '5',
          sample: true,
        ),
      ];
      expect(genuineDeviceRecords(records, hk).map((a) => a.id), ['ok']);
    });

    test('each planned provider names its platform', () {
      expect(const AppleHealthProvider().platform, DevicePlatform.appleHealth);
      expect(
        const HealthConnectProvider().platform,
        DevicePlatform.healthConnect,
      );
      expect(
        const WearableProvider(
          vendor: 'garmin',
          platform: DevicePlatform.garmin,
        ).platform,
        DevicePlatform.garmin,
      );
    });
  });

  testWidgets('each activity row says where it came from', (tester) async {
    await tester.pumpWidget(
      _app(
        ListView(
          children: [
            for (final a in [
              _a(
                'dev',
                ActivitySource.device,
                platform: DevicePlatform.appleHealth,
                externalId: 'hk',
              ),
              _a(
                'watch',
                ActivitySource.device,
                platform: DevicePlatform.healthConnect,
                externalId: 'hc',
                deviceName: 'Pixel Watch',
              ),
              _a('ff', ActivitySource.fitflex),
              _a('man', ActivitySource.manual),
              _a('tr', ActivitySource.trainer),
              _a('gym', ActivitySource.gym),
              _a('mock', ActivitySource.device, sample: true),
            ])
              ActivityTimelineTile(activity: a),
          ],
        ),
      ),
    );
    String origin(String id) => [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(Key('activity-origin-$id')),
          matching: find.byType(Text),
        ),
      ))
        t.data!,
    ].join(' / ');
    expect(origin('dev'), 'Device / Apple Health');
    expect(origin('watch'), 'Device / Pixel Watch');
    expect(origin('ff'), 'FitFlex');
    expect(origin('man'), 'Manual');
    expect(origin('tr'), 'By trainer');
    expect(origin('gym'), 'By gym');
    expect(origin('mock'), 'Sample', reason: 'sample walks are never Device');
  });

  testWidgets('the data sources sheet explains all three', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDataOriginsSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('data-origins-sheet')), findsOneWidget);
    for (final t in ['Device', 'FitFlex', 'Manual']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.textContaining('never estimates'), findsOneWidget);
    expect(find.textContaining('nothing here is device data'), findsOneWidget);
  });
}
