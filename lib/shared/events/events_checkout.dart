// Events S3: what the register flow sends and checks before the server does
// (spec §3.3, §3.11, §5.5, §5.6). The server is the judge; these local rules
// only catch what is certainly wrong so the member fixes it before step 4.
import 'dart:convert';

import '../api_client.dart';
import '../date_of_birth.dart';
import '../shop_checkout.dart';
import 'event_order.dart';
import 'event_time.dart';

/// `consentBasis` values on the wire (§3.3).
const consentSelf = 'self';
const consentPurchaserAuthorised = 'purchaser_authorised';

/// One person in the order, as typed. [ticketTypeId] / [categoryId] come
/// from the ticket picker; the rest from the participant card.
class EventParticipantInput {
  EventParticipantInput({
    required this.ticketTypeId,
    required this.categoryId,
    this.isSelf = false,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.email = '',
    this.dateOfBirth = '',
    this.gender = '',
    this.emergencyName = '',
    this.emergencyPhone = '',
    this.kitSize = '',
    this.consented = false,
  });

  final String ticketTypeId;
  final String categoryId;
  bool isSelf;
  String firstName;
  String lastName;
  String phone;
  String email;

  /// `YYYY-MM-DD` or empty.
  String dateOfBirth;
  String gender;
  String emergencyName;
  String emergencyPhone;
  String kitSize;

  /// The per-card consent checkbox (others only; self is implied by the
  /// terms checkbox on step 4).
  bool consented;

  String get consentBasis => isSelf ? consentSelf : consentPurchaserAuthorised;

  bool get hasEmergencyContact =>
      emergencyName.trim().isNotEmpty || emergencyPhone.trim().isNotEmpty;

  /// The wire shape (§3.3). Fields the event does not collect are left
  /// out; empty optional fields are left out too.
  Map<String, dynamic> toJson(ParticipantFields fields) => {
    'ticketTypeId': ticketTypeId,
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
    if (fields.phone != FieldPolicy.off && phone.trim().isNotEmpty)
      'phone': phone.trim(),
    if (fields.email != FieldPolicy.off && email.trim().isNotEmpty)
      'email': email.trim(),
    if (fields.dateOfBirth != FieldPolicy.off && dateOfBirth.trim().isNotEmpty)
      'dateOfBirth': dateOfBirth.trim(),
    if (fields.gender != FieldPolicy.off && gender.isNotEmpty) 'gender': gender,
    if (fields.emergencyContact != FieldPolicy.off && hasEmergencyContact)
      'emergencyContact': {
        'name': emergencyName.trim(),
        'phone': emergencyPhone.trim(),
      },
    if (fields.kitSize != FieldPolicy.off && kitSize.isNotEmpty)
      'kitSize': kitSize,
    'consentBasis': consentBasis,
  };

  Map<String, dynamic> toDraftJson() => {
    'ticketTypeId': ticketTypeId,
    'categoryId': categoryId,
    'isSelf': isSelf,
    'firstName': firstName,
    'lastName': lastName,
    'phone': phone,
    'email': email,
    'dateOfBirth': dateOfBirth,
    'gender': gender,
    'emergencyName': emergencyName,
    'emergencyPhone': emergencyPhone,
    'kitSize': kitSize,
    'consented': consented,
  };

  static EventParticipantInput fromDraftJson(Map json) => EventParticipantInput(
    ticketTypeId: json['ticketTypeId']?.toString() ?? '',
    categoryId: json['categoryId']?.toString() ?? '',
    isSelf: json['isSelf'] == true,
    firstName: json['firstName']?.toString() ?? '',
    lastName: json['lastName']?.toString() ?? '',
    phone: json['phone']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    dateOfBirth: json['dateOfBirth']?.toString() ?? '',
    gender: json['gender']?.toString() ?? '',
    emergencyName: json['emergencyName']?.toString() ?? '',
    emergencyPhone: json['emergencyPhone']?.toString() ?? '',
    kitSize: json['kitSize']?.toString() ?? '',
    consented: json['consented'] == true,
  );
}

/// The team part of a quote / order body (§3.4), or null for none.
class TeamChoice {
  const TeamChoice.create({required this.name, required this.teamType})
    : joinCode = null;
  const TeamChoice.join(this.joinCode) : name = null, teamType = null;

  final String? name;
  final String? teamType;
  final String? joinCode;

  bool get isCreate => joinCode == null;

  Map<String, dynamic> toJson() => isCreate
      ? {
          'create': {'name': name!.trim(), 'teamType': teamType},
        }
      : {'joinCode': normalizeTeamCode(joinCode!)};

  Map<String, dynamic> toDraftJson() => {
    'name': name,
    'teamType': teamType,
    'joinCode': joinCode,
  };

  static TeamChoice? fromDraftJson(Object? json) {
    if (json is! Map) return null;
    final code = json['joinCode']?.toString();
    if (code != null && code.isNotEmpty) return TeamChoice.join(code);
    final name = json['name']?.toString();
    if (name == null || name.isEmpty) return null;
    return TeamChoice.create(
      name: name,
      teamType: json['teamType']?.toString() ?? 'community',
    );
  }
}

// ── Team codes (§3.9) ────────────────────────────────────────────────────

/// "ab12-cd34" → "AB12CD34": case-insensitive, dash and spaces dropped.
String normalizeTeamCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// "AB12CD34" → "AB12-CD34" (shown grouped).
String formatTeamCode(String raw) {
  final c = normalizeTeamCode(raw);
  if (c.length <= 4) return c;
  return '${c.substring(0, 4)}-${c.substring(4)}';
}

/// A well-formed code: 8 letters / digits. The server's alphabet (§3.9,
/// no 0/O/1/I) is not enforced here — the spec's own example "AB12-CD34"
/// carries a 1, so the lookup route is the judge.
bool teamCodeLooksValid(String raw) => normalizeTeamCode(raw).length == 8;

// ── Local validation (§3.11 subset, §5.5) ────────────────────────────────

final _nameShape = RegExp(r'^[^0-9@]{1,80}$');
final _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Loose local check matching what `normalizePhone` accepts: local `07…` /
/// `06…` or `+255…` with 9–15 digits.
bool phoneLooksValid(String raw) {
  final digits = raw.replaceAll(RegExp(r'[\s\-()]'), '');
  return RegExp(r'^(\+?[1-9]\d{8,14}|0\d{8,9})$').hasMatch(digits);
}

/// Digits only, with a leading local `0` read as `+255` so two spellings
/// of one number compare equal (`listed_twice`).
String phoneKey(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.startsWith('+')) d = d.substring(1);
  if (d.startsWith('0') && d.length >= 9) d = '255${d.substring(1)}';
  return d;
}

String emailKey(String raw) => raw.trim().toLowerCase();

/// Whole years between [dob] and [eventDay] on the calendar (a birthday on
/// event day counts; §3.11).
int ageOn(DateTime dob, DateTime eventDay) {
  var age = eventDay.year - dob.year;
  if (eventDay.month < dob.month ||
      (eventDay.month == dob.month && eventDay.day < dob.day)) {
    age--;
  }
  return age;
}

/// Problems with one participant that the server would certainly report,
/// keyed by field. Codes are the server's (§3.11) so the same i18n keys
/// apply. [eventStartUtc] / [offsetMinutes] give the event day for the age
/// rule; [minAge] is the category's.
Map<String, FieldProblem> validateParticipantLocally(
  EventParticipantInput p, {
  required ParticipantFields fields,
  int? minAge,
  DateTime? eventStartUtc,
  int offsetMinutes = 0,
  DateTime? now,
}) {
  final out = <String, FieldProblem>{};
  void problem(String field, String code, [Map<String, dynamic>? extra]) =>
      out.putIfAbsent(
        field,
        () => FieldProblem(field: field, code: code, extra: extra),
      );

  for (final (field, value) in [
    ('firstName', p.firstName),
    ('lastName', p.lastName),
  ]) {
    final v = value.trim();
    if (v.isEmpty) {
      problem(field, 'required');
    } else if (!_nameShape.hasMatch(v)) {
      problem(field, 'name_invalid');
    }
  }

  final phone = p.phone.trim();
  final email = p.email.trim();
  if (fields.phone == FieldPolicy.required && phone.isEmpty) {
    problem('phone', 'required');
  } else if (phone.isNotEmpty && !phoneLooksValid(phone)) {
    problem('phone', 'phone_invalid');
  }
  if (fields.email == FieldPolicy.required && email.isEmpty) {
    problem('email', 'required');
  } else if (email.isNotEmpty && !_emailShape.hasMatch(email)) {
    problem('email', 'email_invalid');
  }
  if (!p.isSelf &&
      fields.phone != FieldPolicy.off &&
      fields.email != FieldPolicy.off &&
      phone.isEmpty &&
      email.isEmpty) {
    problem('phone', 'contact_required');
  }

  if (fields.dateOfBirth != FieldPolicy.off) {
    final dob = p.dateOfBirth.trim();
    if (dob.isEmpty) {
      if (fields.dateOfBirth == FieldPolicy.required || minAge != null) {
        problem('dateOfBirth', minAge != null ? 'dob_required' : 'required');
      }
    } else if (dateOfBirthProblemKey(dob, now: now) != null) {
      problem('dateOfBirth', 'dob_invalid');
    } else if (minAge != null && eventStartUtc != null) {
      final day = eventClock(eventStartUtc, offsetMinutes);
      final age = ageOn(parseDateOfBirth(dob)!, day);
      if (age < minAge) {
        problem('dateOfBirth', 'age_not_eligible', {
          'minAge': minAge,
          'ageOnEventDay': age,
        });
      }
    }
  }

  if (fields.gender == FieldPolicy.required && p.gender.isEmpty) {
    problem('gender', 'required');
  } else if (p.gender.isNotEmpty && !participantGenders.contains(p.gender)) {
    problem('gender', 'gender_invalid');
  }

  if (fields.kitSize == FieldPolicy.required && p.kitSize.isEmpty) {
    problem('kitSize', 'required');
  } else if (p.kitSize.isNotEmpty && !kitSizes.contains(p.kitSize)) {
    problem('kitSize', 'kit_size_invalid');
  }

  if (fields.emergencyContact != FieldPolicy.off) {
    final name = p.emergencyName.trim();
    final ph = p.emergencyPhone.trim();
    if (fields.emergencyContact == FieldPolicy.required &&
        name.isEmpty &&
        ph.isEmpty) {
      problem('emergencyContact', 'required');
    } else if ((name.isNotEmpty || ph.isNotEmpty) &&
        (name.isEmpty || !phoneLooksValid(ph))) {
      problem('emergencyContact', 'emergency_contact_invalid');
    }
  }

  if (!p.isSelf && !p.consented) problem('consent', 'required');
  return out;
}

/// Indexes of participants whose phone or email also appears on another
/// participant in the same category (`listed_twice`).
Set<int> listedTwice(List<EventParticipantInput> list) {
  final out = <int>{};
  for (var i = 0; i < list.length; i++) {
    for (var j = i + 1; j < list.length; j++) {
      if (list[i].categoryId != list[j].categoryId) continue;
      final a = list[i], b = list[j];
      final samePhone =
          a.phone.trim().isNotEmpty && phoneKey(a.phone) == phoneKey(b.phone);
      final sameEmail =
          a.email.trim().isNotEmpty && emailKey(a.email) == emailKey(b.email);
      if (samePhone || sameEmail) out.addAll([i, j]);
    }
  }
  return out;
}

// ── Request body and idempotency (§3.4, §3.5, §5.6) ──────────────────────

/// The quote / order body. Keys are sorted at every level so the same
/// choices always serialise the same way (the signature below).
Map<String, dynamic> registrationBody({
  required String eventId,
  required Map<String, int> lines,
  required List<EventParticipantInput> participants,
  required ParticipantFields fields,
  TeamChoice? team,
}) => {
  'eventId': eventId,
  'lines': [
    for (final e in lines.entries)
      if (e.value > 0) {'ticketTypeId': e.key, 'quantity': e.value},
  ],
  'participants': [for (final p in participants) p.toJson(fields)],
  if (team != null) 'team': team.toJson(),
};

Object? _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canonical(v[k])};
  }
  if (v is List) return [for (final e in v) _canonical(e)];
  return v;
}

/// Canonical JSON (sorted keys) of the order body: what the server
/// fingerprints under the `Idempotency-Key`, so an edit yields a new key
/// through [CheckoutAttempt.forPurchase].
String registrationSignature(Map<String, dynamic> body) =>
    jsonEncode(_canonical(body));

/// The i18n key for a refused quote / order, or null for the generic copy.
String? eventsOrderErrorKey(Object error) {
  if (error is! ApiException) return null;
  return switch (error.code) {
    'price_changed' => 'events.review.priceChanged',
    'participant_invalid' => 'events.review.fix',
    _ => null,
  };
}

/// True when the order may have been created although the answer was lost.
bool eventOrderOutcomeUnknown(Object error) => orderOutcomeUnknown(error);
