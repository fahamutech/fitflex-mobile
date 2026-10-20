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

/// Build-time list of storage hosts a photo address may redirect to,
/// comma-separated (`--dart-define=HERO_IMAGES_ALLOWED_HOSTS=cdn.example`;
/// `host:port` for a port other than the scheme's default). The server's
/// `/storage/<cid>/<file>` answers with a 307 to its file store
/// (`ZEBRA_BASE_URL` in fitflex-functions), so that store's host has to be
/// listed here. Empty by default: only the API_BASE host itself is accepted,
/// and any redirect elsewhere falls back to the bundled photo.
const String kHeroImagesAllowedHosts = String.fromEnvironment(
  'HERO_IMAGES_ALLOWED_HOSTS',
);

/// [raw] split into lower-case `host` / `host:port` entries. Anything that
/// looks like more than a host (a scheme, a path, a user) is dropped.
Set<String> parseHeroAllowedHosts(String raw) => {
  for (final part in raw.split(','))
    if (_hostEntry.hasMatch(part.trim())) part.trim().toLowerCase(),
};

final _hostEntry = RegExp(r'^[A-Za-z0-9.-]+(:[0-9]{1,5})?$');
