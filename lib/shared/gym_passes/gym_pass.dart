// Custom Gym Passes (phase 4): models and rules for the member app.
//
// Shapes follow docs/custom-gym-passes-api.md and functions/gym-passes.mjs in
// fitflex-functions (PR #355). The price is always the server's: nothing here
// computes one.

import '../api_client.dart';
import '../i18n.dart';

/// The three kinds of custom pass an owner can publish.
enum GymPassCategory {
  individual,
  couples,
  group;

  static GymPassCategory? parse(Object? v) => switch (v) {
    'individual' => GymPassCategory.individual,
    'couples' => GymPassCategory.couples,
    'group' => GymPassCategory.group,
    _ => null,
  };
}

/// One published plan (`GET /gyms/:id/pass-plans`).
class GymPassPlan {
  const GymPassPlan({
    required this.id,
    required this.gymId,
    required this.name,
    required this.category,
    required this.durationValue,
    required this.durationUnit,
    required this.beneficiaryLimit,
    required this.priceTzs,
    this.description,
    this.terms,
    this.termsVersion = 1,
  });

  final String id;
  final String gymId;
  final String name;
  final String? description;
  final GymPassCategory category;
  final int durationValue;

  /// `days` | `weeks` | `months`.
  final String durationUnit;

  /// People covered, the buyer included: individual 1, couples 2, group 3..50.
  final int beneficiaryLimit;
  final num priceTzs;
  final String? terms;
  final int termsVersion;

  /// The shape is the server's; a row the app cannot read is left out.
  static GymPassPlan? fromJson(Object? json) {
    if (json is! Map) return null;
    final category = GymPassCategory.parse(json['category']);
    final id = json['id']?.toString();
    final price = json['priceTzs'];
    final value = json['durationValue'];
    final unit = json['durationUnit']?.toString();
    final limit = json['beneficiaryLimit'];
    if (category == null ||
        id == null ||
        price is! num ||
        value is! num ||
        unit == null ||
        limit is! num) {
      return null;
    }
    String? text(Object? v) {
      final t = v?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    return GymPassPlan(
      id: id,
      gymId: json['gymId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: text(json['description']),
      category: category,
      durationValue: value.toInt(),
      durationUnit: unit,
      beneficiaryLimit: limit.toInt(),
      priceTzs: price,
      terms: text(json['terms']),
      termsVersion: (json['termsVersion'] as num?)?.toInt() ?? 1,
    );
  }

  /// Other people the buyer can name at checkout (the buyer holds slot 1).
  int get maxOthers => beneficiaryLimit - 1;

  /// The fewest other people the checkout accepts: individual none, couples
  /// exactly one, group two (three people with the buyer).
  int get minOthers => switch (category) {
    GymPassCategory.individual => 0,
    GymPassCategory.couples => 1,
    GymPassCategory.group => 2,
  };

  /// Whether the checkout asks for other people at all.
  bool get takesOthers => maxOthers > 0;
}

/// One person on a pass as the buyer (or the person) sees it.
class GymPassPerson {
  const GymPassPerson({
    required this.id,
    required this.slot,
    required this.isPurchaser,
    required this.status,
    required this.you,
    this.displayName,
    this.contactType,
    this.contact,
  });

  final String id;
  final int slot;
  final bool isPurchaser;

  /// awaiting_payment | invited | active | suspended | removed (and, for a
  /// server that sends it, pending_registration).
  final String status;
  final bool you;
  final String? displayName;
  final String? contactType;

  /// Masked by the server.
  final String? contact;

  static GymPassPerson? fromJson(Object? json) {
    if (json is! Map || json['id'] == null) return null;
    return GymPassPerson(
      id: json['id'].toString(),
      slot: (json['slot'] as num?)?.toInt() ?? 0,
      isPurchaser: json['isPurchaser'] == true,
      status: json['status']?.toString() ?? 'invited',
      you: json['you'] == true,
      displayName: json['displayName']?.toString(),
      contactType: json['contactType']?.toString(),
      contact: json['contact']?.toString(),
    );
  }

  bool get isRemoved => status == 'removed';
}

/// A pass I bought (`purchased[]` of `GET /me/gym-passes`).
class GymPassPurchase {
  const GymPassPurchase({
    required this.id,
    required this.status,
    required this.planName,
    required this.category,
    required this.limit,
    required this.used,
    required this.people,
    this.gymName,
    this.expiresAt,
    this.startsAt,
    this.priceTzs,
  });

  final String id;

  /// pending_payment | active | expired | cancelled.
  final String status;
  final String planName;
  final GymPassCategory? category;
  final String? gymName;
  final String? startsAt;
  final String? expiresAt;
  final num? priceTzs;
  final int limit;
  final int used;
  final List<GymPassPerson> people;

  static GymPassPurchase? fromJson(Object? json) {
    if (json is! Map || json['id'] == null) return null;
    final plan = json['plan'] is Map ? json['plan'] as Map : const {};
    final slots = json['slots'] is Map ? json['slots'] as Map : const {};
    final gym = json['gym'] is Map ? json['gym'] as Map : const {};
    return GymPassPurchase(
      id: json['id'].toString(),
      status: json['status']?.toString() ?? '',
      planName: plan['name']?.toString() ?? '',
      category: GymPassCategory.parse(plan['category']),
      gymName: gym['name']?.toString(),
      startsAt: json['startsAt']?.toString(),
      expiresAt: json['expiresAt']?.toString(),
      priceTzs: json['priceTzs'] as num?,
      limit:
          (slots['limit'] as num?)?.toInt() ??
          (plan['beneficiaryLimit'] as num?)?.toInt() ??
          0,
      used: (slots['used'] as num?)?.toInt() ?? 0,
      people: [
        for (final p in (json['beneficiaries'] as List? ?? const []))
          ?GymPassPerson.fromJson(p),
      ],
    );
  }

  bool get isActive => status == 'active';
  bool get isPendingPayment => status == 'pending_payment';

  /// People still on the pass (a removed person has left the list).
  List<GymPassPerson> get onPass => [
    for (final p in people)
      if (!p.isRemoved) p,
  ];

  /// A slot is free on a running pass (the add route needs this).
  bool get canAddPerson => isActive && limit > 0 && used < limit;
}

/// A pass I am covered by (`memberships[]`).
class GymPassMembership {
  const GymPassMembership({
    required this.purchaseId,
    required this.beneficiaryId,
    required this.status,
    required this.purchaseStatus,
    required this.planName,
    this.gymName,
    this.expiresAt,
  });

  final String purchaseId;
  final String beneficiaryId;

  /// active | suspended | pending_registration.
  final String status;
  final String purchaseStatus;
  final String planName;
  final String? gymName;
  final String? expiresAt;

  static GymPassMembership? fromJson(Object? json) {
    if (json is! Map || json['purchaseId'] == null) return null;
    final plan = json['plan'] is Map ? json['plan'] as Map : const {};
    final gym = json['gym'] is Map ? json['gym'] as Map : const {};
    return GymPassMembership(
      purchaseId: json['purchaseId'].toString(),
      beneficiaryId: json['beneficiaryId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      purchaseStatus: json['purchaseStatus']?.toString() ?? '',
      planName: plan['name']?.toString() ?? '',
      gymName: gym['name']?.toString(),
      expiresAt: json['expiresAt']?.toString(),
    );
  }

  bool get isRunning => purchaseStatus == 'active';
}

/// `GET /me/gym-passes`.
class GymPassesMine {
  const GymPassesMine({this.purchased = const [], this.memberships = const []});

  final List<GymPassPurchase> purchased;
  final List<GymPassMembership> memberships;

  bool get isEmpty => purchased.isEmpty && memberships.isEmpty;

  factory GymPassesMine.fromJson(Map<String, dynamic> json) => GymPassesMine(
    purchased: [
      for (final p in (json['purchased'] as List? ?? const []))
        ?GymPassPurchase.fromJson(p),
    ],
    memberships: [
      for (final m in (json['memberships'] as List? ?? const []))
        ?GymPassMembership.fromJson(m),
    ],
  );
}

/// Server 404 `feature_disabled`: the feature is off there. Treated as "not
/// available", never as an error to show.
bool isGymPassesUnavailable(Object error) =>
    error is ApiException &&
    error.status == 404 &&
    error.code == 'feature_disabled';

/// The label for a direct subscription: a custom pass shows its own name (or
/// a generic "Gym pass"); a legacy daily/weekly/monthly plan reads exactly as
/// before, including the old `monthly` fallback for a row with no plan.
String directSubscriptionLabel(
  FFLocale locale, {
  required String? plan,
  required String? passPurchaseId,
  String? passName,
}) {
  if (passPurchaseId != null && passPurchaseId.isNotEmpty) {
    final name = passName?.trim() ?? '';
    return name.isNotEmpty ? name : locale.t('gymPass.genericLabel');
  }
  return locale.t('member.plan_${plan ?? 'monthly'}');
}

/// A typed contact as the add / checkout routes take it: `{phone}` or
/// `{email}`. Null when it is neither (nothing is sent).
Map<String, String>? gymPassContactBody(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text.contains('@')) {
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(text);
    return ok ? {'email': text} : null;
  }
  final digits = text.replaceAll(RegExp(r'[\s\-().]'), '');
  final ok = RegExp(r'^\+?\d{9,15}$').hasMatch(digits);
  return ok ? {'phone': digits} : null;
}

/// One typed contact, reduced so the same person typed twice can be spotted
/// before the request (the server makes the final call).
String gymPassContactKey(String raw) {
  final body = gymPassContactBody(raw);
  if (body == null) return raw.trim().toLowerCase();
  final email = body['email'];
  if (email != null) return 'email:${email.toLowerCase()}';
  var d = body['phone']!;
  if (d.startsWith('+')) d = d.substring(1);
  if (d.startsWith('255')) d = d.substring(3);
  if (d.startsWith('0')) d = d.substring(1);
  return 'phone:$d';
}

/// A refused gym-pass request in the member's words. Contract errors
/// (docs/custom-gym-passes-api.md): the generic `invalid_beneficiaries`
/// (never says why: nobody learns whether a contact has an account),
/// `cannot_add_person`, `rate_limited` with its wait, and the rest.
/// Anything else falls back to the shared mapping.
String gymPassErrorMessage(
  FFLocale locale,
  Object error,
  String Function(FFLocale, Object) fallback,
) {
  if (error is ApiException) {
    final body = error.body is Map ? error.body as Map : const {};
    switch (error.code) {
      case 'invalid_beneficiaries':
        return locale.t('gymPass.error.invalidBeneficiaries');
      case 'cannot_add_person':
        return locale.t('gymPass.error.cannotAddPerson');
      case 'rate_limited':
        final s = body['retryAfterSeconds'];
        final n = s is num ? s.ceil() : int.tryParse('${s ?? ''}');
        if (n == null || n <= 0) return locale.t('gymPass.error.rateLimited');
        return locale
            .t('gymPass.error.rateLimitedSeconds')
            .replaceFirst('{time}', gymPassWaitLabel(locale, n));
      case 'too_soon':
        return locale.t('gymPass.error.tooSoon');
      case 'removed_by_owner':
        return locale.t('gymPass.error.removedByOwner');
      case 'suspended_by_other':
        return locale.t('gymPass.error.suspendedByOther');
      case 'replacement_limit_reached':
        return locale.t('gymPass.error.replacementLimit');
      case 'beneficiary_limit_exceeded':
        return locale.t('gymPass.error.limitExceeded');
      case 'duplicate_beneficiary':
      case 'cannot_add_yourself':
      case 'invalid_contact':
        return locale.t('gymPass.error.contactProblem');
      case 'beneficiaries_not_allowed':
      case 'couples_needs_two_people':
      case 'group_needs_minimum':
        return locale.t('gymPass.error.headcount');
      case 'plan_not_available':
      case 'plan_not_found':
      case 'gym_not_available':
      case 'gym_not_found':
        return locale.t('gymPass.error.planUnavailable');
      case 'terms_changed':
      case 'terms_not_accepted':
        return locale.t('gymPass.error.termsChanged');
      case 'payment_already_pending':
        return locale.t('gymPass.error.paymentPending');
      case 'pass_not_active':
        return locale.t('gymPass.error.passNotActive');
      case 'invalid_transition':
        return locale.t('gymPass.error.invalidTransition');
      case 'cannot_remove_purchaser':
        return locale.t('gymPass.error.cannotRemoveBuyer');
      case 'feature_disabled':
        return locale.t('gymPass.error.unavailable');
    }
  }
  return fallback(locale, error);
}

/// "45 seconds", "12 minutes" for a 429 wait.
String gymPassWaitLabel(FFLocale locale, int seconds) {
  if (seconds < 90) {
    return locale.t('gymPass.wait.seconds').replaceFirst('{n}', '$seconds');
  }
  final minutes = (seconds / 60).ceil();
  return locale.t('gymPass.wait.minutes').replaceFirst('{n}', '$minutes');
}

/// "30 days", "1 week", "3 months" (plural keys per unit).
String gymPassDurationLabel(FFLocale locale, GymPassPlan plan) {
  final unit = plan.durationUnit;
  final one = plan.durationValue == 1;
  final key = switch (unit) {
    'days' => one ? 'gymPass.duration.day' : 'gymPass.duration.days',
    'weeks' => one ? 'gymPass.duration.week' : 'gymPass.duration.weeks',
    'months' => one ? 'gymPass.duration.month' : 'gymPass.duration.months',
    _ => 'gymPass.duration.days',
  };
  return locale.t(key).replaceFirst('{n}', '${plan.durationValue}');
}

/// "Individual", "Couples" or "Group of up to {n}".
String gymPassCategoryLabel(FFLocale locale, GymPassPlan plan) =>
    switch (plan.category) {
      GymPassCategory.individual => locale.t('gymPass.category.individual'),
      GymPassCategory.couples => locale.t('gymPass.category.couples'),
      GymPassCategory.group =>
        locale
            .t('gymPass.category.group')
            .replaceFirst('{n}', '${plan.beneficiaryLimit}'),
    };
