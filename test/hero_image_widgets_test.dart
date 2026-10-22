// Heroes and footers with admin-published photos (HERO_IMAGES_REMOTE):
// bundled first, saved photos only on the next build, never mid-view.

import 'package:fitflexmobile/shared/components/ff_photo_footer.dart';
import 'package:fitflexmobile/shared/components/ff_photo_hero.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_flag.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_store.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/photo_footer_flag.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hero_images_fakes.dart';

/// The provider under any ResizeImage wrapper.
ImageProvider _inner(ImageProvider p) =>
    p is ResizeImage ? _inner(p.imageProvider) : p;

ImageProvider _shown(WidgetTester tester, String key) =>
    _inner(tester.widget<Image>(find.byKey(Key(key)).first).image);

Widget _app(Widget child, {bool highContrast = false}) => FFLocaleScope(
  notifier: FFLocale(),
  child: MaterialApp(
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(highContrast: highContrast, disableAnimations: true),
      child: c!,
    ),
    home: Scaffold(body: child),
  ),
);

Widget _hero({Key? key}) => SizedBox(
  height: 300,
  child: FFPhotoHero(
    key: key,
    photo: FFHeroPhoto.signIn,
    variant: FFHeroVariant.compact,
    headlineLead: 'Every step',
    headlineAccent: 'counts.',
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugPhotoHeroUiOverride = true;
    debugHeroImagesRemoteOverride = true;
  });
  tearDown(() {
    debugPhotoHeroUiOverride = null;
    debugHeroImagesRemoteOverride = null;
    debugPhotoFooterUiOverride = null;
    HeroImageStore.debugInstance = null;
  });

  FakeServer serverWithSignIn() => FakeServer()
    ..manifest = manifestJson(3, {
      'signIn': [entryJson('s1', sourceId: 'hero_S')],
    });

  testWidgets('bundled photo on the first frame, before anything loads', (
    tester,
  ) async {
    final server = serverWithSignIn();
    HeroImageStore.debugInstance = server.store();
    await tester.pumpWidget(_app(_hero()));
    expect(_shown(tester, 'ff-hero-photo'), isA<AssetImage>());
    expect(
      (_shown(tester, 'ff-hero-photo') as AssetImage).assetName,
      FFHeroPhoto.signIn.asset,
    );
  });

  testWidgets('a photo saved mid-view shows only on the next build', (
    tester,
  ) async {
    final server = serverWithSignIn();
    final store = server.store();
    HeroImageStore.debugInstance = store;
    var tick = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Column(
              children: [
                Text('tick $tick'),
                Expanded(child: _hero(key: const ValueKey('first'))),
              ],
            );
          },
        ),
      ),
    );
    expect(_shown(tester, 'ff-hero-photo'), isA<AssetImage>());

    await tester.runAsync(store.onFirstFrame);
    expect(store.readyIds, {'s1'});
    rebuild(() => tick++);
    await tester.pump();
    expect(find.text('tick 1'), findsOneWidget);
    expect(
      _shown(tester, 'ff-hero-photo'),
      isA<AssetImage>(),
      reason: 'never swapped while the screen is open',
    );

    // The next time the screen is built: the saved photo, its focal point.
    await tester.pumpWidget(_app(_hero(key: const ValueKey('second'))));
    expect(_shown(tester, 'ff-hero-photo'), isA<MemoryImage>());
    final img = tester.widget<Image>(
      find.byKey(const Key('ff-hero-photo')).first,
    );
    expect(img.alignment, const Alignment(-0.3, 0.2));
  });

  testWidgets('high contrast: no photo, saved or bundled', (tester) async {
    final server = serverWithSignIn();
    final store = server.store();
    HeroImageStore.debugInstance = store;
    await tester.runAsync(store.onFirstFrame);
    await tester.pumpWidget(_app(_hero(), highContrast: true));
    expect(find.byKey(const Key('ff-hero-photo')), findsNothing);
  });

  testWidgets('flag off: bundled photos and zero requests', (tester) async {
    debugHeroImagesRemoteOverride = false;
    final server = serverWithSignIn();
    HeroImageStore.debugInstance = server.store();
    expect(HeroImageStore.startIfEnabled(apiBase: fakeApiBase), isNull);
    await tester.pumpWidget(_app(_hero()));
    await tester.pump(const Duration(seconds: 1));
    expect(_shown(tester, 'ff-hero-photo'), isA<AssetImage>());
    expect(server.requests, isEmpty);
  });

  testWidgets('footer shows a saved pool photo of another scene', (
    tester,
  ) async {
    debugPhotoFooterUiOverride = true;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final server = FakeServer()
      ..manifest = manifestJson(3, {
        'gyms': [entryJson('g1', sourceId: 'hero_A')],
        'footerPool': [
          entryJson('f1', sourceId: 'hero_A'),
          entryJson('f2', sourceId: 'hero_B'),
        ],
      })
      ..fileBody['f1'] = okBytes(4001)
      ..fileBody['f2'] = okBytes(4002);
    final store = server.store(footer: true);
    await tester.runAsync(() async {
      await store.setSession(signedIn: true, role: 'member');
      await store.onFirstFrame();
    });
    HeroImageStore.debugInstance = store;
    await tester.pumpWidget(
      _app(
        CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: SizedBox(
                height: 300,
                child: FFPhotoHero(
                  photo: FFHeroPhoto.gyms,
                  variant: FFHeroVariant.band,
                  headlineLead: 'Find your',
                  headlineAccent: 'gym.',
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 900)),
            FFPhotoFooter.sliver(pageKey: 'member.gyms', top: FFHeroPhoto.gyms),
          ],
        ),
      ),
    );
    expect(_shown(tester, 'ff-hero-photo'), isA<MemoryImage>());
    expect(store.topSourceIdFor(FFHeroPhoto.gyms), 'hero_A');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pump();
    expect(_shown(tester, 'photo-footer-photo'), isA<MemoryImage>());
    final footerBytes =
        (_shown(tester, 'photo-footer-photo') as MemoryImage).bytes;
    expect(footerBytes.length, 4002, reason: 'f2 (hero_B), not hero_A');
  });
}
