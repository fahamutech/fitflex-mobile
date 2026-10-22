// Hero photos without third-party logos (owner rule 2026-10-20): the
// treadmill photo pexels-12250460 shows another gym's "smart fit" logo and
// must not come back; the slots that used it (Language, Activity: Today) and
// the crops that showed a gym's logo screens and wall slogan (role, Home
// start) or a large maker name (owner home) use clean crops.

import 'dart:io';
import 'dart:typed_data';

import 'package:fitflexmobile/shared/components/ff_photo_footer.dart';
import 'package:fitflexmobile/shared/components/ff_photo_hero.dart';
import 'package:flutter_test/flutter_test.dart';

const _banned = '12250460';

void main() {
  final licences = File('assets/photos/hero/LICENSES.md').readAsStringSync();

  String row(FFHeroPhoto p) => licences
      .split('\n')
      .firstWhere((l) => l.startsWith('| `${p.file}.webp`'));

  List<String> cells(String row) =>
      row.split('|').map((c) => c.trim()).toList();

  test('pexels-12250460 is not referenced by any photo, file or row', () {
    for (final p in FFHeroPhoto.values) {
      expect(p.sourceId, isNot(contains(_banned)), reason: p.name);
      expect(row(p), isNot(contains(_banned)), reason: p.name);
    }
    for (final l in licences.split('\n')) {
      if (l.startsWith('| `')) expect(l, isNot(contains(_banned)));
    }
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        expect(f.readAsStringSync(), isNot(contains(_banned)), reason: f.path);
      }
    }
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains(_banned)));
  });

  test('replaced slots use the clean scenes', () {
    expect(FFHeroPhoto.language.sourceId, 'pexels-4716814');
    expect(FFHeroPhoto.activityToday.sourceId, 'pexels-4173217');
    expect(FFHeroPhoto.role.sourceId, 'pexels-29526371');
    expect(FFHeroPhoto.homeStart.sourceId, 'pexels-29526371');
    expect(FFHeroPhoto.owner.sourceId, 'pexels-29526371');
    expect(row(FFHeroPhoto.activityToday), contains('no face in frame'));
    // Crops of 29526371 stay below the gym's logo screens and wall slogan
    // (y < 640) and left of the lettered machine (x > 1083).
    for (final p in [FFHeroPhoto.role, FFHeroPhoto.homeStart]) {
      final m = RegExp(r'(\d+),(\d+),(\d+),(\d+) \(').firstMatch(row(p))!;
      expect(int.parse(m[2]!), greaterThanOrEqualTo(640), reason: p.name);
      expect(int.parse(m[3]!), lessThanOrEqualTo(1083), reason: p.name);
    }
    final owner = RegExp(
      r'(\d+),(\d+),(\d+),(\d+) \(',
    ).firstMatch(row(FFHeroPhoto.owner))!;
    expect(int.parse(owner[3]!), lessThanOrEqualTo(1083));
  });

  test('neighbours still differ', () {
    // Language → Sign in.
    expect(FFHeroPhoto.language.sourceId, isNot(FFHeroPhoto.signIn.sourceId));
    // Activity: four sections, four scenes; none shared with Home, Profile
    // or Gyms (one tab away) or with the Activity footer.
    const sections = [
      FFHeroPhoto.activityToday,
      FFHeroPhoto.activityTraining,
      FFHeroPhoto.activityChallenges,
      FFHeroPhoto.activityProgress,
    ];
    expect({for (final p in sections) p.sourceId}, hasLength(4));
    final neighbours = {
      FFHeroPhoto.homeStart.sourceId,
      FFHeroPhoto.homePass.sourceId,
      FFHeroPhoto.profile.sourceId,
      FFHeroPhoto.gyms.sourceId,
      footerPhotoFor(
        'member.activity',
        top: FFHeroPhoto.activityToday,
      ).sourceId,
    };
    expect(neighbours, isNot(contains(FFHeroPhoto.activityToday.sourceId)));
  });

  test('no hero is upscaled: crop ≥ 2x file, file matches its row', () {
    for (final p in FFHeroPhoto.values) {
      final c = cells(row(p));
      final crop = RegExp(r'^(\d+),(\d+),(\d+),(\d+)').firstMatch(c[6])!;
      final cw = int.parse(crop[3]!) - int.parse(crop[1]!);
      final ch = int.parse(crop[4]!) - int.parse(crop[2]!);
      final size = RegExp(r'^(\d+)x(\d+)$').firstMatch(c[7])!;
      final w = int.parse(size[1]!), h = int.parse(size[2]!);
      expect(cw, greaterThanOrEqualTo(w), reason: p.name);
      expect(ch, greaterThanOrEqualTo(h), reason: p.name);
      final (fw, fh) = _vp8Size(File('assets/photos/hero/2.0x/${p.file}.webp'));
      expect((fw, fh), (w, h), reason: p.name);
      expect(p.aspect, closeTo(fw / fh, 0.01), reason: p.name);
    }
  });

  test('replaced files: hero caps, VP8 only, total within 1.6 MB', () {
    const replaced = [
      FFHeroPhoto.language,
      FFHeroPhoto.activityToday,
      FFHeroPhoto.role,
      FFHeroPhoto.homeStart,
      FFHeroPhoto.owner,
    ];
    for (final p in replaced) {
      final x2 = File('assets/photos/hero/2.0x/${p.file}.webp');
      final x1 = File('assets/photos/hero/${p.file}.webp');
      expect(x2.lengthSync(), lessThanOrEqualTo(150 * 1000), reason: p.name);
      expect(x1.lengthSync(), lessThanOrEqualTo(60 * 1000), reason: p.name);
      for (final f in [x1, x2]) {
        expect(_webpChunks(f), ['VP8 '], reason: f.path);
      }
    }
    var total = 0;
    for (final f in Directory('assets/photos/hero').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.webp')) total += f.lengthSync();
    }
    expect(total, lessThanOrEqualTo(1600 * 1000));
  });
}

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
