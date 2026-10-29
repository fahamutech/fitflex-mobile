// The home band with a partner photo and logo plate (spec §40): plate
// geometry on phones and at 840+ (AC-P5), the 68px room above the eyebrow
// and the first control moving at most 68px (AC-P6), tones and high
// contrast (AC-P7, AC-P8), the plate left out of semantics (AC-P9), no
// change without a plate, and the band never swapping while on screen
// (AC-P3).
import 'dart:typed_data';

import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/partner_media/partner_hero_builder.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_flag.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_models.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_store.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/hero_images_fakes.dart';
import 'fixtures.dart';

Widget _app(
  Widget child, {
  Size size = const Size(390, 844),
  bool highContrast = false,
  double textScale = 1,
  String lang = 'en',
}) => FFLocaleScope(
  notifier: FFLocale()..set(Locale(lang)),
  child: MaterialApp(
    theme: buildTheme(),
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: size,
        highContrast: highContrast,
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: c!,
    ),
    home: Scaffold(
      body: ListView(padding: const EdgeInsets.all(24), children: [child]),
    ),
  ),
);

FFLogoPlate _plate({double aspect = 2, bool dark = false}) =>
    FFLogoPlate(image: MemoryImage(onePixelPng), aspect: aspect, dark: dark);

Widget _band({Widget? logo, FFHeroOwnPhoto? own}) => FFHeroBand(
  key: const Key('band'),
  photo: FFHeroPhoto.trainer,
  ownPhoto: own,
  logo: logo,
  clearPhoto: FFTokens.heroBandClearPhoto,
  maxHeightAt844: 469,
  eyebrow: 'Good morning, Asha',
  headlineLead: 'Train people.',
  headlineAccent: 'Get paid.',
  subline: 'Check in at a gym with your QR.',
  actions: [
    FFButton(key: const Key('first-control'), label: 'Scan', onPressed: () {}),
  ],
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugPhotoHeroUiOverride = true;
    debugPartnerMediaUiOverride = true;
  });
  tearDown(() {
    debugPhotoHeroUiOverride = null;
    debugPartnerMediaUiOverride = null;
    PartnerMediaStore.debugInstance = null;
  });

  Future<(double, double, double)> measure(
    WidgetTester tester, {
    Widget? logo,
    Size size = const Size(390, 844),
    double textScale = 1,
    String lang = 'en',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _band(logo: logo),
        size: size,
        textScale: textScale,
        lang: lang,
      ),
    );
    await tester.pump();
    final band = tester.getRect(find.byKey(const Key('band')));
    final eyebrow = tester.getRect(find.byKey(const Key('ff-hero-eyebrow')));
    final control = tester.getRect(find.byKey(const Key('first-control')));
    return (band.top, eyebrow.top - band.top, control.top);
  }

  group('phone plate (AC-P5, AC-P6)', () {
    for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932)]) {
      for (final lang in ['en', 'sw']) {
        for (final scale in [1.0, 1.3]) {
          testWidgets('$size $lang ${scale}x', (tester) async {
            final (_, gapNone, controlNone) = await measure(
              tester,
              size: size,
              lang: lang,
              textScale: scale,
            );
            final (bandTop, gap, control) = await measure(
              tester,
              logo: _plate(),
              size: size,
              lang: lang,
              textScale: scale,
            );
            expect(gap, greaterThanOrEqualTo(FFTokens.logoPlateReserve - 0.01));
            expect(control - controlNone, lessThanOrEqualTo(68.01));
            expect(control - controlNone, greaterThanOrEqualTo(-0.01));
            expect(gapNone, greaterThan(0));
            final plate = tester.getRect(
              find.byKey(const Key('ff-logo-plate')),
            );
            final bandRect = tester.getRect(find.byKey(const Key('band')));
            expect(plate.left - bandRect.left, 16);
            expect(plate.top - bandTop, 16);
            expect(plate.height, 40);
            expect(plate.width, lessThanOrEqualTo(120));
          });
        }
      }
    }

    testWidgets('no plate: the band is exactly as before', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_band()));
      final before = tester.getSize(find.byKey(const Key('band')));
      expect(find.byKey(const Key('ff-hero-plate')), findsNothing);
      expect(find.byKey(const Key('ff-hero-own-photo')), findsNothing);
      await tester.pumpWidget(_app(_band(logo: null, own: null)));
      expect(tester.getSize(find.byKey(const Key('band'))), before);
    });
  });

  testWidgets('840+: top-right 24px in, banner height unchanged', (
    tester,
  ) async {
    const size = Size(1280, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_band(), size: size));
    final without = tester.getRect(find.byKey(const Key('band')));
    await tester.pumpWidget(_app(_band(logo: _plate(aspect: 4)), size: size));
    final band = tester.getRect(find.byKey(const Key('band')));
    final plate = tester.getRect(find.byKey(const Key('ff-logo-plate')));
    expect(
      band.height,
      without.height,
      reason: 'the plate never grows the banner',
    );
    expect(band.height, greaterThanOrEqualTo(220));
    expect(band.right - plate.right, 24);
    expect(plate.top - band.top, 24);
    expect(plate.width, 120);
  });

  group('tones, high contrast, semantics', () {
    BoxDecoration deco(WidgetTester tester) =>
        tester
                .widget<Container>(find.byKey(const Key('ff-logo-plate')))
                .decoration!
            as BoxDecoration;

    testWidgets('light and dark plates (AC-P7)', (tester) async {
      await tester.pumpWidget(_app(_band(logo: _plate())));
      expect(deco(tester).color, FFTokens.logoPlateLight);
      await tester.pumpWidget(_app(_band(logo: _plate(dark: true))));
      expect(deco(tester).color, FFTokens.logoPlateDark);
      expect(
        (deco(tester).border! as Border).top.color,
        FFTokens.logoPlateDarkBorder,
      );
    });

    testWidgets('high contrast: no photo even with one; full dark edge '
        '(AC-P8)', (tester) async {
      final own = FFHeroOwnPhoto(id: 'p', provider: MemoryImage(onePixelPng));
      await tester.pumpWidget(
        _app(_band(logo: _plate(dark: true), own: own), highContrast: true),
      );
      expect(find.byKey(const Key('ff-hero-own-photo')), findsNothing);
      expect(find.byKey(const Key('ff-hero-photo')), findsNothing);
      expect(find.byKey(const Key('ff-logo-plate')), findsOneWidget);
      expect(
        (deco(tester).border! as Border).top.color,
        FFTokens.logoPlateDarkBorderStrong,
      );
      await tester.pumpWidget(_app(_band(logo: _plate()), highContrast: true));
      expect(deco(tester).border, isNull);
    });

    testWidgets('the partner photo leads, at its focal point', (tester) async {
      final own = FFHeroOwnPhoto(
        id: 'p',
        provider: MemoryImage(onePixelPng),
        focal: const Alignment(0.5, -0.25),
      );
      await tester.pumpWidget(_app(_band(own: own)));
      final img = tester.widget<Image>(
        find.byKey(const Key('ff-hero-own-photo')),
      );
      expect(img.alignment, const Alignment(0.5, -0.25));
    });

    testWidgets('the plate is not announced (AC-P9)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(_band(logo: _plate())));
      expect(
        find.descendant(
          of: find.byKey(const Key('ff-hero-plate')),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.label?.isNotEmpty ?? false),
          ),
        ),
        findsNothing,
      );
      expect(find.bySemanticsLabel(RegExp('Good morning')), findsOneWidget);
      handle.dispose();
    });
  });

  group('PartnerHeroBuilder: never swaps on screen (AC-P3, AC-P11)', () {
    late FakeFiles files;
    late PartnerMediaStore store;
    final subject = PartnerMediaSubject.trainer('u1');

    PartnerMediaOverview o({bool hero = true, String id = 'pmd_hero1'}) =>
        PartnerMediaOverview.tryParse(
          overview(hero: hero ? heroItem(id: id) : null),
        )!;

    Future<void> setUpStore(WidgetTester tester) async {
      files = FakeFiles();
      store = _OfflineStore(files);
      PartnerMediaStore.debugInstance = store;
    }

    Widget host({required bool visible}) => _app(
      PartnerHeroBuilder(
        subject: subject,
        visible: visible,
        builder: (context, m) =>
            Text('photo:${m?.photo?.id ?? 'bundled'}', key: const Key('shown')),
      ),
    );

    String shown(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('shown'))).data!;

    testWidgets('a photo saved while on screen shows only on the next view', (
      tester,
    ) async {
      await setUpStore(tester);
      await tester.pumpWidget(host(visible: true));
      expect(shown(tester), 'photo:bundled');
      await tester.runAsync(() => store.apply(subject, o()));
      await tester.pump();
      await tester.pumpWidget(host(visible: true));
      expect(shown(tester), 'photo:bundled', reason: 'no swap mid-view');
      await tester.pumpWidget(host(visible: false));
      await tester.pumpWidget(host(visible: true));
      expect(shown(tester), 'photo:pmd_hero1');
      // Removed or taken down: cleared, the bundled photo on the next view.
      await tester.runAsync(() => store.apply(subject, o(hero: false)));
      expect(files.names, isEmpty);
      await tester.pumpWidget(host(visible: false));
      await tester.pumpWidget(host(visible: true));
      expect(shown(tester), 'photo:bundled');
    });

    testWidgets('a gym switch reads that gym, never the other', (tester) async {
      await setUpStore(tester);
      final a = PartnerMediaSubject.gym('u1', 'gym_a');
      final b = PartnerMediaSubject.gym('u1', 'gym_b');
      await tester.runAsync(() => store.apply(a, o(id: 'pmd_a')));
      Widget gym(PartnerMediaSubject s) => _app(
        PartnerHeroBuilder(
          subject: s,
          builder: (context, m) => Text(
            'photo:${m?.photo?.id ?? 'bundled'}',
            key: const Key('shown'),
          ),
        ),
      );
      await tester.pumpWidget(gym(a));
      expect(shown(tester), 'photo:pmd_a');
      await tester.pumpWidget(gym(b));
      expect(shown(tester), 'photo:bundled');
      await tester.pumpWidget(gym(a));
      expect(shown(tester), 'photo:pmd_a');
    });

    testWidgets('flag off: no store, nothing asked', (tester) async {
      await setUpStore(tester);
      debugPartnerMediaUiOverride = false;
      await tester.runAsync(() => store.apply(subject, o()));
      await tester.pumpWidget(host(visible: true));
      expect(shown(tester), 'photo:bundled');
      expect(PartnerMediaStore.instance, isNull);
    });
  });
}

/// A store whose downloads come from a fixed answer and whose refreshes
/// fail (offline), so only [PartnerMediaStore.apply] changes it.
class _OfflineStore extends PartnerMediaStore {
  _OfflineStore(FakeFiles files)
    : super(
        api: _FileApi(),
        files: files,
        device: FakeDevice(),
        decodeTest: (b) async => true,
      );

  @override
  Future<PartnerMediaOverview?> refresh(
    PartnerMediaSubject subject, {
    bool force = false,
    Duration? every,
  }) async => null;
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
