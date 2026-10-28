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

  // ── Registration (S3 spec §7.2) ────────────────────────────────────────

  static void registrationStarted({
    required String eventId,
    required String source,
  }) => _record('registration_started', {'eventId': eventId, 'source': source});

  static void quoteCreated({
    required String eventId,
    required int placesCount,
    required int totalTzs,
    required String mode,
  }) => _record('checkout_quote_created', {
    'eventId': eventId,
    'placesCount': placesCount,
    'totalTzs': totalTzs,
    'mode': mode,
  });

  static void orderCreated({
    required String orderId,
    required String eventId,
    required int placesCount,
    required int totalTzs,
    required String mode,
    required bool team,
  }) => _record('order_created', {
    'orderId': orderId,
    'eventId': eventId,
    'placesCount': placesCount,
    'totalTzs': totalTzs,
    'mode': mode,
    'team': team,
  });

  static void orderCancelled({
    required String orderId,
    required String reason,
  }) => _record('order_cancelled', {'orderId': orderId, 'reason': reason});

  static void registrationClaimed({
    required String registrationId,
    required String via,
  }) => _record('registration_claimed', {
    'registrationId': registrationId,
    'via': via,
  });
}
