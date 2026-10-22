import 'package:flutter/foundation.dart';

/// Build-time switch for member event discovery (Marathon & Running Events
/// S2, docs/design/events-s2-organizer-and-discovery.md §13). Off by
/// default: `--dart-define=EVENTS_DISCOVERY=true` turns it on. The UI also
/// needs `GET /events/options` to answer `discovery: true`; with either off
/// there is no Activity segment, no Home card and no `/member/events` route.
const bool kEventsDiscovery = bool.fromEnvironment('EVENTS_DISCOVERY');

bool? _debugOverride;

/// Whether event discovery is on in this build.
bool get eventsDiscoveryEnabled => _debugOverride ?? kEventsDiscovery;

/// Lets widget tests render both sides of the flag. Pass null to go back to
/// the build-time value.
@visibleForTesting
set debugEventsDiscoveryOverride(bool? value) => _debugOverride = value;
