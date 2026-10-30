// Design-QA and UAT fixes for partner photos (mobile#250 follow-up): the
// home refreshes when a page over it closes but never after a dialog
// (UAT 1), the first answer of a session fades in once (UAT 2), the red
// Remove label (QA M1), one labelled node for the disabled button (QA M2),
// a readable takedown alert (UAT a11y), the wide preview at its home height
// (QA M3), loading with no plate (QA L1), the dashed empty plate (QA L2),
// the Swahili title (QA L3), the plate waiting for its photo (QA L4), the
// URL following the gym (UAT 12) and the generic no-access text (UAT 13).

import 'package:fitflexmobile/screens/partner/partner_media_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/partner_media/partner_hero_builder.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_flag.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_image_check.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_models.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_store.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/hero_images_fakes.dart';
import '../support/recording_api.dart';
import 'fixtures.dart';

const _trainer = {'id': 'u1', 'userType': 'trainer', 'displayName': 'Asha'};
const _owner = {'id': 'o1', 'userType': 'gym_operator'};

/// A store whose server answers come from [answers], one per refresh.
class _ScriptedStore extends PartnerMediaStore {
  _ScriptedStore(this.files)
    : super(
        api: _FileApi(),
        files: files,
        device: FakeDevice(),
        decodeTest: (b) async => true,
      );

  final FakeFiles files;
  final List<PartnerMediaOverview?> answers = [];
  int asked = 0;

  @override
  Future<PartnerMediaOverview?> refresh(
    PartnerMediaSubject subject, {
    bool force = false,
    Duration? every,
  }) async {
    asked++;
    final o = answers.isEmpty ? null : answers.removeAt(0);
    if (o != null) await apply(subject, o);
    return o;
  }
}

class _FileApi extends ApiClient {
  _FileApi() : super(baseUrl: fakeApiBase);

  @override
  Future<({int status, Uint8List? bytes, String? etag})?> partnerMediaFile(
    Uri uri, {
    required int maxBytes,
    String? etag,
    Duration timeout = const Duration(seconds: 20),
  }) async => (status: 200, bytes: onePixelPng, etag: null);
}

PartnerMediaOverview _o(String? heroId) => PartnerMediaOverview.tryParse(
  overview(hero: heroId == null ? null : heroItem(id: heroId)),
)!;

/// The trainer home's banner height on a 1280 x 800 window.
Future<double> _homeBannerHeight(WidgetTester tester) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    FFLocaleScope(
      notifier: FFLocale(),
      child: MaterialApp(
        theme: buildTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  FFHeroBand(
                    key: key,
                    photo: FFHeroPhoto.trainer,
                    clearPhoto: FFTokens.heroBandClearPhoto,
                    maxHeightAt844: 469,
                    eyebrow: 'Good morning, Asha',
                    headlineLead: FFLocale.textOf('en', 'hero.trainer.lead'),
                    headlineAccent: FFLocale.textOf(
                      'en',
                      'hero.trainer.accent',
                    ),
                    subline: FFLocale.textOf('en', 'checkin.body'),
                    actions: [
                      FFButton(
                        label: FFLocale.textOf('en', 'checkin.scan')!,
                        icon: Icons.qr_code_scanner,
                        onPressed: () {},
                      ),
                      FFButton(
                        label: FFLocale.textOf('en', 'checkin.showQr')!,
                        icon: Icons.qr_code_2,
                        variant: FFButtonVariant.onPhoto,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byKey(key)).height;
}

Text _shownText(String id) => Text('photo:$id', key: const Key('shown'));

String _shown(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('shown'))).data!;

void main() {
  // Real fonts, so heights match a device (the 220px banner).
  setUpAll(loadAppFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugPhotoHeroUiOverride = true;
    debugPartnerMediaUiOverride = true;
  });
  tearDown(() {
    debugPhotoHeroUiOverride = null;
    debugPartnerMediaUiOverride = null;
    PartnerMediaStore.debugInstance = null;
    PartnerRouteWatch.root = null;
    debugPartnerMediaPicker = null;
  });

  group('home refresh rules (UAT 1, UAT 2)', () {
    final subject = PartnerMediaSubject.gym('o1', 'gym_a');

    Widget home() => PartnerHeroBuilder(
      subject: subject,
      builder: (context, m) => _shownText(m?.photo?.id ?? 'bundled'),
    );

    testWidgets('a page pushed over the home (in a shell) closing shows the '
        'new photo; a dialog closing does not', (tester) async {
      final store = _ScriptedStore(FakeFiles());
      await tester.runAsync(() => store.apply(subject, _o('pmd_old')));
      PartnerMediaStore.debugInstance = store;
      final watch = PartnerRouteWatch.root = PartnerRouteWatch();
      final router = GoRouter(
        initialLocation: '/owner/home',
        observers: [watch],
        routes: [
          ShellRoute(
            builder: (_, _, child) => Scaffold(body: child),
            routes: [GoRoute(path: '/owner/home', builder: (_, _) => home())],
          ),
          GoRoute(
            path: '/owner/profile',
            builder: (_, _) => const Scaffold(body: Text('PROFILE')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(_shown(tester), 'photo:pmd_old');

      // A dialog over the home: closing it never swaps the band.
      await tester.runAsync(() => store.apply(subject, _o('pmd_new')));
      showDialog<void>(
        context: tester.element(find.byKey(const Key('shown'))),
        builder: (_) => const Text('DIALOG'),
      );
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('DIALOG'))).pop();
      await tester.pumpAndSettle();
      expect(_shown(tester), 'photo:pmd_old');

      // Profile → back: the home comes into view again.
      router.push('/owner/profile');
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(_shown(tester), 'photo:pmd_new');
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('taken down while away: Back re-checks and fades to the '
        'bundled photo; a replacement still waits (post-fix UAT)', (
      tester,
    ) async {
      final store = _ScriptedStore(FakeFiles());
      await tester.runAsync(() => store.apply(subject, _o('pmd_live')));
      PartnerMediaStore.debugInstance = store;
      final watch = PartnerRouteWatch.root = PartnerRouteWatch();
      final router = GoRouter(
        initialLocation: '/owner/home',
        observers: [watch],
        routes: [
          ShellRoute(
            builder: (_, _, child) => Scaffold(body: child),
            routes: [GoRoute(path: '/owner/home', builder: (_, _) => home())],
          ),
          GoRoute(
            path: '/owner/scan',
            builder: (_, _) => const Scaffold(body: Text('SCAN')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await settle(tester);
      expect(_shown(tester), 'photo:pmd_live');

      // Replaced by the partner elsewhere: Back keeps the photo on screen
      // (no new photo mid-view); the next view shows the new one.
      store.answers.add(_o('pmd_new'));
      router.push('/owner/scan');
      await tester.pumpAndSettle();
      router.pop();
      await settle(tester);
      expect(_shown(tester), 'photo:pmd_live');

      // FitFlex took it down: the next Back re-checks and lets it go.
      store.answers.add(_o(null));
      router.push('/owner/scan');
      await tester.pumpAndSettle();
      router.pop();
      await settle(tester);
      expect(_shown(tester), 'photo:bundled');
    });

    testWidgets('app resume re-checks; a takedown fades out, nothing is '
        'added', (tester) async {
      final store = _ScriptedStore(FakeFiles());
      await tester.runAsync(() => store.apply(subject, _o('pmd_live')));
      PartnerMediaStore.debugInstance = store;
      await tester.pumpWidget(MaterialApp(home: home()));
      await settle(tester);
      expect(_shown(tester), 'photo:pmd_live');
      store.answers.add(_o(null));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(_shown(tester), 'photo:bundled');
      // A photo that arrives on a later resume waits for the next view.
      store.answers.add(_o('pmd_again'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(_shown(tester), 'photo:bundled');
    });

    testWidgets('first load of the session: the answer shows once; later '
        'saves wait for the next view', (tester) async {
      final store = _ScriptedStore(FakeFiles())..answers.add(_o('pmd_first'));
      PartnerMediaStore.debugInstance = store;
      await tester.pumpWidget(MaterialApp(home: home()));
      expect(_shown(tester), 'photo:bundled');
      await tester.runAsync(() async {
        // The post-frame refresh, then its apply.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(_shown(tester), 'photo:pmd_first');
      expect(store.asked, 1);
      // On screen now: a newer save does not swap it.
      await tester.runAsync(() => store.apply(subject, _o('pmd_second')));
      await tester.pumpWidget(MaterialApp(home: home()));
      expect(_shown(tester), 'photo:pmd_first');
    });
  });

  group('settings page', () {
    Future<PageHost> open(
      WidgetTester tester,
      RecordingApi api, {
      String side = 'trainer',
      Map<String, dynamic> user = _trainer,
      String lang = 'en',
      double textScale = 1,
      Size size = const Size(390, 3200),
      bool settle = true,
    }) => pumpPage(
      tester,
      api,
      PartnerMediaPage(side: side),
      user: user,
      lang: lang,
      textScale: textScale,
      size: size,
      keepRequests: true,
      settle: settle,
    );

    for (final dark in [false, true]) {
      testWidgets('Remove is red (${dark ? 'dark' : 'light'}) (QA M1)', (
        tester,
      ) async {
        final theme = dark ? buildDarkTheme() : buildTheme();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: FFButton(
                label: 'Remove',
                variant: FFButtonVariant.ghost,
                foregroundColor: theme.colorScheme.error,
                onPressed: () {},
              ),
            ),
          ),
        );
        final style = DefaultTextStyle.of(tester.element(find.text('Remove')));
        expect(style.style.color, theme.colorScheme.error);
      });
    }

    apiTest('the page uses that red on Remove', (tester, api) async {
      api.on('GET /partner/media', overview(hero: heroItem()));
      await open(tester, api);
      final remove = find.byKey(const Key('partner-media-hero-remove'));
      final ctx = tester.element(
        find.descendant(of: remove, matching: find.byType(Text)).first,
      );
      expect(
        DefaultTextStyle.of(ctx).style.color,
        Theme.of(ctx).colorScheme.error,
      );
    });

    apiTest('takedown alert is one readable node (UAT a11y)', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      api.on(
        'GET /partner/media',
        overview(
          heroDown: heroItem(
            status: 'taken_down',
            takedown: {'reason': 'rights', 'note': 'Ask the photographer'},
          ),
        ),
      );
      final h = await open(tester, api);
      final node = tester.getSemantics(
        find.byKey(const Key('partner-media-hero-taken-down-semantics')),
      );
      expect(node.label, contains(h.tr('partnerMedia.reason.rights')));
      expect(node.label, contains('Ask the photographer'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    apiTest('the disabled button is one labelled tap target (QA M2)', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      debugPartnerMediaPicker = (_) async => PickedPartnerImage(
        bytes: onePixelPng,
        filename: 'p.png',
        type: 'image/png',
        width: 1600,
        height: 1000,
      );
      api.on('GET /partner/media', overview());
      await open(tester, api);
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-hero-upload')),
      );
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-source-gallery')),
      );
      await tester.ensureVisible(find.byKey(const Key('partner-media-use')));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    apiTest('840+: the preview is the wide home banner, 220 tall (QA M3)', (
      tester,
      api,
    ) async {
      api.on('GET /partner/media', overview());
      await open(tester, api, size: const Size(1280, 3200));
      expect(
        find.byKey(const Key('partner-media-preview-wide-fit')),
        findsOneWidget,
      );
      final band = find.descendant(
        of: find.byKey(const Key('partner-media-preview')),
        matching: find.byType(FFPhotoHero),
      );
      final preview = tester.getSize(band).height;
      expect(
        tester.getSize(find.byKey(const Key('partner-media-preview'))).width,
        1232,
      );
      // The same band as the 1280-wide home draws it (220 at least; text
      // never wraps it taller than the home), not a 672-wide column.
      final homeBand = await _homeBannerHeight(tester);
      expect(preview, homeBand);
      expect(preview, greaterThanOrEqualTo(220));
      expect(preview, lessThan(240));
    });

    for (final side in ['trainer', 'vendor']) {
      apiTest('loading ($side): the bundled photo, no plate (QA L1)', (
        tester,
        api,
      ) async {
        final hold = api.hold('GET /partner/media');
        api.on('GET /partner/media', overview(type: side, logo: logoItem()));
        await open(
          tester,
          api,
          side: side,
          user: {'id': 'u1', 'userType': side},
          settle: false,
        );
        await tester.pump();
        final preview = find.byKey(const Key('partner-media-preview'));
        expect(
          find.descendant(
            of: preview,
            matching: find.byKey(const Key('ff-hero-photo')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.byKey(const Key('ff-hero-plate')),
          ),
          findsNothing,
        );
        hold.complete();
        await tester.pumpAndSettle();
      });
    }

    apiTest('empty logo: a dashed 40 x 40 outline (QA L2)', (
      tester,
      api,
    ) async {
      api.on('GET /partner/media', overview());
      await open(tester, api);
      final paint = tester.widget<CustomPaint>(
        find.byKey(const Key('partner-media-logo-empty-plate')),
      );
      expect(paint.painter, isA<DashedPlatePainter>());
      expect(
        tester.getSize(find.byKey(const Key('partner-media-logo-empty-plate'))),
        const Size(40, 40),
      );
    });

    for (final scale in [1.0, 1.3]) {
      apiTest('Swahili title keeps off the bar edges at ${scale}x (QA L3)', (
        tester,
        api,
      ) async {
        api.on('GET /partner/media', overview());
        await open(
          tester,
          api,
          lang: 'sw',
          textScale: scale,
          size: const Size(360, 800),
        );
        expect(tester.takeException(), isNull);
        final title = tester.getRect(
          find.byKey(const Key('partner-media-title')),
        );
        final back = tester.getRect(
          find.byKey(const Key('partner-media-back')),
        );
        expect(title.left, greaterThanOrEqualTo(back.right));
        expect(title.right, lessThanOrEqualTo(360 - FFTokens.spacingMd));
        final bar = tester.getRect(find.byType(AppBar));
        expect(title.top, greaterThanOrEqualTo(bar.top));
        expect(title.bottom, lessThanOrEqualTo(bar.bottom));
      });
    }

    apiTest('switching gym keeps the address in step (UAT 12)', (
      tester,
      api,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          null,
        ),
      );
      api.on('GET /owner/gyms', [
        {'id': 'gym_a', 'name': 'Arena'},
        {'id': 'gym_b', 'name': 'Bahari'},
      ]);
      api.on('GET /partner/media', overview(type: 'gym', id: 'gym_a'));
      await open(tester, api, side: 'gym', user: _owner);
      await tapVisible(tester, find.byKey(const Key('partner-media-gym')));
      await tapVisible(tester, find.text('Bahari'));
      final update = calls.lastWhere(
        (c) => c.method == 'routeInformationUpdated',
      );
      expect(
        (update.arguments as Map)['uri'].toString(),
        '/owner/brand-media?gymId=gym_b',
      );
      expect((update.arguments as Map)['replace'], isTrue);
    });

    apiTest('a member on /trainer/brand-media: generic text (UAT 13)', (
      tester,
      api,
    ) async {
      final h = await open(
        tester,
        api,
        user: const {'id': 'm1', 'userType': 'member'},
      );
      expect(find.text(h.tr('partnerMedia.restricted')), findsOneWidget);
      expect(find.text(h.tr('partnerMedia.restrictedGym')), findsNothing);
      expect(FFLocale.textOf('sw', 'partnerMedia.restricted'), isNotNull);
    });
  });

  testWidgets('focus ring at Top left stays inside the photo (post-fix 21)', (
    tester,
  ) async {
    for (final pos in [Alignment.topLeft, Alignment.bottomRight]) {
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 342,
                child: FFFocalPointPicker(
                  image: MemoryImage(onePixelPng),
                  aspect: 1.5,
                  value: pos,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final photo = tester.getRect(find.byKey(const Key('ff-focal-image')));
      final ring = tester.getRect(find.byKey(const Key('ff-focal-ring')));
      // 2px outline outside the 28px ring still inside the photo.
      expect(ring.inflate(2).left, greaterThanOrEqualTo(photo.left));
      expect(ring.inflate(2).top, greaterThanOrEqualTo(photo.top));
      expect(ring.inflate(2).right, lessThanOrEqualTo(photo.right));
      expect(ring.inflate(2).bottom, lessThanOrEqualTo(photo.bottom));
    }
  });

  group('plate waits for its photo (QA L4)', () {
    Widget band({bool highContrast = false}) => MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(highContrast: highContrast, disableAnimations: true),
        child: c!,
      ),
      home: Scaffold(
        body: ListView(
          children: [
            FFHeroBand(
              photo: FFHeroPhoto.trainer,
              ownPhoto: FFHeroOwnPhoto(
                id: 'p',
                provider: MemoryImage(onePixelPng),
              ),
              logo: FFLogoPlate(
                image: MemoryImage(onePixelPng),
                aspect: 1,
                dark: false,
              ),
              eyebrow: 'Hi',
              headlineLead: 'Lead',
            ),
          ],
        ),
      ),
    );

    double gate(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(find.byKey(const Key('ff-hero-plate-gate')))
        .opacity;

    testWidgets('hidden until the photo shows; bundled photo underneath', (
      tester,
    ) async {
      await tester.pumpWidget(band());
      await tester.pump();
      expect(gate(tester), 0);
      expect(find.byKey(const Key('ff-hero-photo')), findsOneWidget);
      expect(find.byKey(const Key('ff-hero-own-photo')), findsOneWidget);
    });

    testWidgets('high contrast: no photo, so the plate shows', (tester) async {
      await tester.pumpWidget(band(highContrast: true));
      await tester.pump();
      await tester.pump();
      expect(gate(tester), 1);
    });
  });
}
