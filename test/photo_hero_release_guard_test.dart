// Release guard for the photo heroes (owner 2026-10-22): a photo that is OK
// for testing but NOT cleared for release (the four the owner collected
// from the internet, until 2026-10-28) is listed in kTestOnlyHeroAssets; a
// test run with `--dart-define=PHOTO_HERO_RELEASE=true` fails while any is
// still mapped:
//
//   flutter test test/photo_hero_release_guard_test.dart \
//     --dart-define=PHOTO_HERO_UI=true --dart-define=PHOTO_HERO_RELEASE=true
//
// The user builds (deploy-web, distribute-android, release-play-store) run
// it before building whenever PHOTO_HERO_UI is on, and fail if it fails.
// Since 2026-10-28 (owner approval) the four are replaced by FitFlex
// Africa's own generated scenes and the list is empty.

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
    // None left since 2026-10-28 (replaced by gen-21..gen-24).
    expect(kTestOnlyHeroAssets, isEmpty);
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
