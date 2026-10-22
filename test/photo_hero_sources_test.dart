// Hero and footer photos from approved sources only (owner approval
// 2026-10-22): FitFlex Africa's own AI-generated scenes and four photos the
// owner supplied. The Pexels stand-ins are gone; no crop shows another
// brand's logo (owner rule 2026-10-20), and nothing is upscaled.

import 'dart:io';
import 'dart:typed_data';

import 'package:fitflexmobile/shared/components/ff_photo_footer.dart';
import 'package:fitflexmobile/shared/components/ff_photo_hero.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _generated =
    'FitFlex Africa, AI-generated via Figma AI (gpt-image-2.5), '
    '2026-10-22, no people';
const _owner =
    'Supplied by owner 2026-10-22; owner to confirm source/licence before '
    'flag on';

/// The approved slot → scene mapping (owner, 2026-10-22).
const _mapping = <FFHeroPhoto, String>{
  FFHeroPhoto.language: 'fitflex-gen-01-reception',
  FFHeroPhoto.signIn: 'fitflex-gen-04-entrance',
  FFHeroPhoto.signUp: 'fitflex-gen-05-locker-towel',
  FFHeroPhoto.pin: 'fitflex-gen-06-desk-sign',
  FFHeroPhoto.role: 'fitflex-gen-07-wide-floor',
  FFHeroPhoto.homeStart: 'fitflex-gen-08-sunrise-neon',
  FFHeroPhoto.homePass: 'fitflex-gen-09-rack-shaker',
  FFHeroPhoto.profile: 'fitflex-gen-10-towel-bench',
  FFHeroPhoto.upgrade: 'fitflex-gen-11-premium-zone',
  FFHeroPhoto.activityToday: 'owner-16-dumbbells-palms',
  FFHeroPhoto.activityTraining: 'fitflex-gen-12-cable-zone',
  FFHeroPhoto.activityChallenges: 'owner-02-hooded-bench-back',
  FFHeroPhoto.activityProgress: 'fitflex-gen-13-treadmills-decal',
  FFHeroPhoto.gyms: 'owner-15-empty-gym-windows',
  FFHeroPhoto.trainers: 'owner-01-lat-pulldown-back',
  FFHeroPhoto.shop: 'fitflex-gen-02-shop',
  FFHeroPhoto.trainer: 'fitflex-gen-14-coaching',
  FFHeroPhoto.vendor: 'fitflex-gen-15-vendor-packing',
  FFHeroPhoto.owner: 'fitflex-gen-03-gym-floor',
  FFHeroPhoto.footerStretch: 'fitflex-gen-16-footer-stretch',
  FFHeroPhoto.footerRooftop: 'fitflex-gen-17-footer-rooftop',
  FFHeroPhoto.footerHydration: 'fitflex-gen-18-footer-hydration',
  FFHeroPhoto.footerNightHall: 'fitflex-gen-19-footer-night-hall',
};

void main() {
  final licences = File('assets/photos/hero/LICENSES.md').readAsStringSync();
  final rows = [
    for (final l in licences.split('\n'))
      if (l.startsWith('| `')) l,
  ];

  String row(FFHeroPhoto p) =>
      rows.firstWhere((l) => l.startsWith('| `${p.file}.webp`'));

  List<String> cells(String row) =>
      row.split('|').map((c) => c.trim()).toList();

  test('every slot uses its approved scene', () {
    expect({for (final p in FFHeroPhoto.values) p: p.sourceId}, _mapping);
    expect(footerPhotoPool, [
      FFHeroPhoto.footerStretch,
      FFHeroPhoto.footerRooftop,
      FFHeroPhoto.footerHydration,
      FFHeroPhoto.footerNightHall,
    ]);
  });

  test('only approved sources: each row names its source and licence', () {
    for (final p in FFHeroPhoto.values) {
      final c = cells(row(p));
      final source = p.sourceId.replaceFirst('fitflex-', '');
      expect(c[3], contains('`$source.'), reason: p.name);
      if (p.sourceId.startsWith('owner-')) {
        expect(c[5], _owner, reason: p.name);
        expect(c[3], contains('owner-supplied'), reason: p.name);
      } else {
        expect(p.sourceId, startsWith('fitflex-gen-'), reason: p.name);
        expect(c[5], _generated, reason: p.name);
        expect(c[3], contains('puGVsWuNb8IJb43IkB85Hc'), reason: p.name);
      }
      expect(c[10], contains('no face in frame'), reason: p.name);
    }
    // One row per bundled file, and no row for a file that is not bundled.
    expect(rows, hasLength(FFHeroPhoto.values.length));
    final files = {
      for (final f in Directory('assets/photos/hero').listSync())
        if (f is File && f.path.endsWith('.webp')) f.uri.pathSegments.last,
    };
    expect(files, {for (final p in FFHeroPhoto.values) '${p.file}.webp'});
    final files2x = {
      for (final f in Directory('assets/photos/hero/2.0x').listSync())
        if (f is File) f.uri.pathSegments.last,
    };
    expect(files2x, files);
  });

  test('no stock photo is referenced anywhere', () {
    final banned = RegExp(r'pexels|unsplash|scene-', caseSensitive: false);
    for (final r in rows) {
      expect(r, isNot(matches(banned)));
    }
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        expect(f.readAsStringSync(), isNot(matches(banned)), reason: f.path);
      }
    }
    expect(File('pubspec.yaml').readAsStringSync(), isNot(matches(banned)));
  });

  test('no upscaling: 2x file = source crop at 1:1, within the source', () {
    for (final p in FFHeroPhoto.values) {
      final c = cells(row(p));
      final src = RegExp(r'^(\d+)x(\d+)$').firstMatch(c[4])!;
      final sw = int.parse(src[1]!), sh = int.parse(src[2]!);
      final crop = RegExp(r'^(\d+),(\d+),(\d+),(\d+)').firstMatch(c[6])!;
      final l = int.parse(crop[1]!), t = int.parse(crop[2]!);
      final r = int.parse(crop[3]!), b = int.parse(crop[4]!);
      expect(r, lessThanOrEqualTo(sw), reason: p.name);
      expect(b, lessThanOrEqualTo(sh), reason: p.name);
      final (w, h) = _vp8Size(File('assets/photos/hero/2.0x/${p.file}.webp'));
      // 2x width never beyond the source's width or the crop's.
      expect(w, lessThanOrEqualTo(sw), reason: p.name);
      expect(w, lessThanOrEqualTo(r - l), reason: p.name);
      expect(h, lessThanOrEqualTo(b - t), reason: p.name);
      expect(c[7], '${w}x$h', reason: p.name);
      expect(p.aspect, closeTo(w / h, 0.005), reason: p.name);
      final (w1, h1) = _vp8Size(File('assets/photos/hero/${p.file}.webp'));
      expect(w1, w ~/ 2, reason: p.name);
      expect(h1, h ~/ 2, reason: p.name);
    }
  });

  test('files: VP8 only (no metadata), caps, total within 2.0 MB', () {
    var total = 0;
    for (final p in FFHeroPhoto.values) {
      final x2 = File('assets/photos/hero/2.0x/${p.file}.webp');
      final x1 = File('assets/photos/hero/${p.file}.webp');
      for (final f in [x1, x2]) {
        expect(_webpChunks(f), ['VP8 '], reason: f.path);
      }
      expect(x2.lengthSync(), lessThanOrEqualTo(150 * 1000), reason: p.name);
      expect(x1.lengthSync(), lessThanOrEqualTo(60 * 1000), reason: p.name);
      total += x1.lengthSync() + x2.lengthSync();
    }
    // Budget raised from 1.6 MB to 2.0 MB for this set (2026-10-22).
    expect(total, lessThanOrEqualTo(2000 * 1000));
    expect(licences, contains('= ${_thousands(total)} bytes'));
  });

  test('sourceId rules: one scene per file; neighbours differ', () {
    expect({
      for (final p in FFHeroPhoto.values) p.sourceId,
    }, hasLength(FFHeroPhoto.values.length));
    // Activity: four sections, four scenes.
    expect({
      FFHeroPhoto.activityToday.sourceId,
      FFHeroPhoto.activityTraining.sourceId,
      FFHeroPhoto.activityChallenges.sourceId,
      FFHeroPhoto.activityProgress.sourceId,
    }, hasLength(4));
    // Pre-sign-in screens one step apart.
    expect(FFHeroPhoto.language.sourceId, isNot(FFHeroPhoto.signIn.sourceId));
    expect(FFHeroPhoto.signIn.sourceId, isNot(FFHeroPhoto.signUp.sourceId));
    expect(FFHeroPhoto.signUp.sourceId, isNot(FFHeroPhoto.role.sourceId));
    // A footer never shows the scene of any top hero.
    final tops = {
      for (final p in FFHeroPhoto.values)
        if (!footerPhotoPool.contains(p)) p.sourceId,
    };
    for (final f in footerPhotoPool) {
      expect(tops, isNot(contains(f.sourceId)), reason: f.name);
    }
    for (final MapEntry(key: page, value: footer) in footerPagePhotos.entries) {
      for (final top in FFHeroPhoto.values) {
        if (footerPhotoPool.contains(top)) continue;
        expect(
          footerPhotoFor(page, top: top),
          footer,
          reason: '$page / ${top.name}',
        );
      }
    }
  });

  test('focal points keep the signs in the clear photo', () {
    expect(FFHeroPhoto.role.focal, Alignment.topCenter);
    expect(FFHeroPhoto.shop.focal, Alignment.topCenter);
  });
}

String _thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

(int, int) _vp8Size(File f) {
  final b = f.readAsBytesSync();
  expect(String.fromCharCodes(b.sublist(12, 16)), 'VP8 ');
  const d = 20;
  expect(b.sublist(d + 3, d + 6), [0x9d, 0x01, 0x2a]);
  final data = ByteData.sublistView(b);
  return (
    data.getUint16(d + 6, Endian.little) & 0x3fff,
    data.getUint16(d + 8, Endian.little) & 0x3fff,
  );
}

List<String> _webpChunks(File f) {
  final b = f.readAsBytesSync();
  final data = ByteData.sublistView(b);
  final names = <String>[];
  var i = 12;
  while (i + 8 <= b.length) {
    names.add(String.fromCharCodes(b.sublist(i, i + 4)));
    final n = data.getUint32(i + 4, Endian.little);
    i += 8 + n + (n & 1);
  }
  return names;
}
