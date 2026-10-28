// Release guard for the photo heroes (owner 2026-10-22): the four photos the
// owner collected from the internet are OK for testing, NOT cleared for
// release. They are listed in kTestOnlyHeroAssets; a test run with
// `--dart-define=PHOTO_HERO_RELEASE=true` fails while any is still mapped:
//
//   flutter test test/photo_hero_release_guard_test.dart \
//     --dart-define=PHOTO_HERO_UI=true --dart-define=PHOTO_HERO_RELEASE=true
//
// Run it before any build that shows PHOTO_HERO_UI to users (see the notes
// in .github/workflows/deploy-web.yml and distribute-android.yml).

import 'dart:io';

import 'package:fitflexmobile/shared/components/ff_photo_hero.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter_test/flutter_test.dart';

const _testOnlyLicence =
    'Collected from the internet by owner; NOT cleared for release — '
    'testing only (owner 2026-10-22). Replace before PHOTO_HERO_UI goes on '
    'for users.';

void main() {
  final licences = File('assets/photos/hero/LICENSES.md').readAsStringSync();
  String row(FFHeroPhoto p) => licences
      .split('\n')
      .firstWhere((l) => l.startsWith('| `${p.file}.webp`'));

  test('the test-only list is exactly the owner-collected photos', () {
    expect(kTestOnlyHeroAssets, {
      FFHeroPhoto.trainers,
      FFHeroPhoto.activityChallenges,
      FFHeroPhoto.gyms,
      FFHeroPhoto.activityToday,
    });
    for (final p in FFHeroPhoto.values) {
      final owner = p.sourceId.startsWith('owner-');
      // Every owner photo is on the list (a new one must be added too).
      expect(kTestOnlyHeroAssets.contains(p), owner, reason: p.name);
      final licence = row(p).split('|')[5].trim();
      if (owner) {
        expect(licence, _testOnlyLicence, reason: p.name);
      } else {
        expect(licence, isNot(contains('NOT cleared')), reason: p.name);
      }
    }
  });

  test('PHOTO_HERO_RELEASE: no test-only photo may ship', () {
    if (!kPhotoHeroRelease) {
      markTestSkipped(
        'Run with --dart-define=PHOTO_HERO_RELEASE=true before a user build',
      );
      return;
    }
    expect(
      kTestOnlyHeroAssets.map((p) => '${p.file} (${p.sourceId})').toList(),
      isEmpty,
      reason:
          'PHOTO_HERO_RELEASE is set, but these hero photos are testing only '
          '(collected from the internet, not cleared for release; owner '
          '2026-10-22). Replace them and update LICENSES.md first.',
    );
  });
}
