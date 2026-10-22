// Admin-published app photos (HERO_IMAGES_REMOTE): the photo-hero increment
// plan, slice 6, and design spec §36–§38. The store reads GET
// /app/hero-images (fitflex-functions functions/hero-images.mjs) and keeps
// the photos on the phone.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
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
      expect(
        server.cancelled,
        contains('$_base/storage/bafy/liar-2x.webp'),
        reason: 'the body is let go, not left open',
      );
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
        // An admin photo that is the same scene as the bundled Gyms footer.
        final server = FakeServer()
          ..manifest = manifestJson(7, {
            'gyms': [
              entryJson('g1', sourceId: FFHeroPhoto.footerNightHall.sourceId),
            ],
          });
        final store = server.store();
        await store.setSession(signedIn: true, role: 'member');
        await store.onFirstFrame();
        HeroImageStore.debugInstance = store;
        expect(footerPagePhotos['member.gyms'], FFHeroPhoto.footerNightHall);
        store.resolveTop(FFHeroPhoto.gyms);
        final choice = resolveFooterPhoto('member.gyms', top: FFHeroPhoto.gyms);
        expect(choice.remote, isNull);
        expect(
          choice.bundled.sourceId,
          isNot(FFHeroPhoto.footerNightHall.sourceId),
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
    test('no disk; fetched with the same caps, used once it decodes', () async {
      final server = FakeServer(web: true)
        ..manifest = manifestJson(7, {
          'language': [entryJson('ok')],
          'signIn': [entryJson('broken')],
          'signUp': [entryJson('huge', bytes: 300 * 1024)],
        })
        ..fileBody['broken'] = utf8.encode('garbage');
      final store = server.store();
      await store.onFirstFrame();
      expect(store.readyIds, {'ok'});
      expect(
        server.fileRequests.map((r) => r.url.pathSegments.last),
        unorderedEquals(['ok-2x.webp', 'broken-2x.webp']),
        reason: 'oversize never loaded',
      );
      expect(store.bytesToday, 4000 + 7, reason: 'actual bytes counted');
      final r = store.resolveTop(FFHeroPhoto.language)!;
      expect(r.provider, isA<MemoryImage>());
      expect((r.provider as MemoryImage).bytes, okBytes(4000));
      expect(server.manifestRequests.single.headers['if-none-match'], isNull);
      expect(
        server.manifestRequests.single.followRedirects,
        isFalse,
        reason: 'the list is never redirected',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty, reason: 'nothing kept on the device');
      // A new session starts from nothing again.
      final next = server.store();
      expect(next.resolveTop(FFHeroPhoto.language), isNull);
    });

    test(
      'the browser follows the 307; an allowed final host is used',
      () async {
        final server = FakeServer(web: true)
          ..manifest = manifestJson(7, {
            'language': [entryJson('l1')],
          });
        server.redirects['$_base/storage/bafy/l1-2x.webp'] =
            'https://gw.test/storage/bafy/l1-2x.webp';
        final store = server.store(allowedHosts: {'gw.test'});
        await store.onFirstFrame();
        expect(store.readyIds, {'l1'});
        expect(server.fileRequests.first.followRedirects, isTrue);
        expect(server.requests.last.url.host, 'gw.test');
      },
    );

    test('a final host not allowed: the bytes are never used', () async {
      final server = FakeServer(web: true)
        ..manifest = manifestJson(7, {
          'language': [entryJson('l1')],
        });
      server.redirects['$_base/storage/bafy/l1-2x.webp'] =
          'https://evil.test/storage/bafy/l1-2x.webp';
      final store = server.store(allowedHosts: {'gw.test'});
      await store.onFirstFrame();
      expect(store.readyIds, isEmpty);
      expect(
        server.cancelled,
        contains('https://evil.test/storage/bafy/l1-2x.webp'),
      );
      expect(store.resolveTop(FFHeroPhoto.language), isNull);
    });

    test('the web photo is sized to its box like a phone one', () {
      final memory = MemoryImage(Uint8List.fromList(okBytes(10)));
      final p = heroRemoteImageProvider(
        RemoteHeroImage(
          entryId: 'w1',
          sourceId: 'hero_w1',
          focal: Alignment.center,
          aspect: 1.5,
          provider: memory,
        ),
        const Size(400, 300),
        2,
      );
      expect(p, isA<ResizeImage>());
      // 300 x 1.5 = 450 logical px wide at 2x = 900, up to the 128 step.
      expect((p as ResizeImage).width, 1024);
      expect(p.imageProvider, same(memory));
    });
  });

  group('redirects (phones)', () {
    const file = '$_base/storage/bafy/l1-2x.webp';
    FakeServer serverFor() => FakeServer()
      ..manifest = manifestJson(7, {
        'language': [entryJson('l1')],
      });

    test('none followed automatically; an allowed gateway host is', () async {
      final server = serverFor()
        ..redirects[file] = 'https://gw.test/storage/bafy/l1-2x.webp';
      final store = server.store(allowedHosts: {'gw.test'});
      await store.onFirstFrame();
      expect(store.readyIds, {'l1'});
      expect(server.requests.every((r) => !r.followRedirects), isTrue);
      expect(server.requests.last.url.host, 'gw.test');
      expect(server.cancelled, contains(file), reason: '307 body let go');
    });

    test('another host (not listed) is refused, never requested', () async {
      final server = serverFor()
        ..redirects[file] = 'https://evil.test/storage/bafy/l1-2x.webp';
      final store = server.store(allowedHosts: {'gw.test'});
      await store.onFirstFrame();
      expect(store.readyIds, isEmpty);
      expect(
        server.requests.map((r) => r.url.host),
        isNot(contains('evil.test')),
      );
      expect(store.resolveTop(FFHeroPhoto.language), isNull);
    });

    test('with no list, only the API host itself', () async {
      final server = serverFor()
        ..redirects[file] = 'https://gw.test/storage/bafy/l1-2x.webp';
      final store = server.store();
      await store.onFirstFrame();
      expect(store.readyIds, isEmpty);
      expect(
        server.requests.map((r) => r.url.host),
        isNot(contains('gw.test')),
      );

      SharedPreferences.setMockInitialValues({}); // a fresh install
      final same = serverFor()
        ..redirects[file] = '/storage/bafy/l1-2x.webp?v=2';
      final s2 = same.store();
      await s2.onFirstFrame();
      expect(s2.readyIds, {'l1'}, reason: 'a relative hop on the API host');
    });

    test('a hop to http is refused, even to a listed host', () async {
      for (final to in [
        'http://gw.test/storage/bafy/l1-2x.webp',
        'http://api.fitflex.test/storage/bafy/l1-2x.webp',
      ]) {
        SharedPreferences.setMockInitialValues({}); // a fresh install
        final server = serverFor()..redirects[file] = to;
        final store = server.store(allowedHosts: {'gw.test'});
        await store.onFirstFrame();
        expect(store.readyIds, isEmpty, reason: to);
        expect(server.fileRequests, hasLength(1), reason: 'only the first');
        expect(server.requests.where((r) => r.url.isScheme('http')), isEmpty);
      }
    });

    test('two hops are followed; a third is refused', () async {
      final two = serverFor()
        ..redirects[file] = 'https://gw.test/a/l1-2x.webp'
        ..redirects['https://gw.test/a/l1-2x.webp'] =
            'https://gw.test/b/l1-2x.webp';
      final s2 = two.store(allowedHosts: {'gw.test'});
      await s2.onFirstFrame();
      expect(s2.readyIds, {'l1'});

      SharedPreferences.setMockInitialValues({}); // a fresh install
      final three = serverFor()
        ..redirects[file] = 'https://gw.test/a/l1-2x.webp'
        ..redirects['https://gw.test/a/l1-2x.webp'] =
            'https://gw.test/b/l1-2x.webp'
        ..redirects['https://gw.test/b/l1-2x.webp'] =
            'https://gw.test/c/l1-2x.webp';
      final s3 = three.store(allowedHosts: {'gw.test'});
      await s3.onFirstFrame();
      expect(s3.readyIds, isEmpty);
      expect(
        three.requests.map((r) => r.url.path),
        isNot(contains('/c/l1-2x.webp')),
      );
    });

    test('local development: an http API_BASE allows http hops only', () async {
      const local = 'http://127.0.0.1:3000';
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('l1'), entryJson('l2')],
          'signIn': [entryJson('s1')],
        })
        ..redirects['$local/storage/bafy/l1-2x.webp'] =
            'http://127.0.0.1:3000/zebra/l1-2x.webp'
        ..redirects['$local/storage/bafy/l2-2x.webp'] =
            'https://gw.test/storage/bafy/l2-2x.webp'
        ..redirects['$local/storage/bafy/s1-2x.webp'] =
            'http://gw.test/storage/bafy/s1-2x.webp';
      final store = server.store(apiBase: local, allowedHosts: {'gw.test'});
      await store.onFirstFrame();
      expect(store.readyIds, {'l1', 's1'});
    });

    test('the list itself is never redirected', () async {
      final server = FakeServer()
        ..redirects['$_base/app/hero-images'] = '$_base/app/hero-images?x=1';
      final store = server.store();
      await store.onFirstFrame();
      expect(server.manifestRequests, hasLength(1));
      expect(store.manifest.isEmpty, isTrue);
    });

    test('address rule: ports, user info, the allow-list format', () {
      final store = FakeServer().store(
        allowedHosts: parseHeroAllowedHosts(
          ' GW.test, https://x.test ,a.test:8443,, b.test/path,',
        ),
      );
      expect(store.isAllowedHop(Uri.parse('https://gw.test/f')), isTrue);
      expect(store.isAllowedHop(Uri.parse('https://gw.test:443/f')), isTrue);
      expect(store.isAllowedHop(Uri.parse('https://gw.test:8443/f')), isFalse);
      expect(store.isAllowedHop(Uri.parse('https://a.test:8443/f')), isTrue);
      expect(store.isAllowedHop(Uri.parse('https://a.test/f')), isFalse);
      expect(store.isAllowedHop(Uri.parse('https://x.test/f')), isFalse);
      expect(store.isAllowedHop(Uri.parse('https://b.test/f')), isFalse);
      expect(store.isAllowedHop(Uri.parse('https://u:p@gw.test/f')), isFalse);
      expect(store.isAllowedHop(Uri.parse('$_base/f')), isTrue);
      expect(
        store.isAllowedHop(Uri.parse('https://api.fitflex.test:8443/f')),
        isFalse,
      );
      expect(store.isAllowedHop(Uri.parse('ftp://gw.test/f')), isFalse);
      expect(parseHeroAllowedHosts(''), isEmpty);
    });

    test('a refused status lets the body go', () async {
      final server = serverFor()..statusFor[file] = 404;
      final store = server.store();
      await store.onFirstFrame();
      expect(store.readyIds, isEmpty);
      expect(server.cancelled, contains(file));
    });
  });

  group('deadlines and cut-offs', () {
    testWidgets('one 30 s deadline over the whole photo, then cancelled', (
      tester,
    ) async {
      // 160 KB in 16 KB chunks, one every 5 s: each chunk is quick, the
      // whole is 50 s.
      final server = FakeServer()
        ..manifest = manifestJson(7, {
          'language': [entryJson('slow', bytes: 160 * 1024)],
        })
        ..drip = const Duration(seconds: 5);
      final store = server.store();
      var done = false;
      unawaited(store.onFirstFrame().then((_) => done = true));
      await tester.pump(const Duration(seconds: 29));
      expect(done, isFalse);
      expect(server.bytesStreamed['slow'], greaterThan(0));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(done, isTrue);
      expect(store.readyIds, isEmpty);
      expect(server.bytesStreamed['slow'], lessThan(160 * 1024));
      expect(server.cancelled, contains('$_base/storage/bafy/slow-2x.webp'));
      expect(server.files.names, isEmpty);
      await tester.pump(const Duration(seconds: 10)); // the drip's last timer
    });

    test('a list over 256 KB: reading stops, nothing changes', () async {
      final server = FakeServer()..manifestJunkChunks = 100; // 1.6 MB
      final store = server.store();
      await store.onFirstFrame();
      expect(store.manifest.isEmpty, isTrue);
      expect(server.manifestStreamed, lessThan(100 * 16 * 1024));
      expect(
        server.manifestStreamed,
        lessThanOrEqualTo(HeroImageStore.maxManifestBytes + 2 * 16 * 1024),
      );
      expect(server.cancelled, contains('$_base/app/hero-images'));
    });

    testWidgets('one 5 s deadline over the whole list', (tester) async {
      // 10 small chunks, one a second: under the size cap, over the time.
      final server = FakeServer()
        ..manifestJunkChunks = 10
        ..drip = const Duration(seconds: 1);
      final store = server.store();
      var done = false;
      unawaited(store.onFirstFrame().then((_) => done = true));
      await tester.pump(const Duration(seconds: 4));
      expect(done, isFalse);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(done, isTrue);
      expect(server.manifestStreamed, lessThan(10 * 16 * 1024));
      expect(server.cancelled, contains('$_base/app/hero-images'));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('cache folder', () {
    test('photos live in the app cache folder (not backed up)', () async {
      final tmp = Directory.systemTemp.createTempSync('hero_cache_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final before = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePaths(tmp.path);
      addTearDown(() => PathProviderPlatform.instance = before);
      expect(
        (await heroCacheDirectory()).path,
        '${tmp.path}/cache/hero_images',
      );
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

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';

  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';

  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/documents';

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}
