// Events S3 (spec §5.5): a registration started but not placed is kept on
// this device only (SharedPreferences, 7 days), never synced. Cleared when
// the order is placed, on "Start over", and when the event refuses it.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'events_checkout.dart';

class RegistrationDraft {
  RegistrationDraft({
    required this.eventId,
    required this.savedAt,
    this.step = 1,
    this.lines = const {},
    this.mode = '',
    this.team,
    this.participants = const [],
  });

  final String eventId;
  final DateTime savedAt;
  final int step;

  /// ticketTypeId → quantity.
  final Map<String, int> lines;

  /// `self` | `selfOthers` | `others`.
  final String mode;
  final TeamChoice? team;
  final List<EventParticipantInput> participants;

  int get placesCount => lines.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'step': step,
    'lines': lines,
    'mode': mode,
    'team': team?.toDraftJson(),
    'participants': [for (final p in participants) p.toDraftJson()],
  };

  static RegistrationDraft? fromJson(Object? json) {
    if (json is! Map) return null;
    final savedAt = DateTime.tryParse(json['savedAt']?.toString() ?? '');
    final eventId = json['eventId']?.toString() ?? '';
    if (savedAt == null || eventId.isEmpty) return null;
    return RegistrationDraft(
      eventId: eventId,
      savedAt: savedAt.toUtc(),
      step: json['step'] is num ? (json['step'] as num).toInt() : 1,
      lines: json['lines'] is Map
          ? {
              for (final e in (json['lines'] as Map).entries)
                if (e.value is num) e.key.toString(): (e.value as num).toInt(),
            }
          : const {},
      mode: json['mode']?.toString() ?? '',
      team: TeamChoice.fromDraftJson(json['team']),
      participants: json['participants'] is List
          ? [
              for (final p in json['participants'] as List)
                if (p is Map) EventParticipantInput.fromDraftJson(p),
            ]
          : const [],
    );
  }
}

class RegistrationDraftStore {
  RegistrationDraftStore._();

  static const prefix = 'events.registrationDraft.';
  static const maxAge = Duration(days: 7);

  /// Replaceable in tests.
  static DateTime Function() clock = DateTime.now;

  static String keyFor(String eventId) => '$prefix$eventId';

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// The kept draft for [eventId], or null when none or older than 7 days
  /// (an old one is dropped).
  static Future<RegistrationDraft?> load(String eventId) async {
    final p = await _prefs();
    final raw = p?.getString(keyFor(eventId));
    if (raw == null) return null;
    RegistrationDraft? draft;
    try {
      draft = RegistrationDraft.fromJson(jsonDecode(raw));
    } catch (_) {
      draft = null;
    }
    if (draft == null || clock().toUtc().difference(draft.savedAt) > maxAge) {
      await p?.remove(keyFor(eventId));
      return null;
    }
    return draft;
  }

  static Future<void> save(RegistrationDraft draft) async {
    final p = await _prefs();
    try {
      await p?.setString(keyFor(draft.eventId), jsonEncode(draft.toJson()));
    } catch (_) {}
  }

  static Future<void> clear(String eventId) async {
    final p = await _prefs();
    try {
      await p?.remove(keyFor(eventId));
    } catch (_) {}
  }
}
