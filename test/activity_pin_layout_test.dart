// Layout fixes that apply with PHOTO_HERO_UI off and on (owner, 2026-10-19):
// - choosing an Activity section scrolls only the segmented row, never the
//   page around it;
// - Activity in Swahili at 1.3x text on a 360px phone does not overflow;
// - PIN keypad keys stay at least 44x44 and fully on screen on short phones.

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/pin_flows.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_api.dart';

// ── harness ─────────────────────────────────────────────────────────────

Future<void> _host(
  WidgetTester tester,
  Widget page, {
  String lang = 'en',
  double textScale = 1,
  Size size = const Size(390, 844),
  bool settle = true,
  bool scaffold = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient(baseUrl: 'http://fixtures.local');
  final auth = AuthState(client);
  await auth.signIn('token', {
    'id': 'u1',
    'userType': 'member',
    'approvalStatus': 'approved',
    'onboardingCompleted': true,
  });
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => scaffold ? Scaffold(body: page) : page,
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    AppScope(
      api: client,
      auth: auth,
      child: ThemeScope(
        notifier: ThemeNotifier(),
        child: FFLocaleScope(
          notifier: FFLocale()..set(Locale(lang)),
          child: MaterialApp.router(
            routerConfig: router,
            theme: buildTheme(),
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: c!,
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await _pumpFew(tester);
  }
}

Future<void> _pumpFew(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Runs [body] once with the flag off and once with it on.
void bothFlags(
  String name,
  Future<void> Function(WidgetTester tester, RecordingApi api) body,
) {
  for (final flag in [false, true]) {
    testWidgets('${flag ? 'flag on' : 'flag off'}: $name', (tester) async {
      SharedPreferences.setMockInitialValues({});
      debugPhotoHeroUiOverride = flag;
      addTearDown(() => debugPhotoHeroUiOverride = null);
      final api = RecordingApi();
      await api.run(() async {
        await body(tester, api);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    });
  }
}

/// Collects Flutter errors (overflows) raised while [run] runs.
Future<List<FlutterErrorDetails>> _errorsDuring(
  Future<void> Function() run,
) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await run();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

String _tr(String lang, String key) => FFLocale.textOf(lang, key)!;

Finder _key(String k) => find.byKey(Key(k));

// ── member data ─────────────────────────────────────────────────────────

final _now = DateTime(2026, 9, 23, 20);

MemberData _activityData() => MemberData()
  ..me = MemberMeResponse.fromJson({
    'user': {
      'id': 'm1',
      'displayName': 'Amina Juma',
      'onboardingCompleted': true,
    },
    'visitsUsed': 3,
    'visitCap': 18,
  })
  ..activities = [
    for (var d = 0; d < 6; d++)
      Activity(
        id: 'a$d',
        userId: 'u1',
        type: d.isEven ? ActivityType.walking : ActivityType.running,
        source: ActivitySource.device,
        startedAt: DateTime(2026, 9, 23 - d, 7),
        steps: 4000 + d * 1234,
        distanceKm: 3.2 + d,
        durationMinutes: 30 + d,
        activeMinutes: 30 + d,
      ),
  ]
  ..activityLoaded = true;

Widget _activity({String section = 'overview'}) => MemberDataScope(
  data: _activityData(),
  child: MemberActivityTab(now: _now, initialSection: section),
);

const _sections = ['overview', 'workouts', 'challenges', 'progress'];

void main() {
  // ── 1. Segmented control never scrolls the page ─────────────────────────

  group('Activity sections: the page does not jump', () {
    for (final lang in ['en', 'sw']) {
      for (final scale in [1.0, 1.3]) {
        bothFlags('$lang ${scale}x 360x640: each section keeps the page '
            'offset', (tester, api) async {
          await _host(
            tester,
            _activity(),
            lang: lang,
            textScale: scale,
            size: const Size(360, 640),
            settle: false,
          );
          final page = tester.state<ScrollableState>(
            find
                .descendant(
                  of: _key('activity-scroll'),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          for (final id in [..._sections.reversed, ..._sections]) {
            final before = page.position.pixels;
            // Some segments sit outside the row at this size, so choose
            // through the control's callback (what a tap calls).
            tester.widget<FFSegmented>(_key('activity-sections')).onChanged(id);
            await _pumpFew(tester);
            expect(
              page.position.pixels,
              before,
              reason: 'selecting $id moved the page',
            );
          }
        });
      }
    }

    bothFlags('starting on Progress does not scroll the page', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        _activity(section: 'progress'),
        lang: 'sw',
        textScale: 1.3,
        size: const Size(360, 640),
        settle: false,
      );
      final page = tester.state<ScrollableState>(
        find
            .descendant(
              of: _key('activity-scroll'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(page.position.pixels, 0);
    });

    testWidgets('the segmented row still scrolls its chosen segment into '
        'view, and only the row', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final value = ValueNotifier('a');
      addTearDown(value.dispose);
      final outer = ScrollController();
      addTearDown(outer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: c!,
          ),
          home: Scaffold(
            body: ListView(
              controller: outer,
              children: [
                const SizedBox(height: 900),
                ValueListenableBuilder<String>(
                  valueListenable: value,
                  builder: (context, v, _) => FFSegmented(
                    value: v,
                    options: const [
                      ('a', 'Mazoezi'),
                      ('b', 'Changamoto'),
                      ('c', 'Maendeleo'),
                      ('d', 'Takwimu'),
                    ],
                    onChanged: (n) => value.value = n,
                  ),
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      );
      outer.jumpTo(700);
      await tester.pumpAndSettle();
      final row = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(FFSegmented),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(row.position.maxScrollExtent, greaterThan(0));
      value.value = 'd';
      await tester.pumpAndSettle();
      expect(row.position.pixels, greaterThan(0));
      expect(outer.offset, 700);
      // The chosen segment is inside the row's visible part.
      final seg = tester.getRect(find.text('Takwimu'));
      final rowRect = tester.getRect(find.byType(FFSegmented));
      expect(seg.right, lessThanOrEqualTo(rowRect.right + 0.5));
      expect(seg.left, greaterThanOrEqualTo(rowRect.left - 0.5));
    });
  });

  // ── 2. Swahili at 1.3x on 360px ───────────────────────────────────────

  group('Activity in Swahili at 1.3x on 360px: no overflow', () {
    for (final height in [640.0, 800.0]) {
      for (final id in _sections) {
        bothFlags('360x${height.toInt()} $id', (tester, api) async {
          final errors = await _errorsDuring(() async {
            await _host(
              tester,
              _activity(section: id),
              lang: 'sw',
              textScale: 1.3,
              size: Size(360, height),
              settle: false,
            );
            // Bring every part of the section through layout.
            final page = find
                .descendant(
                  of: _key('activity-scroll'),
                  matching: find.byType(Scrollable),
                )
                .first;
            for (var i = 0; i < 30; i++) {
              final s = tester.state<ScrollableState>(page);
              if (s.position.pixels >= s.position.maxScrollExtent) break;
              await tester.drag(page, const Offset(0, -300));
              await _pumpFew(tester);
            }
          });
          expect(
            errors,
            isEmpty,
            reason: errors.map((e) => e.toString()).join('\n---\n'),
          );
        });
      }
    }
  });

  // ── 3. PIN keypad keys ────────────────────────────────────────────────

  group('PIN keypad: 44x44 keys, all on screen', () {
    const sizes = [Size(360, 640), Size(390, 700), Size(390, 844)];

    void expectKeys(WidgetTester tester, Size size) {
      for (final label in [for (var d = 0; d <= 9; d++) '$d', 'OK']) {
        final text = find.descendant(
          of: find.byType(CustomKeypad),
          matching: find.text(label),
        );
        expect(text, findsOneWidget, reason: label);
        final key = find
            .ancestor(of: text, matching: find.byType(Material))
            .first;
        final r = tester.getRect(key);
        expect(r.height, greaterThanOrEqualTo(44), reason: '$label $r');
        expect(r.width, greaterThanOrEqualTo(44), reason: '$label $r');
        expect(r.top, greaterThanOrEqualTo(0), reason: '$label $r');
        expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$label $r');
        expect(r.left, greaterThanOrEqualTo(0), reason: '$label $r');
        expect(r.right, lessThanOrEqualTo(size.width), reason: '$label $r');
        // Tappable where it is drawn.
        expect(
          tester
              .hitTestOnBinding(r.center)
              .path
              .any((e) => e.target == tester.renderObject(key)),
          isTrue,
          reason: '$label not hittable',
        );
      }
      final del = find.bySemanticsLabel(_tr('en', 'a11y.delete'));
      expect(del, findsOneWidget);
      final r = tester.getRect(del);
      expect(r.height, greaterThanOrEqualTo(44));
      expect(r.bottom, lessThanOrEqualTo(size.height));
    }

    for (final size in sizes) {
      for (final scale in [1.0, 1.3]) {
        for (final mode in EmailAuthMode.values) {
          bothFlags('PIN entry ${mode.name} '
              '${size.width.toInt()}x${size.height.toInt()} ${scale}x', (
            tester,
            api,
          ) async {
            final handle = tester.ensureSemantics();
            final errors = await _errorsDuring(() async {
              await _host(
                tester,
                EmailAuthScreen(
                  initialEmail: 'qa@example.test',
                  initialMode: mode,
                ),
                textScale: scale,
                size: size,
                scaffold: false,
              );
            });
            expect(errors, isEmpty, reason: errors.join('\n'));
            expectKeys(tester, size);
            handle.dispose();
          });
        }

        bothFlags('PIN setup choose step '
            '${size.width.toInt()}x${size.height.toInt()} ${scale}x', (
          tester,
          api,
        ) async {
          final handle = tester.ensureSemantics();
          final errors = await _errorsDuring(() async {
            await _host(
              tester,
              const PinSetupScreen(
                setupToken: 't',
                contact: '0712345678',
                needsCode: false,
                needsNewPin: true,
                currentPin: '12345',
              ),
              textScale: scale,
              size: size,
              scaffold: false,
            );
          });
          expect(errors, isEmpty, reason: errors.join('\n'));
          expectKeys(tester, size);
          handle.dispose();
        });
      }
    }

    test('the keypad asks for at least 44px keys', () {
      expect(CustomKeypad.minKeyExtent, greaterThanOrEqualTo(44));
      expect(
        CustomKeypad.minHeight,
        4 * (CustomKeypad.minKeyExtent + 2 * FFTokens.spacingSm),
      );
    });
  });
}
