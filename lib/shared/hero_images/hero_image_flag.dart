import 'package:flutter/foundation.dart';

import '../photo_hero_flag.dart';

/// Build-time switch for admin-published app photos (photo-hero increment
/// plan, slice 6). Off by default: `--dart-define=HERO_IMAGES_REMOTE=true`
/// turns it on, and only together with `PHOTO_HERO_UI=true`. With it off the
/// app never asks the server for the photo list and shows only its bundled
/// photos.
const bool kHeroImagesRemote = bool.fromEnvironment('HERO_IMAGES_REMOTE');

bool? _debugOverride;

/// Whether this build reads admin-published photos: this flag and the photo
/// hero flag must both be on.
bool get heroImagesRemote =>
    photoHeroUi && (_debugOverride ?? kHeroImagesRemote);

/// Lets tests render both sides of the flag. Pass null to go back to the
/// build-time value. The photo hero flag still applies.
@visibleForTesting
set debugHeroImagesRemoteOverride(bool? value) => _debugOverride = value;
