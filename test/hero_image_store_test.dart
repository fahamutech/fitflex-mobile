// Admin-published app photos (HERO_IMAGES_REMOTE): the photo-hero increment
// plan, slice 6, and design spec §36–§38. The store reads GET
// /app/hero-images (fitflex-functions functions/hero-images.mjs) and keeps
// the photos on the phone.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fitflexmobile/shared/components/ff_photo_footer.dart';
import 'package:fitflexmobile/shared/components/ff_photo_hero.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_files_io.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_flag.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_store.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_url.dart';
import 'package:fitflexmobile/shared/hero_images/hero_manifest.dart';
import 'package:fitflexmobile/shared/hero_images/hero_slots.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hero_images_fakes.dart';

const _base = 'https://api.fitflex.test';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugPhotoHeroUiOverride = true;
    debugHeroImagesRemoteOverride = true;
  });
  tearDown(() {
    debugPhotoHeroUiOverride = null;
    debugHeroImagesRemoteOverride = null;
    HeroImageStore.debugInstance = null;
  });

  group('photo address (mirrors the portal heroAssetUrl)', () {
    test('a root-relative /storage path resolves against API_BASE only', () {
      expect(
        heroAssetUri('/storage/bafy123/hero_a-2x.webp', _base).toString(),
        '$_base/storage/bafy123/hero_a-2x.webp',
      );
      expect(
        heroAssetUri('/storage/c/f.webp', 'https://h.test/api/').toString(),
        'https://h.test/api/storage/c/f.webp',
      );
    });

    test('rejects absolute, other hosts, .., percent tricks and the rest', () {
      for (final bad in <Object?>[
        'https://evil.test/storage/a/b.webp',
        'http://api.fitflex.test/storage/a/b.webp',
        '//evil.test/storage/a/b.webp',
        '/storage/../a/b.webp',
        '/storage/a/..',
        '/storage/a/..b.webp',
        '/storage/./b.webp',
        '/storage/a/.',
        '/storage/%2e%2e/b.webp',
        '/storage/a/%2e%2e',
        '/storage/a/b%2fc.webp',
        '/storage/a/b.webp?x=1',
        '/storage/a/b.webp#x',
        '/storage/a/b/c.webp',
        '/storage/a',
        '/other/a/b.webp',
        ' /storage/a/b.webp',
        '/storage/a/b.webp\n',
        'storage/a/b.webp',
        '/storage/a@evil.test/b.webp',
        '/storage/a\\b/c.webp',
        '',
        null,
        42,
      ]) {
        expect(heroAssetUri(bad, _base), isNull, reason: '$bad');
      }
    });

    test('a bad API base gives nothing', () {
      expect(heroAssetUri('/storage/a/b.webp', 'ftp://x.test'), isNull);
      expect(heroAssetUri('/storage/a/b.webp', 'not a url'), isNull);
    });
  });

  group('manifest', () {
    test('bigint versions as strings, bad entries and unknown slots drop', () {
      final m = HeroManifest.tryParse(
        {
          'version': '12',
          'slots': {
            'gyms': [
              entryJson('g1', bytes: 1000, focal: {'x': 3, 'y': -0.5}),
              {...entryJson('g2'), 'url': 'https://evil.test/storage/a/b'},
              {...entryJson('g3'), 'id': '../x'},
            ],
            'portalLogin': [entryJson('p1')],
            'notASlot': [entryJson('n1')],
          },
        },
        _base,
        etag: null,
        knownSlots: kMobileHeroSlots,
      )!;
      expect(m.version, 12);
      expect(m.etag, '"hp_12"', reason: 'the contract tag when unreadable');
      expect(m.slots.keys, ['gyms']);
      expect(m.slots['gyms']!.single.id, 'g1');
      expect(m.slots['gyms']!.single.focal, const Alignment(1, -0.5));
    });

    test('slot ids match the backend registry (hero-slots.mjs)', () {
      // fitflex-functions src/shared/hero-slots.mjs, surface 'mobile'.
      const backend = {
        'language', 'signIn', 'signUp', 'role', 'pin', 'homeStart', //
        'homePass', 'profile', 'upgrade', 'activityToday',
        'activityTraining', 'activityChallenges', 'activityProgress', 'gyms',
        'trainers', 'shop', 'trainer', 'vendor', 'owner', 'footerPool',
      };
      expect(kMobileHeroSlots, backend);
      expect(heroSlotOf.keys.toSet(), FFHeroPhoto.values.toSet());
      for (final p in FFHeroPhoto.values) {
        if (!p.name.startsWith('footer')) expect(heroSlotOf[p], p.name);
      }
    });

    test('rotation is FNV-1a of date|slot (stable, not String.hashCode)', () {
      final day = DateTime(2026, 10, 20, 23, 59);
      expect(heroRotationIndex(day, 'gyms', 3), fnv1a32('2026-10-20|gyms') % 3);
      expect(fnv1a32('2026-10-20|gyms'), fnv1a32('2026-10-20|gyms'));
      // Known FNV-1a 32-bit vector.
      expect(fnv1a32('a'), 0xe40c292c);
    });
  });

  group('flag', () {
    test('off: no store, so no request is ever made', () async {
      debugHeroImagesRemoteOverride = false;
      expect(HeroImageStore.startIfEnabled(apiBase: _base), isNull);
      expect(HeroImageStore.instance, isNull);
    });

    test('needs PHOTO_HERO_UI too', () {
      debugPhotoHeroUiOverride = false;
      debugHeroImagesRemoteOverride = true;
      expect(heroImagesRemote, isFalse);
      expect(HeroImageStore.startIfEnabled(apiBase: _base), isNull);
    });

    test('a store set while the flag is off is never used', () {
      final server = FakeServer();
      HeroImageStore.debugInstance = server.store();
      debugHeroImagesRemoteOverride = false;
      expect(HeroImageStore.instance, isNull);
      expect(server.requests, isEmpty);
    });
  });

  group('list fetch', () {
    test('ETag stored and sent; 304 keeps the photos', () async {
      final server = FakeServer()
        ..manifest = manifestJson(5, {
          'language': [entryJson('l1')],
        });
      var store = server.store();
      await store.onFirstFrame();
      expect(server.manifestRequests.single.headers['if-none-match'], isNull);
      expect(store.readyIds, {'l1'});

      // A new launch: the saved tag goes out, the server answers 304.
      server.clock = server.clock.add(const Duration(hours: 1));
      store = server.store();
      await store.onFirstFrame();
      expect(server.manifestRequests.last.headers['if-none-match'], '"hp_5"');
      expect(server.lastManifestStatus, 304);
      expect(store.manifest.version, 5);
      expect(store.readyIds, {'l1'}, reason: 'saved file decoded again');
      expect(server.fileRequests, hasLength(1), reason: 'not downloaded twice');
    });

    test('resume checks again only after 6 hours', () async {
      final server = FakeServer()..manifest = manifestJson(5, {});
      final store = server.store();
      await store.onFirstFrame();
      server.clock = server.clock.add(const Duration(hours: 5));
      await store.onResume();
      expect(server.manifestRequests, hasLength(1));
      server.clock = server.clock.add(const Duration(hours: 2));
      await store.onResume();
      expect(server.manifestRequests, hasLength(2));
    });

    test('5 s timeout, then the saved state stays', () async {
      final server = FakeServer()..hangManifest = true;
      final store = server.store();
      await store.onFirstFrame(); // waits out the 5 s timeout
      expect(store.manifest.isEmpty, isTrue);
      expect(store.readyIds, isEmpty);
    });

    test('version 0 purges every saved photo', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'signIn': [entryJson('s1')],
          'language': [entryJson('l1')],
        });
      final store = server.store();
      await store.onFirstFrame();
      expect(store.readyIds, {'s1', 'l1'});
      expect(server.files.names, hasLength(2));

      server.manifest = {'version': 0, 'slots': {}};
      server.clock = server.clock.add(const Duration(hours: 7));
      await store.onResume();
      expect(store.readyIds, isEmpty);
      expect(server.files.names, isEmpty);
      expect(store.resolveTop(FFHeroPhoto.signIn), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('heroImages.v1.index'), isNull);
    });

    test('a photo no longer published (unpublish) is deleted', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'signIn': [entryJson('s1')],
          'language': [entryJson('l1')],
        });
      final store = server.store();
      await store.onFirstFrame();
      server.manifest = manifestJson(8, {
        'language': [entryJson('l1')],
      });
      server.clock = server.clock.add(const Duration(hours: 7));
      await store.onResume();
      expect(store.readyIds, {'l1'});
      expect(server.files.names, ['l1.img']);
    });

    test('a server error or junk keeps what is saved', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('l1')],
        });
      final store = server.store();
      await store.onFirstFrame();
      server.manifestStatus = 503;
      server.clock = server.clock.add(const Duration(hours: 7));
      await store.onResume();
      expect(store.readyIds, {'l1'});
      server.manifestStatus = 200;
      server.manifestRaw = 'not json';
      server.clock = server.clock.add(const Duration(hours: 7));
      await store.onResume();
      expect(store.readyIds, {'l1'});
    });

    test('no sign-in token is sent, to the list or the files', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('l1')],
        });
      await server.store().onFirstFrame();
      expect(server.requests, hasLength(2));
      for (final r in server.requests) {
        expect(
          r.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(r.url.host, 'api.fitflex.test');
      }
    });
  });

  group('downloads', () {
    test('declared size over 200 KB: never requested', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('big', bytes: 200 * 1024 + 1)],
        });
      final store = server.store();
      await store.onFirstFrame();
      expect(server.fileRequests, isEmpty);
      expect(store.resolveTop(FFHeroPhoto.language), isNull);
    });

    test('actual size over 200 KB: reading stops, nothing saved', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('liar', bytes: 1000)],
        })
        ..fileBody['liar'] = okBytes(300 * 1024)
        ..sendLength = false;
      final store = server.store();
      await store.onFirstFrame();
      expect(server.fileRequests, hasLength(1));
      expect(server.bytesStreamed['liar']!, lessThan(300 * 1024));
      expect(store.readyIds, isEmpty);
      expect(server.files.names, isEmpty);
      expect(store.resolveTop(FFHeroPhoto.language), isNull);
    });

    test('Content-Length over 200 KB: refused before reading', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('liar', bytes: 1000)],
        })
        ..fileBody['liar'] = okBytes(250 * 1024);
      final store = server.store();
      await store.onFirstFrame();
      expect(store.readyIds, isEmpty);
      expect(server.files.names, isEmpty);
    });

    test('a corrupt file is deleted and the bundled photo stays', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('bad')],
        })
        ..fileBody['bad'] = utf8.encode('not an image');
      final store = server.store();
      await store.onFirstFrame();
      expect(store.readyIds, isEmpty);
      expect(server.files.names, isEmpty);
      expect(store.resolveTop(FFHeroPhoto.language), isNull);
      // Not retried (and paid for) again today.
      server.clock = server.clock.add(const Duration(hours: 7));
      await store.onResume();
      expect(server.fileRequests, hasLength(1));
    });

    test('a write failure (full disk) falls back and stops', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('l1')],
          'signIn': [entryJson('s1')],
        });
      server.files.failWrites = true;
      final store = server.store();
      await store.onFirstFrame();
      expect(store.readyIds, isEmpty);
      expect(server.fileRequests, hasLength(1));
    });

    test('at most 1.5 MB a day; the rest comes the next day', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          for (final s in kPreSignInSlots)
            s: [
              for (var i = 0; i < 3; i++) entryJson('$s$i', bytes: 150 * 1024),
            ],
        });
      final store = server.store();
      await store.onFirstFrame();
      expect(store.bytesToday, lessThanOrEqualTo(1536 * 1024));
      expect(store.readyIds, hasLength(10)); // 10 × 150 KB ≤ 1.5 MB < 11
      // Today's pick of every slot came first.
      for (final s in kPreSignInSlots) {
        final i = heroRotationIndex(server.clock, s, 3);
        expect(store.readyIds, contains('$s$i'));
      }
      server.clock = server.clock.add(const Duration(days: 1));
      await store.onResume();
      expect(store.readyIds, hasLength(15));
    });

    test('cache stays under 4 MB, least recently used goes first', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          for (final s in [
            ...kPreSignInSlots,
            'homeStart',
            'homePass',
            'gyms',
            'trainers',
            'shop',
            'profile',
          ])
            s: [
              for (var i = 0; i < 3; i++) entryJson('$s$i', bytes: 190 * 1024),
            ],
        });
      final store = server.store();
      await store.setSession(signedIn: true, role: 'member');
      await store.onFirstFrame();
      final dayOne = store.readyIds;
      expect(dayOne, hasLength(8)); // 8 × 190 KB ≤ 1.5 MB
      // Used today: kept although it was downloaded first.
      final kept = store.resolveTop(FFHeroPhoto.homeStart)!.entryId;
      for (var d = 0; d < 3; d++) {
        server.clock = server.clock.add(const Duration(days: 1));
        // Touch the kept one again each day so it stays most recent.
        store.resolveTop(FFHeroPhoto.homeStart);
        await store.onResume();
      }
      expect(store.savedBytes, lessThanOrEqualTo(4 * 1024 * 1024));
      expect(server.files.totalBytes, store.savedBytes);
      expect(store.readyIds, hasLength(21)); // 21 × 190 KB ≤ 4 MB < 22
      expect(store.readyIds, contains(kept));
      expect(dayOne.difference(store.readyIds), isNotEmpty);
    });

    test('Data Saver or Low Data Mode: no downloads', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('l1')],
        })
        ..device.reduced = true;
      final store = server.store();
      await store.onFirstFrame();
      expect(server.fileRequests, isEmpty);
      expect(store.resolveTop(FFHeroPhoto.language), isNull);
    });

    test('little free storage: no downloads', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('l1')],
        })
        ..device.free = 10 * 1024 * 1024;
      await server.store().onFirstFrame();
      expect(server.fileRequests, isEmpty);
    });

    test('only the role\'s slots plus the pre-sign-in screens', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('l1')],
          'gyms': [entryJson('g1')],
          'trainer': [entryJson('t1')],
          'owner': [entryJson('o1')],
          'footerPool': [entryJson('f1')],
        });
      final store = server.store(footer: true);
      await store.onFirstFrame();
      expect(store.readyIds, {'l1'}, reason: 'signed out');
      await store.setSession(signedIn: true, role: 'trainer');
      expect(store.readyIds, {'l1', 't1', 'f1'});
      expect(
        server.fileRequests.map((r) => r.url.path),
        isNot(contains(endsWith('g1-2x.webp'))),
      );
    });

    test('footer pool only when the footer is on', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'gyms': [entryJson('g1')],
          'footerPool': [entryJson('f1')],
        });
      final store = server.store(footer: false);
      await store.setSession(signedIn: true, role: 'member');
      await store.onFirstFrame();
      expect(store.readyIds, {'g1'});
    });

    test('saved files go through a temporary file, then a rename', () async {
      final dir = await Directory.systemTemp.createTemp('hero_images_');
      addTearDown(() => dir.delete(recursive: true));
      final files = IoHeroFileStore.at(dir);
      expect(await files.write('a.img', [1, 2, 3]), isTrue);
      final names = dir.listSync().map((e) => e.uri.pathSegments.last);
      expect(names, ['a.img'], reason: 'no .part left behind');
      expect(await files.read('a.img'), [1, 2, 3]);
      File('${dir.path}/b.img.part').writeAsBytesSync([9]);
      expect(await files.list(), ['a.img']);
      expect(() => files.provider('../x.img'), throwsArgumentError);
      await files.deleteAll();
      expect(dir.listSync(), isEmpty);
    });
  });

  group('choosing', () {
    test('the day\'s photo per slot; bundled until it is ready', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'signIn': [entryJson('a'), entryJson('b'), entryJson('c')],
        });
      final store = server.store();
      expect(store.resolveTop(FFHeroPhoto.signIn), isNull);
      await store.onFirstFrame();
      final i = heroRotationIndex(server.clock, 'signIn', 3);
      final r = store.resolveTop(FFHeroPhoto.signIn)!;
      expect(r.entryId, ['a', 'b', 'c'][i]);
      expect(r.focal, const Alignment(-0.3, 0.2));
    });

    test('footer never shows the top photo\'s scene (remote data)', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'gyms': [entryJson('g1', sourceId: 'hero_A')],
          'footerPool': [
            entryJson('f1', sourceId: 'hero_A'),
            entryJson('f2', sourceId: 'hero_B'),
            entryJson('f3', sourceId: 'hero_C'),
          ],
        });
      final store = server.store(footer: true);
      await store.setSession(signedIn: true, role: 'member');
      await store.onFirstFrame();
      HeroImageStore.debugInstance = store;
      for (var d = 0; d < 20; d++) {
        server.clock = server.clock.add(const Duration(days: 1));
        final top = store.resolveTop(FFHeroPhoto.gyms);
        for (final page in footerPagePhotos.keys) {
          final f = store.resolveFooter(page, top: FFHeroPhoto.gyms);
          expect(
            f?.sourceId,
            isNot(top?.sourceId ?? FFHeroPhoto.gyms.sourceId),
          );
          final choice = resolveFooterPhoto(page, top: FFHeroPhoto.gyms);
          final shown = choice.remote?.sourceId ?? choice.bundled.sourceId;
          expect(shown, isNot(top?.sourceId ?? FFHeroPhoto.gyms.sourceId));
        }
      }
    });

    test(
      'bundled footer avoids a remote top photo of the same scene',
      () async {
        // An admin photo that is the same scene as the bundled studio footer.
        final server = FakeServer()
          ..manifest = manifestJson(7, {
            'gyms': [
              entryJson('g1', sourceId: FFHeroPhoto.footerStudio.sourceId),
            ],
          });
        final store = server.store();
        await store.setSession(signedIn: true, role: 'member');
        await store.onFirstFrame();
        HeroImageStore.debugInstance = store;
        expect(footerPagePhotos['member.gyms'], FFHeroPhoto.footerStudio);
        store.resolveTop(FFHeroPhoto.gyms);
        final choice = resolveFooterPhoto('member.gyms', top: FFHeroPhoto.gyms);
        expect(choice.remote, isNull);
        expect(
          choice.bundled.sourceId,
          isNot(FFHeroPhoto.footerStudio.sourceId),
        );
      },
    );

    test('all footer photos match the top: bundled footer', () async {
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'gyms': [entryJson('g1', sourceId: 'hero_A')],
          'footerPool': [entryJson('f1', sourceId: 'hero_A')],
        });
      final store = server.store(footer: true);
      await store.setSession(signedIn: true, role: 'member');
      await store.onFirstFrame();
      store.resolveTop(FFHeroPhoto.gyms);
      expect(store.resolveFooter('member.gyms', top: FFHeroPhoto.gyms), isNull);
    });
  });

  group('web', () {
    test('no disk; used only after it decodes in this session', () async {
      final server = FakeServer(web: true)
        ..manifest = manifestJson(7, {
          'language': [entryJson('ok')],
          'signIn': [entryJson('broken')],
          'signUp': [entryJson('huge', bytes: 300 * 1024)],
        });
      server.precacheFails.add('broken');
      final store = server.store();
      await store.onFirstFrame();
      expect(store.readyIds, {'ok'});
      expect(server.precached, hasLength(2), reason: 'oversize never loaded');
      final r = store.resolveTop(FFHeroPhoto.language)!;
      expect(r.provider, isA<NetworkImage>());
      expect(
        (r.provider as NetworkImage).url,
        '$_base/storage/bafy/ok-2x.webp',
      );
      expect(server.fileRequests, isEmpty, reason: 'the browser loads it');
      expect(server.manifestRequests.single.headers['if-none-match'], isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty, reason: 'nothing kept on the device');
      // A new session starts from nothing again.
      final next = server.store();
      expect(next.resolveTop(FFHeroPhoto.language), isNull);
    });
  });

  group('decode test', () {
    testWidgets('real image ok; corrupt and oversized pictures refused', (
      tester,
    ) async {
      await tester.runAsync(() async {
        expect(await heroDecodeTest(await pngBytes(40, 30)), isTrue);
        expect(await heroDecodeTest(utf8.encode('garbage')), isFalse);
        expect(await heroDecodeTest(await pngBytes(2500, 8)), isFalse);
      });
    });
  });
}

Future<List<int>> pngBytes(int w, int h) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xff1f7a3a),
  );
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}
