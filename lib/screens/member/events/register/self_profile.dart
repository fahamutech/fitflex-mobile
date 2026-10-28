import 'package:flutter/widgets.dart';

import '../../../../app_scope.dart';
import '../../../../shared/date_of_birth.dart';
import '../../../../shared/events/event_order.dart';
import '../../../../shared/events/events_checkout.dart';
import '../../member_shell.dart';

/// What the "Myself" card is prefilled with (events S3 spec §5.5): the
/// member's name, their **verified** phone / email (typed profile values
/// count for nothing — `self_contact_mismatch`), and the profile's date of
/// birth and gender when it has them (`/me/personal-details` is not wired
/// in this app; spec §8.7 accepts the member-profile fallback).
class RegistrationSelfProfile {
  const RegistrationSelfProfile({
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.email = '',
    this.dateOfBirth = '',
    this.gender = '',
    this.emergencyName = '',
    this.emergencyPhone = '',
  });

  final String firstName;
  final String lastName;

  /// Verified contacts only; empty when none is verified.
  final String phone;
  final String email;
  final String dateOfBirth;
  final String gender;
  final String emergencyName;
  final String emergencyPhone;

  /// A self place needs a verified contact (§5.5).
  bool get hasVerifiedContact => phone.isNotEmpty || email.isNotEmpty;

  /// Read from the member scope and the auth state. When the identifiers
  /// feature is off on the server (404), the profile's own phone / email
  /// are the only contacts the server knows and are used instead.
  static RegistrationSelfProfile fromScope(BuildContext context) {
    final auth = AppScope.of(context).auth;
    final me = context
        .dependOnInheritedWidgetOfExactType<MemberDataScope>()
        ?.notifier
        ?.me;
    final user = me?.user;
    final name = (user?.displayName ?? '').trim();
    final parts = name.split(RegExp(r'\s+'));
    final first = parts.isEmpty ? '' : parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    String verified(String type) {
      for (final i in auth.verifiedIdentifiers) {
        if (i['type']?.toString() == type) return i['value']?.toString() ?? '';
      }
      return '';
    }

    final phone = auth.identifiersEnabled
        ? verified('phone')
        : (user?.phone ?? '');
    final email = auth.identifiersEnabled
        ? verified('email')
        : (user?.email ?? '');
    final dob = normaliseDateOfBirth(user?.memberProfile?.dateOfBirth ?? '');
    final gender = user?.memberProfile?.gender ?? '';
    return RegistrationSelfProfile(
      firstName: first,
      lastName: last,
      phone: phone.trim(),
      email: email.trim(),
      dateOfBirth: parseDateOfBirth(dob) == null ? '' : dob,
      gender: participantGenders.contains(gender) ? gender : '',
    );
  }

  /// Fills a self participant from this profile (name editable later).
  void applyTo(EventParticipantInput p) {
    p
      ..isSelf = true
      ..firstName = p.firstName.isEmpty ? firstName : p.firstName
      ..lastName = p.lastName.isEmpty ? lastName : p.lastName
      ..phone = phone
      ..email = email
      ..dateOfBirth = p.dateOfBirth.isEmpty ? dateOfBirth : p.dateOfBirth
      ..gender = p.gender.isEmpty ? gender : p.gender
      ..consented = true;
  }
}
