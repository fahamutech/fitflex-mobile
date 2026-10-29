import 'package:flutter/foundation.dart';

import '../photo_hero_flag.dart';

/// Build-time switch for the partner home photo and logo
/// (docs/design/photo-hero-screens.md §39–§45). Off by default:
/// `--dart-define=PARTNER_MEDIA_UI=true` turns it on, and only together with
/// `PHOTO_HERO_UI=true`. With it off there is no `/partner/media` request,
/// no saved copy, no Settings entry and no `brand-media` route; the owner,
/// trainer and vendor homes are exactly as before.
const bool kPartnerMediaUi = bool.fromEnvironment('PARTNER_MEDIA_UI');

bool? _debugOverride;

/// Whether this build shows partner photos and logos: this flag and the
/// photo hero flag must both be on.
bool get partnerMediaUi => photoHeroUi && (_debugOverride ?? kPartnerMediaUi);

/// Lets tests render both sides of the flag. Pass null to go back to the
/// build-time value. The photo hero flag still applies.
@visibleForTesting
set debugPartnerMediaUiOverride(bool? value) => _debugOverride = value;
