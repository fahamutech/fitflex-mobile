// Events S4 (docs/design/events-s4-payments-and-tickets.md §3.8, §5.4, §5.5,
// §5.8): tickets as the server returns them, and the small on-device copy of
// the last good ticket so a code still shows with no signal at the venue.
//
// The QR payload is whatever the server sent (`qrPayload`); the app never
// builds or alters a token. Nothing here is written to logs or analytics.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_order.dart';
import 'event_summary.dart';

String _str(Object? v) => v?.toString() ?? '';

String? _opt(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// `kit.state` on a ticket (S5 fills it; null before then).
String? kitStateOf(Object? json) => json is Map ? _opt(json['state']) : null;

/// A ticket's state on an order's registration row (spec §3.5): no token.
class RegistrationTicket {
  const RegistrationTicket({this.state = 'none', this.displayCode});

  /// `active` | `revoked` | `none`.
  final String state;
  final String? displayCode;

  bool get isActive => state == 'active';
  bool get isRevoked => state == 'revoked';

  static RegistrationTicket? fromJson(Object? json) {
    if (json is! Map) return null;
    return RegistrationTicket(
      state: _opt(json['state']) ?? 'none',
      displayCode: _opt(json['displayCode']),
    );
  }
}

/// One card of the wallet (`GET /me/event-tickets` item, spec §3.8.4).
/// There is no token in the list.
class EventTicketRow {
  const EventTicketRow({
    required this.registrationId,
    this.ticketId = '',
    this.displayCode = '',
    this.state = 'active',
    this.event,
    this.categoryName = '',
    this.categoryDistanceM = 0,
    this.categoryStartsAt,
    this.ticketTypeName = '',
    this.firstName = '',
    this.lastName = '',
    this.relation = '',
    this.orderReference = '',
    this.issuedAt,
    this.kitState,
  });

  final String registrationId;
  final String ticketId;
  final String displayCode;

  /// `active` | `revoked`.
  final String state;
  final EventSummary? event;
  final String categoryName;
  final int categoryDistanceM;
  final DateTime? categoryStartsAt;
  final String ticketTypeName;
  final String firstName;
  final String lastName;

  /// `self` | `purchased` | `claimed`.
  final String relation;
  final String orderReference;
  final DateTime? issuedAt;
  final String? kitState;

  bool get isActive => state == 'active';

  String get participantName =>
      [firstName, lastName].where((s) => s.trim().isNotEmpty).join(' ');

  /// The event happened or is over, as far as the list knows.
  bool isPast(DateTime now) {
    final at = event?.startsAt;
    return at != null && at.isBefore(now);
  }

  /// Shown under "Cancelled" (revoked) or as "Event cancelled".
  bool get eventCancelled => event?.availability == EventAvailability.cancelled;

  static EventTicketRow fromJson(Map json) {
    final category = json['category'] is Map
        ? json['category'] as Map
        : const {};
    final ticketType = json['ticketType'] is Map
        ? json['ticketType'] as Map
        : const {};
    final participant = json['participant'] is Map
        ? json['participant'] as Map
        : const {};
    return EventTicketRow(
      registrationId: _str(json['registrationId']),
      ticketId: _str(json['ticketId']),
      displayCode: _str(json['displayCode']),
      state: _opt(json['state']) ?? 'active',
      event: json['event'] is Map ? eventSummaryOf(json['event']) : null,
      categoryName: _str(category['name']),
      categoryDistanceM: category['distanceM'] is num
          ? (category['distanceM'] as num).toInt()
          : 0,
      categoryStartsAt: parseInstant(category['startsAt']),
      ticketTypeName: _str(ticketType['name']),
      firstName: _str(participant['firstName']),
      lastName: _str(participant['lastName']),
      relation: _str(json['relation']),
      orderReference: _str(json['orderReference']),
      issuedAt: parseInstant(json['issuedAt']),
      kitState: kitStateOf(json['kit']),
    );
  }
}

/// `GET /me/event-registrations/:id/ticket` and the rotate answer (spec
/// §3.8.4). [qrPayload] is drawn as is.
class EventTicketPayload {
  const EventTicketPayload({
    required this.ticketId,
    this.displayCode = '',
    this.state = 'active',
    this.issuedAt,
    this.rotatedAt,
    this.token = '',
    this.qrPayload = '',
    this.event,
    this.categoryName = '',
    this.ticketTypeName = '',
    this.firstName = '',
    this.lastName = '',
    this.scanning = false,
    this.kitState,
    this.relation = '',
    this.purchaserFirstName,
  });

  final String ticketId;
  final String displayCode;
  final String state;
  final DateTime? issuedAt;
  final DateTime? rotatedAt;
  final String token;
  final String qrPayload;
  final EventSummary? event;
  final String categoryName;
  final String ticketTypeName;
  final String firstName;
  final String lastName;

  /// Mirrors `options.tickets.scanning` so the wording is right even with a
  /// stale options cache.
  final bool scanning;
  final String? kitState;

  /// `self` | `purchased` | `claimed` when the server says (informational).
  final String relation;
  final String? purchaserFirstName;

  bool get isActive => state == 'active';

  String get participantName =>
      [firstName, lastName].where((s) => s.trim().isNotEmpty).join(' ');

  /// Bought for someone else and not yet claimed: the viewer can hand it
  /// over until the claim (spec §3.8.5).
  bool get isHandover => relation == 'purchased';

  /// What to draw: the server's payload, else its token; empty draws nothing.
  String get drawn => qrPayload.isNotEmpty ? qrPayload : token;

  static EventTicketPayload fromJson(Map json) {
    final ticket = json['ticket'] is Map ? json['ticket'] as Map : const {};
    final category = json['category'] is Map
        ? json['category'] as Map
        : const {};
    final ticketType = json['ticketType'] is Map
        ? json['ticketType'] as Map
        : const {};
    final participant = json['participant'] is Map
        ? json['participant'] as Map
        : const {};
    return EventTicketPayload(
      ticketId: _str(ticket['id']),
      displayCode: _str(ticket['displayCode']),
      state: _opt(ticket['state']) ?? 'active',
      issuedAt: parseInstant(ticket['issuedAt']),
      rotatedAt: parseInstant(ticket['rotatedAt']),
      token: _str(json['token']),
      qrPayload: _str(json['qrPayload']),
      event: json['event'] is Map ? eventSummaryOf(json['event']) : null,
      categoryName: _str(category['name']),
      ticketTypeName: _str(ticketType['name']),
      firstName: _str(participant['firstName']),
      lastName: _str(participant['lastName']),
      scanning: json['scanning'] == true,
      kitState: kitStateOf(json['kit']),
      relation: _str(json['relation']),
      purchaserFirstName: _opt(json['purchaserFirstName']),
    );
  }
}

// ── On-device copy (spec §5.8) ────────────────────────────────────────────

/// The last successful ticket read per registration, in the same app-private
/// store the kept link tokens use (SharedPreferences; no new package).
///
/// Written on every successful read and after a rotation. Deleted on
/// sign-out, on a revoked or claimed-elsewhere answer, and 30 days after the
/// event. The code is a kit-handover bearer, not an access credential;
/// screenshots of the task switcher are not prevented. Nothing is logged.
class EventTicketCache {
  EventTicketCache._();

  static const prefix = 'events.ticket.';
  static const indexKey = 'events.ticket.index';

  /// How long a saved ticket outlives its event.
  static const keepAfterEvent = Duration(days: 30);

  /// Replaceable in tests.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Saves the server's own answer ([raw]) for [registrationId].
  static Future<void> put(
    String registrationId,
    Map<String, dynamic> raw, {
    DateTime? eventStartsAt,
  }) async {
    final p = await _prefs();
    if (p == null || registrationId.isEmpty) return;
    try {
      final now = clock();
      await p.setString(
        '$prefix$registrationId',
        jsonEncode({
          'savedAt': now.toUtc().toIso8601String(),
          'deleteAfter': (eventStartsAt ?? now)
              .add(keepAfterEvent)
              .toUtc()
              .toIso8601String(),
          'ticket': raw,
        }),
      );
      final index = (p.getStringList(indexKey) ?? [])..remove(registrationId);
      index.add(registrationId);
      await p.setStringList(indexKey, index);
    } catch (_) {}
  }

  /// The saved payload and when it was saved, or null (none, unreadable, or
  /// past its keep date, which also deletes it).
  static Future<({EventTicketPayload ticket, DateTime savedAt})?> get(
    String registrationId,
  ) async {
    final p = await _prefs();
    final raw = p?.getString('$prefix$registrationId');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map;
      final deleteAfter = DateTime.tryParse(m['deleteAfter']?.toString() ?? '');
      if (deleteAfter != null && clock().isAfter(deleteAfter)) {
        await remove(registrationId);
        return null;
      }
      final savedAt =
          DateTime.tryParse(m['savedAt']?.toString() ?? '') ?? clock();
      return (
        ticket: EventTicketPayload.fromJson(m['ticket'] as Map),
        savedAt: savedAt.toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String registrationId) async {
    final p = await _prefs();
    if (p == null) return;
    try {
      await p.remove('$prefix$registrationId');
      final index = (p.getStringList(indexKey) ?? [])..remove(registrationId);
      await p.setStringList(indexKey, index);
    } catch (_) {}
  }

  /// Sign-out: nothing of this member stays on the phone.
  static Future<void> clearAll() async {
    final p = await _prefs();
    if (p == null) return;
    try {
      for (final id in p.getStringList(indexKey) ?? const <String>[]) {
        await p.remove('$prefix$id');
      }
      await p.remove(indexKey);
      // Anything saved under the prefix but missing from the index.
      for (final k in p.getKeys().where((k) => k.startsWith(prefix)).toList()) {
        await p.remove(k);
      }
    } catch (_) {}
  }
}
