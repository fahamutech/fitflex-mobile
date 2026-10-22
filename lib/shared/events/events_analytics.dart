import 'package:flutter/foundation.dart';

/// Event-discovery analytics (spec §15). No client pipeline exists for these
/// yet (the promotion tracker only records promoted cards), so each call is a
/// named no-op that records to [debugSink] in tests. S7 connects them; the
/// names and payloads are fixed here. No personal data in any payload.
class EventsAnalytics {
  EventsAnalytics._();

  /// What was recorded, for tests. Null in the app.
  @visibleForTesting
  static List<({String name, Map<String, Object?> props})>? debugSink;

  static void _record(String name, Map<String, Object?> props) {
    debugSink?.add((name: name, props: props));
  }

  static void listViewed({
    required int filtersActive,
    required int resultCount,
  }) => _record('event_list_viewed', {
    'filtersActive': filtersActive,
    'resultCount': resultCount,
  });

  static void detailViewed({
    required String eventId,
    required String availability,
  }) => _record('event_detail_viewed', {
    'eventId': eventId,
    'availability': availability,
  });

  static void saved({required String eventId, required bool saved}) =>
      _record('event_saved', {'eventId': eventId, 'saved': saved});
}
