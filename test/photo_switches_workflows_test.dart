// The photo switches in the real builds (owner approval 2026-10-28): every
// `flutter build` in the user and check workflows reads PHOTO_HERO_UI and
// PHOTO_FOOTER_UI from repository variables, off by default, and the user
// builds run the photo-hero release guard before building whenever
// PHOTO_HERO_UI is on. The admin-published photos (HERO_IMAGES_REMOTE,
// HERO_IMAGES_ALLOWED_HOSTS) stay tester-only: no user build reads them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dir = '.github/workflows';

/// The workflows that build the app.
const _all = [
  'deploy-web.yml',
  'distribute-android.yml',
  'release-play-store.yml',
  'build-flutter.yml',
];

/// The workflows whose builds reach users.
const _userBuilds = [
  'deploy-web.yml',
  'distribute-android.yml',
  'release-play-store.yml',
];

const _guard =
    'flutter test test/photo_hero_release_guard_test.dart '
    '--dart-define=PHOTO_HERO_UI=true --dart-define=PHOTO_HERO_RELEASE=true';

String _read(String name) => File('$_dir/$name').readAsStringSync();

/// The job's steps, split on `- name:` (name, body).
List<(String, String)> _steps(String wf) {
  final steps = <(String, String)>[];
  final start = RegExp(r'^      - name: (.*)$', multiLine: true);
  final matches = start.allMatches(wf).toList();
  for (var i = 0; i < matches.length; i++) {
    final end = i + 1 < matches.length ? matches[i + 1].start : wf.length;
    steps.add((matches[i][1]!.trim(), wf.substring(matches[i].start, end)));
  }
  return steps;
}

/// Each `flutter build …` command, joined across `\` line breaks.
List<String> _builds(String wf) {
  final joined = wf.replaceAll(RegExp(r'\\\n\s*'), ' ');
  return [
    for (final l in joined.split('\n'))
      if (l.contains('flutter build ')) l.trim(),
  ];
}

void main() {
  group('repository variables, off by default', () {
    for (final name in _all) {
      test(name, () {
        final wf = _read(name);
        if (name == 'distribute-android.yml') {
          // Manual input true OR the repository variable true.
          expect(
            wf,
            contains(
              "PHOTO_HERO_UI: \${{ (github.event_name == 'workflow_dispatch' "
              "&& inputs.photo_hero) && 'true' || vars.PHOTO_HERO_UI || "
              "'false' }}",
            ),
          );
          expect(
            wf,
            contains(
              "PHOTO_FOOTER_UI: \${{ (github.event_name == "
              "'workflow_dispatch' && inputs.photo_footer) && 'true' || "
              "vars.PHOTO_FOOTER_UI || 'false' }}",
            ),
          );
          expect(wf, contains('photo_hero:'));
          expect(wf, contains('photo_footer:'));
        } else {
          expect(
            wf,
            contains("PHOTO_HERO_UI: \${{ vars.PHOTO_HERO_UI || 'false' }}"),
          );
          expect(
            wf,
            contains(
              "PHOTO_FOOTER_UI: \${{ vars.PHOTO_FOOTER_UI || 'false' }}",
            ),
          );
        }
        final builds = _builds(wf);
        expect(builds, isNotEmpty);
        for (final b in builds) {
          expect(b, contains('--dart-define=PHOTO_HERO_UI="\$PHOTO_HERO_UI"'));
          expect(
            b,
            contains('--dart-define=PHOTO_FOOTER_UI="\$PHOTO_FOOTER_UI"'),
          );
        }
      });
    }
  });

  group('release guard before the build when PHOTO_HERO_UI is on', () {
    for (final name in _userBuilds) {
      test(name, () {
        final steps = _steps(_read(name));
        final guard = steps.indexWhere(
          (s) => s.$1 == 'Photo hero release guard',
        );
        expect(guard, isNot(-1));
        final body = steps[guard].$2;
        expect(body, contains("if: env.PHOTO_HERO_UI == 'true'"));
        expect(body, contains(_guard));
        // No continue-on-error: a failing guard fails the job.
        expect(body, isNot(contains('continue-on-error')));
        final firstBuild = steps.indexWhere(
          (s) => s.$2.contains('flutter build '),
        );
        expect(firstBuild, greaterThan(guard));
        // Dependencies are fetched before the guard runs.
        final pubGet = steps.indexWhere(
          (s) => s.$2.contains('flutter pub get'),
        );
        expect(pubGet, lessThanOrEqualTo(guard));
      });
    }
  });

  test('HERO_IMAGES_REMOTE stays tester-only', () {
    for (final name in ['deploy-web.yml', 'release-play-store.yml']) {
      final wf = _read(name);
      for (final b in _builds(wf)) {
        expect(b, isNot(contains('HERO_IMAGES_REMOTE')), reason: name);
        expect(b, isNot(contains('HERO_IMAGES_ALLOWED_HOSTS')), reason: name);
      }
      expect(wf, isNot(contains('vars.HERO_IMAGES_REMOTE')), reason: name);
    }
    for (final b in _builds(_read('build-flutter.yml'))) {
      expect(b, isNot(contains('HERO_IMAGES_REMOTE')));
    }
    final dist = _read('distribute-android.yml');
    expect(
      dist,
      contains(
        "HERO_IMAGES_REMOTE: \${{ github.event_name == 'workflow_dispatch' "
        "&& inputs.hero_images_remote && 'true' || 'false' }}",
      ),
    );
    expect(dist, isNot(contains('vars.HERO_IMAGES_REMOTE')));
  });
}
