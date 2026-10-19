import 'package:flutter/foundation.dart';

import 'photo_hero_flag.dart';

/// Build-time switch for the photo footer band (photo-hero increment plan,
/// slice 2). Off by default: `--dart-define=PHOTO_FOOTER_UI=true` turns it
/// on, and only together with `PHOTO_HERO_UI=true`. Separate from the hero
/// flag so heroes can go on without footers.
const bool kPhotoFooterUi = bool.fromEnvironment('PHOTO_FOOTER_UI');

bool? _debugOverride;

/// Whether pages end with the photo footer in this build: the footer flag
/// and the photo hero flag must both be on.
bool get photoFooterUi => photoHeroUi && (_debugOverride ?? kPhotoFooterUi);

/// Lets widget tests render both sides of the flag. Pass null to go back to
/// the build-time value. The hero flag still applies.
@visibleForTesting
set debugPhotoFooterUiOverride(bool? value) => _debugOverride = value;
