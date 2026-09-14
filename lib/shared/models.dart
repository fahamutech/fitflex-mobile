// Typed data models matching the portal's TypeScript interfaces in api.ts.
// Keeps the mobile app aligned with the backend/portal data contract.

class Gym {
  final String id;
  final String name;
  final String tier;
  final String location;
  final num perVisitRate;
  final num? ratePerDay;
  final num? ratePerWeek;
  final num? ratePerMonth;
  final num commissionRate;
  final String status;
  final String? accessMode;
  final String? venueType;
  final bool isVerified;
  final String? verificationStatus;
  final double? latitude;
  final double? longitude;
  final List<String> images;

  /// Small WebP previews, parallel to [images] (same index = same photo).
  final List<String> thumbnails;
  final List<String> amenities;
  final List<String> equipment;

  Gym({
    required this.id,
    required this.name,
    required this.tier,
    required this.location,
    required this.perVisitRate,
    this.ratePerDay,
    this.ratePerWeek,
    this.ratePerMonth,
    required this.commissionRate,
    required this.status,
    this.accessMode,
    this.venueType,
    this.isVerified = false,
    this.verificationStatus,
    this.latitude,
    this.longitude,
    this.images = const [],
    this.thumbnails = const [],
    this.amenities = const [],
    this.equipment = const [],
  });

  factory Gym.fromJson(Map<String, dynamic> json) {
    final coordinates = json['coordinates'];
    final lat =
        _coordinateValue(json['lat']) ??
        (coordinates is Map ? _coordinateValue(coordinates['lat']) : null) ??
        (coordinates is List && coordinates.isNotEmpty
            ? _coordinateValue(coordinates[0])
            : null);
    final lng =
        _coordinateValue(json['lng']) ??
        _coordinateValue(json['longitude']) ??
        (coordinates is Map
            ? _coordinateValue(coordinates['lng']) ??
                  _coordinateValue(coordinates['longitude'])
            : null) ??
        (coordinates is List && coordinates.length > 1
            ? _coordinateValue(coordinates[1])
            : null);

    return Gym(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      tier: json['tier'] as String? ?? '',
      location: json['location'] as String? ?? '',
      perVisitRate: json['perVisitRate'] as num? ?? 0,
      ratePerDay: json['ratePerDay'] as num?,
      ratePerWeek: json['ratePerWeek'] as num?,
      ratePerMonth: json['ratePerMonth'] as num?,
      commissionRate: json['commissionRate'] as num? ?? 0,
      status: json['status'] as String? ?? 'active',
      accessMode: json['accessMode'] as String?,
      venueType: json['venueType'] as String?,
      isVerified: _boolValue(json['isVerified'] ?? json['verified']),
      verificationStatus: json['verificationStatus'] as String?,
      latitude: lat,
      longitude: lng,
      images: (json['images'] as List?)?.whereType<String>().toList() ?? [],
      thumbnails:
          (json['thumbnails'] as List?)?.whereType<String>().toList() ?? [],
      amenities:
          (json['amenities'] as List?)?.whereType<String>().toList() ?? [],
      equipment:
          (json['equipment'] as List?)?.whereType<String>().toList() ?? [],
    );
  }

  bool get isFreeOnline => accessMode == 'free_online';
  bool get isPaidVisit => accessMode == 'paid_visit';
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Small preview image for cards/lists — falls back to the full image for
  /// gyms created before thumbnails existed.
  String? get coverThumbnail =>
      thumbnails.isNotEmpty ? thumbnails.first : images.firstOrNull;
}

double? _coordinateValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return false;
}

class TrainerProfile {
  final String id;
  final String? userId;
  final String? email;
  final String displayName;
  final String? photoUrl;
  final List<String> specialties;
  final String? bio;
  final num? rating;
  final int? reviewCount;
  final num hourlyRateTzs;
  final String sessionRateCurrency;
  final int? experienceYears;
  final List<String> gymIds;
  final List<Gym> gyms;
  final String status;
  final String? approvalStatus;
  final bool isVerified;
  final List<TrainerAvailability> availability;

  TrainerProfile({
    required this.id,
    this.userId,
    this.email,
    required this.displayName,
    this.photoUrl,
    this.specialties = const [],
    this.bio,
    this.rating,
    this.reviewCount,
    required this.hourlyRateTzs,
    this.sessionRateCurrency = 'TZS',
    this.experienceYears,
    this.gymIds = const [],
    this.gyms = const [],
    required this.status,
    this.approvalStatus,
    this.isVerified = false,
    this.availability = const [],
  });

  factory TrainerProfile.fromJson(Map<String, dynamic> json) => TrainerProfile(
    id: json['id'] as String? ?? '',
    userId: json['userId'] as String?,
    email: json['email'] as String?,
    displayName: json['displayName'] as String? ?? '',
    photoUrl: json['photoUrl'] as String?,
    specialties:
        (json['specialties'] as List?)?.whereType<String>().toList() ?? [],
    bio: json['bio'] as String?,
    rating: json['rating'] as num?,
    reviewCount: json['reviewCount'] as int?,
    hourlyRateTzs: json['hourlyRateTzs'] as num? ?? 0,
    sessionRateCurrency: json['sessionRateCurrency'] as String? ?? 'TZS',
    experienceYears: json['experienceYears'] as int?,
    gymIds: (json['gymIds'] as List?)?.whereType<String>().toList() ?? [],
    gyms:
        (json['gyms'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(Gym.fromJson)
            .toList() ??
        [],
    status: json['status'] as String? ?? 'active',
    approvalStatus: json['approvalStatus'] as String?,
    isVerified: _boolValue(json['isVerified'] ?? json['verified']),
    availability: _trainerAvailabilityFromJson(json['availability']),
  );
}

List<TrainerAvailability> _trainerAvailabilityFromJson(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) => TrainerAvailability.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList();
}

class TrainerAvailability {
  /// Day of week (e.g. 'monday', 'tuesday') or legacy date string (e.g. '2026-05-05').
  final String day;

  /// Gym ID where the trainer is available, null if any gym.
  final String? gymId;

  /// Gym name (resolved on read), null if not hydrated.
  final String? gymName;

  /// Time slots available on this day at this gym.
  final List<String> slots;

  TrainerAvailability({
    required this.day,
    this.gymId,
    this.gymName,
    required this.slots,
  });

  factory TrainerAvailability.fromJson(Map<String, dynamic> json) =>
      TrainerAvailability(
        day: json['day'] as String? ?? json['date'] as String? ?? '',
        gymId: json['gymId'] as String?,
        gymName: json['gymName'] as String?,
        slots: (json['slots'] as List?)?.whereType<String>().toList() ?? [],
      );

  /// Human-readable label for the day.
  String get dayLabel {
    final d = day.toLowerCase();
    const dayNames = {
      'monday': 'Monday',
      'tuesday': 'Tuesday',
      'wednesday': 'Wednesday',
      'thursday': 'Thursday',
      'friday': 'Friday',
      'saturday': 'Saturday',
      'sunday': 'Sunday',
    };
    return dayNames[d] ?? day;
  }
}

class MemberProfile {
  final String? fitnessGoal;
  final List<String> fitnessGoals;
  final String? fitnessLevel;
  final num? heightCm;
  final num? weightKg;
  final String? dateOfBirth;
  final String? gender;
  final List<String> preferredWorkoutTimes;

  MemberProfile({
    this.fitnessGoal,
    this.fitnessGoals = const [],
    this.fitnessLevel,
    this.heightCm,
    this.weightKg,
    this.dateOfBirth,
    this.gender,
    this.preferredWorkoutTimes = const [],
  });

  factory MemberProfile.fromJson(Map<String, dynamic> json) => MemberProfile(
    fitnessGoal: json['fitnessGoal'] as String?,
    fitnessGoals:
        (json['fitnessGoals'] as List?)?.whereType<String>().toList() ??
        const [],
    fitnessLevel: json['fitnessLevel'] as String?,
    heightCm: json['heightCm'] as num?,
    weightKg: json['weightKg'] as num?,
    dateOfBirth: json['dateOfBirth'] as String?,
    gender: json['gender'] as String?,
    preferredWorkoutTimes:
        (json['preferredWorkoutTimes'] as List?)
            ?.whereType<String>()
            .toList() ??
        [],
  );
}

class MemberSummary {
  final String id;
  final String? email;
  final String? phone;
  final String? displayName;
  final String? photoUrl;
  final String? publicId;
  final String userType;
  final String? accountStatus;
  final MemberProfile? memberProfile;
  final Subscription? subscription;
  final PaymentRequest? pendingPayment;
  final bool? onboardingCompleted;

  MemberSummary({
    required this.id,
    this.email,
    this.phone,
    this.displayName,
    this.photoUrl,
    this.publicId,
    required this.userType,
    this.accountStatus,
    this.memberProfile,
    this.subscription,
    this.pendingPayment,
    this.onboardingCompleted,
  });

  factory MemberSummary.fromJson(Map<String, dynamic> json) => MemberSummary(
    id: json['id'] as String? ?? '',
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    displayName: json['displayName'] as String?,
    photoUrl: json['photoUrl'] as String?,
    publicId: json['publicId'] as String? ?? json['userCode'] as String?,
    userType: json['userType'] as String? ?? 'member',
    accountStatus: json['accountStatus'] as String?,
    memberProfile: json['memberProfile'] is Map<String, dynamic>
        ? MemberProfile.fromJson(json['memberProfile'] as Map<String, dynamic>)
        : null,
    subscription: json['subscription'] is Map<String, dynamic>
        ? Subscription.fromJson(json['subscription'] as Map<String, dynamic>)
        : null,
    pendingPayment: json['pendingPayment'] is Map<String, dynamic>
        ? PaymentRequest.fromJson(
            json['pendingPayment'] as Map<String, dynamic>,
          )
        : null,
    onboardingCompleted: json['onboardingCompleted'] as bool?,
  );

  String get resolvedName =>
      displayName ?? email ?? phone ?? publicId ?? 'Member';
}

class Subscription {
  final String? id;
  final String? type;
  final String? tier;

  /// Direct-sub plan: 'daily' | 'weekly' | 'monthly' (null for platform pass).
  final String? plan;
  final String status;
  final String? startedAt;
  final String? renewsAt;
  final String? expiresAt;
  final String? homeGymId;

  /// The subscribed gym for direct subscriptions (A3), hydrated by /me.
  final Gym? homeGym;

  Subscription({
    this.id,
    this.type,
    this.tier,
    this.plan,
    required this.status,
    this.startedAt,
    this.renewsAt,
    this.expiresAt,
    this.homeGymId,
    this.homeGym,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
    id: json['id'] as String?,
    type: json['type'] as String?,
    tier: json['tier'] as String?,
    plan: json['plan'] as String?,
    status: json['status'] as String? ?? 'inactive',
    startedAt: json['startedAt'] as String?,
    renewsAt: json['renewsAt'] as String?,
    expiresAt: json['expiresAt'] as String?,
    homeGymId: json['homeGymId'] as String?,
    homeGym: json['homeGym'] is Map<String, dynamic>
        ? Gym.fromJson(json['homeGym'] as Map<String, dynamic>)
        : null,
  );

  bool get isActive => status == 'active';
  bool get isDirect => type == 'direct_sub';

  DateTime? get expiryDate =>
      expiresAt == null ? null : DateTime.tryParse(expiresAt!);

  /// Whole days remaining until expiry (negative when already expired).
  int? get daysLeft {
    final expiry = expiryDate;
    if (expiry == null) return null;
    return expiry.difference(DateTime.now()).inHours ~/ 24;
  }

  bool get isExpired {
    if (status == 'expired') return true;
    final expiry = expiryDate;
    return expiry != null && DateTime.now().isAfter(expiry);
  }
}

class PaymentRequest {
  final String id;
  final String memberId;
  final String subscriptionId;
  final String tier;
  final num amountTzs;
  final String status;
  final String provider;
  final String? reference;
  final String? note;
  final String requestedAt;
  final String? decidedAt;

  PaymentRequest({
    required this.id,
    required this.memberId,
    required this.subscriptionId,
    required this.tier,
    required this.amountTzs,
    required this.status,
    required this.provider,
    this.reference,
    this.note,
    required this.requestedAt,
    this.decidedAt,
  });

  factory PaymentRequest.fromJson(Map<String, dynamic> json) => PaymentRequest(
    id: json['id'] as String? ?? '',
    memberId: json['memberId'] as String? ?? '',
    subscriptionId: json['subscriptionId'] as String? ?? '',
    tier: json['tier'] as String? ?? '',
    amountTzs: json['amountTzs'] as num? ?? 0,
    status: json['status'] as String? ?? 'pending',
    provider: json['provider'] as String? ?? '',
    reference: json['reference'] as String?,
    note: json['note'] as String?,
    requestedAt: json['requestedAt'] as String? ?? '',
    decidedAt: json['decidedAt'] as String?,
  );
}

class CheckIn {
  final String id;
  final String memberId;
  final String? memberPhone;
  final String? memberEmail;
  final String timestamp;
  final String? passTier;
  final int? visitNumberInCycle;
  final String gymTier;
  final Gym? gym;
  final String? gymId;

  CheckIn({
    required this.id,
    required this.memberId,
    this.memberPhone,
    this.memberEmail,
    required this.timestamp,
    this.passTier,
    this.visitNumberInCycle,
    required this.gymTier,
    this.gym,
    this.gymId,
  });

  factory CheckIn.fromJson(Map<String, dynamic> json) => CheckIn(
    id: json['id'] as String? ?? '',
    memberId: json['memberId'] as String? ?? '',
    memberPhone: json['memberPhone'] as String?,
    memberEmail: json['memberEmail'] as String?,
    timestamp: json['timestamp'] as String? ?? '',
    passTier: json['passTier'] as String?,
    visitNumberInCycle: json['visitNumberInCycle'] as int?,
    gymTier: json['gymTier'] as String? ?? '',
    gym: json['gym'] is Map<String, dynamic>
        ? Gym.fromJson(json['gym'] as Map<String, dynamic>)
        : null,
    gymId: json['gymId'] as String?,
  );
}

class TrainerBooking {
  final String id;
  final String memberId;
  final String trainerId;
  final String gymId;
  final String date;
  final String slot;
  final num amountTzs;
  final String status;
  final String? createdAt;

  TrainerBooking({
    required this.id,
    required this.memberId,
    required this.trainerId,
    required this.gymId,
    required this.date,
    required this.slot,
    required this.amountTzs,
    required this.status,
    this.createdAt,
  });

  factory TrainerBooking.fromJson(Map<String, dynamic> json) => TrainerBooking(
    id: json['id'] as String? ?? '',
    memberId: json['memberId'] as String? ?? '',
    trainerId: json['trainerId'] as String? ?? '',
    gymId: json['gymId'] as String? ?? '',
    date: json['date'] as String? ?? '',
    slot: json['slot'] as String? ?? '',
    amountTzs: json['amountTzs'] as num? ?? 0,
    status: json['status'] as String? ?? 'confirmed',
    createdAt: json['createdAt'] as String?,
  );
}

/// Response from /me endpoint — matches portal's MemberMeResponse.
class MemberMeResponse {
  final MemberSummary user;
  final Subscription? subscription;
  final PaymentRequest? pendingPayment;
  final int visitsUsed;
  final int? visitCap;

  MemberMeResponse({
    required this.user,
    this.subscription,
    this.pendingPayment,
    required this.visitsUsed,
    this.visitCap,
  });

  factory MemberMeResponse.fromJson(
    Map<String, dynamic> json,
  ) => MemberMeResponse(
    user: MemberSummary.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
    subscription: json['subscription'] is Map<String, dynamic>
        ? Subscription.fromJson(json['subscription'] as Map<String, dynamic>)
        : null,
    pendingPayment: json['pendingPayment'] is Map<String, dynamic>
        ? PaymentRequest.fromJson(
            json['pendingPayment'] as Map<String, dynamic>,
          )
        : null,
    visitsUsed: (json['visitsUsed'] as num?)?.toInt() ?? 0,
    visitCap: (json['visitCap'] as num?)?.toInt(),
  );

  bool get hasActivePass => subscription?.isActive == true;
  bool get needsOnboarding => user.onboardingCompleted != true;
}

class PassTier {
  final String id;
  final num price;
  final int? visitCap;
  final String? label;
  final String? gymAccess;

  PassTier({
    required this.id,
    required this.price,
    this.visitCap,
    this.label,
    this.gymAccess,
  });

  /// Parse from /passes (legacy) or /subscription-tiers (new).
  factory PassTier.fromJson(Map<String, dynamic> json) => PassTier(
    id: json['id'] as String? ?? json['key'] as String? ?? '',
    price: json['price'] as num? ?? json['monthlyPrice'] as num? ?? 0,
    visitCap:
        (json['visitCap'] as num?)?.toInt() ??
        ((json['visits'] as num?)?.toInt() == -1
            ? null
            : (json['visits'] as num?)?.toInt()),
    label: json['label'] as String?,
    gymAccess: json['gymAccess'] as String?,
  );

  String get gymAccessLabel {
    switch (gymAccess) {
      case 'standard':
        return 'Standard gyms';
      case 'midtier':
        return 'Standard + Mid-tier gyms';
      case 'premium':
        return 'Standard + Mid-tier + Premium gyms';
      case 'luxury_executive':
        return 'All gyms including Luxury/Executive';
      default:
        return gymAccess ?? '';
    }
  }
}
