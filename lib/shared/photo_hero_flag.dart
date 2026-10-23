import 'package:flutter/foundation.dart';

/// Build-time switch for the photo hero screens (docs/design/photo-hero-screens.md).
/// Off by default: `--dart-define=PHOTO_HERO_UI=true` turns it on. With it
/// off, Language, Sign in, Role, Sign up and member Home are unchanged.
const bool kPhotoHeroUi = bool.fromEnvironment('PHOTO_HERO_UI');

/// Build-time marker for a build that shows the photo heroes to users
/// (`--dart-define=PHOTO_HERO_RELEASE=true`). Nothing in the app reads it;
/// `test/photo_hero_release_guard_test.dart` run with the same define fails
/// while any test-only photo (`kTestOnlyHeroAssets` in
/// components/ff_photo_hero.dart) is still bundled. Off by default.
const bool kPhotoHeroRelease = bool.fromEnvironment('PHOTO_HERO_RELEASE');

bool? _debugOverride;

/// Whether the photo hero screens are on in this build.
bool get photoHeroUi => _debugOverride ?? kPhotoHeroUi;

/// Lets widget tests render both sides of the flag. Pass null to go back to
/// the build-time value.
@visibleForTesting
set debugPhotoHeroUiOverride(bool? value) => _debugOverride = value;
