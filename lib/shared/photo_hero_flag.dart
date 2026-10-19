import 'package:flutter/foundation.dart';

/// Build-time switch for the photo hero screens (docs/design/photo-hero-screens.md).
/// Off by default: `--dart-define=PHOTO_HERO_UI=true` turns it on. With it
/// off, Language, Sign in, Role, Sign up and member Home are unchanged.
const bool kPhotoHeroUi = bool.fromEnvironment('PHOTO_HERO_UI');

bool? _debugOverride;

/// Whether the photo hero screens are on in this build.
bool get photoHeroUi => _debugOverride ?? kPhotoHeroUi;

/// Lets widget tests render both sides of the flag. Pass null to go back to
/// the build-time value.
@visibleForTesting
set debugPhotoHeroUiOverride(bool? value) => _debugOverride = value;
