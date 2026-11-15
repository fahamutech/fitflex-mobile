import 'package:flutter/foundation.dart';

/// Build-time switch for custom gym passes (Custom Gym Passes, phase 4).
/// Off by default: `--dart-define=GYM_CUSTOM_PASSES=true` turns it on. The
/// server has its own `GYM_CUSTOM_PASSES` flag; with it off every route
/// answers 404 `feature_disabled`, and this app treats that as "not
/// available" (see [isGymPassesUnavailable]). With either off the gym page,
/// the profile and the sign-in claim behave exactly as before.
const bool kGymCustomPasses = bool.fromEnvironment('GYM_CUSTOM_PASSES');

bool? _debugOverride;

/// Whether custom gym passes are on in this build.
bool get gymCustomPassesEnabled => _debugOverride ?? kGymCustomPasses;

/// Lets widget tests render both sides of the flag. Pass null to go back to
/// the build-time value.
@visibleForTesting
set debugGymCustomPassesOverride(bool? value) => _debugOverride = value;
