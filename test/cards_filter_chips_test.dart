// Gym and trainer cards fit every phone size and text scale (no RenderFlex
// overflow, names may take two lines, prices stay whole), and the Gyms and
// Trainers filter chips are real buttons (F-11): a 48px target, reachable
// with Tab, toggled with Space or Enter, announced as a selectable button.
// For everyone, with the photo flags off or on.

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_card.dart';
import 'package:fitflexmobile/screens/member/widgets/trainer_card.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/photo_footer_flag.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_api.dart';

// ── fixtures: the long, awkward cases ────────────────────────────────────

const _promo = {
  'id': 'pr1',
  'type': 'promoted',
  'label': 'Promoted',
  'commercial': true,
};

Map<String, dynamic> _gym(
  String id,
  String name, {
  bool verified = false,
  bool promoted = false,
}) => {
  'id': id,
  'name': name,
  'tier': 'premium',
  'location': 'Plot 12, Haile Selassie Road, Masaki, Kinondoni, Dar es Salaam',
  'perVisitRate': 5000,
  'ratePerMonth': 350000,
  'commissionRate': 10,
  'status': 'active',
  'isVerified': verified,
  'amenities': <String>[],
  if (promoted) 'promotion': _promo,
};

Map<String, dynamic> _trainer(
  String id,
  String name, {
  bool verified = false,
  bool promoted = false,
}) => {
  'id': id,
  'displayName': name,
  'specialties': ['Weights', 'Cardio', 'Boxing', 'Yoga'],
  'hourlyRateTzs': 1250000,
  'status': 'active',
  'isVerified': verified,
  if (promoted) 'promotion': _promo,
};

List<Gym> _gyms() => [
  Gym.fromJson(
    _gym('g1', 'Mikocheni Strength and Conditioning Centre', promoted: true),
  ),
  Gym.fromJson(_gym('g2', 'Masaki Fit', verified: true)),
  Gym.fromJson(_gym('g3', 'Kariakoo Boxing Club and Fitness Hall')),
];

List<TrainerProfile> _trainers() => [
  TrainerProfile.fromJson(
    _trainer('t1', 'Neema Abdallah Mwakyusa-Kilimanjaro', promoted: true),
  ),
  TrainerProfile.fromJson(_trainer('t2', 'Juma Ali', verified: true)),
  TrainerProfile.fromJson(_trainer('t3', 'Rehema Mwanaisha Salim')),
];

MemberData _data() => MemberData()
  ..gyms = _gyms()
  ..trainers = _trainers()
  ..gymsLoaded = true
  ..trainersLoaded = true;

// ── harness ──────────────────────────────────────────────────────────────

Widget _app(Widget body, {required String lang, required double scale}) =>
    FFLocaleScope(
      notifier: FFLocale()..set(Locale(lang)),
      child: MaterialApp(
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
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: c!,
        ),
        home: Scaffold(body: body),
      ),
    );

Future<void> _page(
  WidgetTester tester,
  Widget page, {
  String lang = 'en',
  double scale = 1,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient(baseUrl: 'http://fixtures.local');
  final auth = AuthState(client);
  await auth.signIn('token', {
    'id': 'm1',
    'userType': 'member',
    'approvalStatus': 'approved',
    'onboardingCompleted': true,
    'displayName': 'Amina Juma',
  });
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: MemberDataScope(data: _data(), child: page),
        ),
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
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: c!,
            ),
          ),
        ),
      ),
    ),
  );
  await _frames(tester);
}

/// A few frames past the fades. Not pumpAndSettle: the Gyms tab may keep a
/// location spinner running.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// A test with a fresh fake backend and both photo flags set to [flags].
void cardTest(
  String name,
  Future<void> Function(WidgetTester tester) body, {
  required bool flags,
}) {
  testWidgets('$name (photo flags ${flags ? 'on' : 'off'})', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugPhotoHeroUiOverride = flags;
    debugPhotoFooterUiOverride = flags;
    addTearDown(() {
      debugPhotoHeroUiOverride = null;
      debugPhotoFooterUiOverride = null;
    });
    final api = RecordingApi();
    await api.run(() async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

Finder _key(String k) => find.byKey(Key(k));

const _sizes = [Size(360, 640), Size(390, 844)];
const _langs = ['en', 'sw'];
const _scales = [1.0, 1.3];

String _combo(Size s, String lang, double scale) =>
    '${s.width.toInt()}x${s.height.toInt()} $lang ${scale}x';

/// Every price is laid out in full: never cut to "…" nor clipped to a line.
void _expectPricesWhole(WidgetTester tester) {
  final price = formatCurrency(1250000);
  final prices = find.textContaining(price);
  expect(prices, findsWidgets);
  for (final e in prices.evaluate()) {
    final p = e.renderObject;
    if (p is RenderParagraph) {
      expect(p.didExceedMaxLines, isFalse, reason: 'price cut: $price');
    }
  }
}

// ── chip helpers ─────────────────────────────────────────────────────────

const _gymChips = [
  'gym-filter-all',
  'gym-filter-saved',
  'gym-filter-nearest',
  'gym-filter-standard',
  'gym-filter-midtier',
  'gym-filter-premium',
  'gym-filter-more',
];

const _trainerChips = [
  'trainer-filter-all',
  'trainer-filter-Weights',
  'trainer-filter-Cardio',
  'trainer-filter-Yoga',
  'trainer-filter-Boxing',
];

/// The key of the chip that has keyboard focus now, if any.
String? _focusedChip() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  final chip = ctx.widget is FFFilterChip
      ? ctx.widget as FFFilterChip
      : ctx.findAncestorWidgetOfExactType<FFFilterChip>();
  final key = chip?.key;
  return key is ValueKey<String> ? key.value : null;
}

/// Presses Tab until every chip in [chips] has had focus (or gives up).
Future<Set<String>> _tabThrough(WidgetTester tester, List<String> chips) async {
  final seen = <String>{};
  for (var i = 0; i < 40 && !seen.containsAll(chips); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final k = _focusedChip();
    if (k != null) seen.add(k);
  }
  return seen;
}

/// Tabs until [chip] has focus.
Future<void> _tabTo(WidgetTester tester, String chip) async {
  for (var i = 0; i < 40 && _focusedChip() != chip; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(_focusedChip(), chip);
}

bool _selected(WidgetTester tester, String chip) =>
    tester.widget<FFFilterChip>(_key(chip)).selected;

void main() {
  setUpAll(loadAppFonts);

  // ── 1. cards: no overflow anywhere ──────────────────────────────────────

  group('cards in a grid and a list: no overflow', () {
    for (final size in _sizes) {
      for (final lang in _langs) {
        for (final scale in _scales) {
          testWidgets(
            'grid, featured strip and list ${_combo(size, lang, scale)}',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              final gyms = _gyms();
              final trainers = _trainers();
              final errors = await captureFlutterErrors(() async {
                await tester.pumpWidget(
                  _app(
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = ffCardGridColumns(context, c.maxWidth);
                        return CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: FFFeaturedStrip(
                                title: 'Featured',
                                count: gyms.length,
                                fitContent: true,
                                itemBuilder: (_, i) =>
                                    GymGridCard(gym: gyms[i]),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: FFFeaturedStrip(
                                title: 'Featured',
                                count: trainers.length,
                                fitContent: true,
                                itemBuilder: (_, i) =>
                                    TrainerGridCard(trainer: trainers[i]),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.all(16),
                              sliver: SliverFFRowGrid(
                                columns: cols,
                                itemCount: gyms.length,
                                itemBuilder: (_, i) => GymGridCard(
                                  key: Key('g-grid-${gyms[i].id}'),
                                  gym: gyms[i],
                                  distanceKm: 12.4,
                                  imageAspectRatio: cols == 1 ? 16 / 9 : 4 / 3,
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.all(16),
                              sliver: SliverFFRowGrid(
                                columns: cols,
                                itemCount: trainers.length,
                                itemBuilder: (_, i) => TrainerGridCard(
                                  key: Key('t-grid-${trainers[i].id}'),
                                  trainer: trainers[i],
                                  imageAspectRatio: cols == 1 ? 4 / 3 : 1,
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.all(16),
                              sliver: SliverList.list(
                                children: [
                                  for (final g in gyms)
                                    GymCard(gym: g, distanceKm: 3.2),
                                  for (final t in trainers)
                                    TrainerCard(trainer: t),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    lang: lang,
                    scale: scale,
                  ),
                );
                await tester.pump();
                // Scroll the whole page so every card is laid out.
                final scroll = tester.state<ScrollableState>(
                  find.byType(Scrollable).first,
                );
                while (scroll.position.pixels <
                    scroll.position.maxScrollExtent) {
                  scroll.position.jumpTo(
                    (scroll.position.pixels + size.height / 2).clamp(
                      0,
                      scroll.position.maxScrollExtent,
                    ),
                  );
                  await tester.pump();
                }
              });
              expect(errors, isEmpty, reason: errors.join('\n'));
            },
          );
        }
      }
    }

    testWidgets('names take up to two lines; Not verified is never cut', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = _trainers().first;
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 160, child: TrainerGridCard(trainer: t)),
          ),
          lang: 'sw',
          scale: 1.3,
        ),
      );
      final name = tester.widget<RichText>(
        find.descendant(
          of: _key('trainer-grid-name-t1'),
          matching: find.byType(RichText),
        ),
      );
      expect(name.maxLines, 2);
      final label = tester.widget<Text>(
        find.descendant(
          of: _key('trainer-grid-unverified-t1'),
          matching: find.byType(Text),
        ),
      );
      expect(label.maxLines, 2);
      _expectPricesWhole(tester);
    });
  });

  for (final flags in [false, true]) {
    group('Gyms and Trainers pages: no overflow', () {
      for (final size in _sizes) {
        for (final lang in _langs) {
          for (final scale in _scales) {
            for (final entry in {
              'gyms': () => const MemberGymsTab(),
              'trainers': () => const MemberTrainersTab(),
            }.entries) {
              cardTest('${entry.key} ${_combo(size, lang, scale)}', (
                tester,
              ) async {
                final errors = await captureFlutterErrors(
                  () => _page(
                    tester,
                    entry.value(),
                    lang: lang,
                    scale: scale,
                    size: size,
                  ),
                );
                expect(errors, isEmpty, reason: errors.join('\n'));
                if (entry.key == 'trainers') {
                  expect(_key('trainer-card-t1'), findsOneWidget);
                  _expectPricesWhole(tester);
                } else {
                  expect(_key('gym-card-g1'), findsOneWidget);
                }
              }, flags: flags);
            }
          }
        }
      }
    });

    // ── 2. filter chips (F-11) ────────────────────────────────────────────

    group('filter chips', () {
      cardTest('every Gyms and Trainers chip is at least 48x48', (
        tester,
      ) async {
        await _page(tester, const MemberGymsTab(), lang: 'sw', scale: 1.3);
        for (final k in _gymChips) {
          final s = tester.getSize(_key(k));
          expect(s.height, greaterThanOrEqualTo(48), reason: k);
          expect(s.width, greaterThanOrEqualTo(48), reason: k);
        }
        // The panel's price chips too.
        await tester.ensureVisible(_key('gym-filter-more'));
        await tester.tap(_key('gym-filter-more'));
        await _frames(tester);
        for (final p in ['any', '<60k', '350k+']) {
          final s = tester.getSize(_key('gym-price-filter-$p'));
          expect(s.height, greaterThanOrEqualTo(48), reason: p);
          expect(s.width, greaterThanOrEqualTo(48), reason: p);
        }

        await _page(tester, const MemberTrainersTab());
        for (final k in _trainerChips) {
          final s = tester.getSize(_key(k));
          expect(s.height, greaterThanOrEqualTo(48), reason: k);
          expect(s.width, greaterThanOrEqualTo(48), reason: k);
        }
      }, flags: flags);

      cardTest('Tab reaches every Gyms chip, then every Trainers chip', (
        tester,
      ) async {
        await _page(tester, const MemberGymsTab());
        expect(await _tabThrough(tester, _gymChips), containsAll(_gymChips));
        await _page(tester, const MemberTrainersTab());
        expect(
          await _tabThrough(tester, _trainerChips),
          containsAll(_trainerChips),
        );
      }, flags: flags);

      cardTest('Enter and Space select a chip; focus ring is visible', (
        tester,
      ) async {
        await _page(tester, const MemberGymsTab());
        expect(_selected(tester, 'gym-filter-all'), isTrue);

        await _tabTo(tester, 'gym-filter-premium');
        final ring = tester.widget<DecoratedBox>(
          find.descendant(
            of: _key('gym-filter-premium'),
            matching: _key('ff-filter-chip-focus-ring'),
          ),
        );
        final border = (ring.decoration as BoxDecoration).border as Border;
        expect(border.top.color, ffFocusRingLight);
        expect(border.top.width, 2);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _frames(tester);
        expect(_selected(tester, 'gym-filter-premium'), isTrue);
        expect(_selected(tester, 'gym-filter-all'), isFalse);

        // "Other filters" opens and closes its panel from the keyboard.
        await _tabTo(tester, 'gym-filter-more');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _frames(tester);
        expect(_key('gym-filter-verified'), findsOneWidget);
        expect(_selected(tester, 'gym-filter-more'), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await _frames(tester);
        expect(_key('gym-filter-verified'), findsNothing);

        await _page(tester, const MemberTrainersTab());
        await _tabTo(tester, 'trainer-filter-Yoga');
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await _frames(tester);
        expect(_selected(tester, 'trainer-filter-Yoga'), isTrue);
        expect(_selected(tester, 'trainer-filter-all'), isFalse);
      }, flags: flags);

      cardTest('chips are announced as selectable buttons with a label', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _page(tester, const MemberGymsTab(), lang: 'sw');
        expect(
          tester.getSemantics(_key('gym-filter-all')),
          isSemantics(
            label: FFLocale.textOf('sw', 'member.all'),
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            isFocusable: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(_key('gym-filter-premium')),
          isSemantics(
            isButton: true,
            hasSelectedState: true,
            isSelected: false,
            isFocusable: true,
            hasTapAction: true,
          ),
        );

        await _page(tester, const MemberTrainersTab(), lang: 'sw');
        expect(
          tester.getSemantics(_key('trainer-filter-Weights')),
          isSemantics(
            label: 'Uzito',
            isButton: true,
            hasSelectedState: true,
            isSelected: false,
            isFocusable: true,
            hasTapAction: true,
          ),
        );
        handle.dispose();
      }, flags: flags);
    });
  }
}
