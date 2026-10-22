import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'formatters.dart';
import 'i18n.dart';

/// Any caught error → user-facing copy (UAT #48). Prefer this over
/// `e.toString()`, which shows raw text like "ApiException(400, {...})".
///
/// [vendorStaff]: the caller is vendor staff, so `account_suspended` means
/// their staff access was turned off (vendor tools S2).
String errorMessage(FFLocale locale, Object error, {bool vendorStaff = false}) {
  if (error is ApiException) {
    return apiErrorMessage(locale, error, vendorStaff: vendorStaff);
  }
  if (isNetworkError(error)) return locale.t('error.network');
  return locale.t('error.requestFailed');
}

/// A refused trainer-booking cancel (member or trainer side). While a
/// mobile-money prompt is out for the booking the server answers
/// 409 payment_in_progress (fitflex-functions#240): say so plainly.
String bookingCancelErrorMessage(FFLocale locale, Object error) {
  if (error is ApiException &&
      _firstReason(error.body)?.trim().toLowerCase() == 'payment_in_progress') {
    return locale.t('error.reason.bookingPaymentInProgress');
  }
  return errorMessage(locale, error);
}

/// The request never reached the server (offline, DNS, timeout), as
/// opposed to the server answering with an error.
bool isNetworkError(Object error) {
  if (error is ApiException) return false;
  if (error is TimeoutException || error is http.ClientException) return true;
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('Failed host lookup');
}

/// Converts API failures into user-facing copy. Backend validation/decline
/// reasons win over the HTTP status so a 400 never leaks into the UI alone.
String apiErrorMessage(
  FFLocale locale,
  ApiException exception, {
  bool vendorStaff = false,
}) {
  if (isVendorStaffDisabled(exception, vendorStaff: vendorStaff)) {
    return locale.t('error.reason.vendorStaffInactive');
  }
  final reason = _firstReason(exception.body);
  if (reason != null && reason.isNotEmpty) {
    final translated =
        _timedReason(locale, reason, exception.body) ??
        _detailedReason(locale, reason, exception.body) ??
        _knownReason(locale, reason) ??
        _humanize(reason);
    return locale
        .t('error.requestDeclined')
        .replaceFirst('{reason}', translated);
  }

  final key = switch (exception.status) {
    401 => 'error.unauthorized',
    403 => 'error.forbidden',
    404 => 'error.notFound',
    409 => 'error.conflict',
    _ => 'error.requestFailed',
  };
  return locale.t(key);
}

/// Vendor staff whose access the business owner turned off (vendor tools
/// S2, fitflex-functions#200): `vendor_staff_inactive` from vendor routes and
/// PIN sign-in, or `account_suspended` (the token check runs first) when the
/// caller is vendor staff. For anyone else `account_suspended` keeps its
/// own message.
bool isVendorStaffDisabled(Object error, {bool vendorStaff = false}) {
  if (error is! ApiException) return false;
  final reason = _firstReason(error.body)?.trim().toLowerCase();
  if (reason == 'vendor_staff_inactive') return true;
  return vendorStaff && reason == 'account_suspended';
}

String? _firstReason(dynamic value) {
  if (value is String) return value.trim().isEmpty ? null : value.trim();
  if (value is List) {
    for (final item in value) {
      final reason = _firstReason(item);
      if (reason != null) return reason;
    }
    return null;
  }
  if (value is Map) {
    for (final key in const [
      'reason',
      'failure', // check-in declines: { ok:false, failure:'visits_exhausted' }
      'message',
      'error_description',
      'error',
      'detail',
      'details',
      'errors',
    ]) {
      if (value.containsKey(key)) {
        final reason = _firstReason(value[key]);
        if (reason != null) return reason;
      }
    }
  }
  return null;
}

/// Refusals that carry the time they are about (trainer session outcomes,
/// fitflex-functions#231): the start of a session that hasn't begun, or
/// when the window to record a missed session closed. Null when the body has
/// no readable time, so the plain wording is used.
String? _timedReason(FFLocale locale, String reason, dynamic body) {
  if (body is! Map) return null;
  final (String field, String key) = switch (reason.trim().toLowerCase()) {
    'session_not_started' => ('startsAt', 'error.reason.sessionNotStartedAt'),
    'no_show_window_passed' => (
      'closedAt',
      'error.reason.noShowWindowPassedAt',
    ),
    _ => ('', ''),
  };
  if (field.isEmpty || localDateTime(body[field]) == null) return null;
  final time = formatDayTime(body[field], locale: locale.locale.languageCode);
  return locale.t(key).replaceFirst('{time}', time);
}

/// Refusals whose details change the wording (mobile money for trainer
/// products, fitflex-functions#240): which account pays for a product, and
/// which pass tier is off sale. Null falls back to the plain wording.
String? _detailedReason(FFLocale locale, String reason, dynamic body) {
  if (body is! Map) return null;
  switch (reason.trim().toLowerCase()) {
    case 'not_payable_by_role':
      final product = body['product']?.toString();
      if (product == null) return null;
      return locale.t(
        product == 'TRAINER_GYM_PASS'
            ? 'error.reason.notPayableByRoleTrainer'
            : 'error.reason.notPayableByRoleMember',
      );
    case 'tier_not_available':
      final tier = body['tier']?.toString().trim() ?? '';
      if (tier.isEmpty) return null;
      // Tier names stay English (owner, Swahili review 2026-10-04).
      final name = '${tier[0].toUpperCase()}${tier.substring(1)}';
      return locale
          .t('error.reason.tierNotAvailableNamed')
          .replaceFirst('{tier}', name);
  }
  return null;
}

String? _knownReason(FFLocale locale, String reason) {
  const keys = {
    'membership_expired': 'error.reason.membershipExpired',
    'gym_tier_not_covered': 'error.reason.gymTierNotCovered',
    'visit_cap_reached': 'error.reason.visitCapReached',
    'slot_unavailable': 'error.reason.slotUnavailable',
    'payment_declined': 'error.reason.paymentDeclined',
    // Check-in (BL-012) — codes the backend actually returns.
    'subscription_inactive': 'error.reason.membershipExpired',
    'tier_not_covered': 'error.reason.gymTierNotCovered',
    'visits_exhausted': 'error.reason.visitCapReached',
    'gym_closed': 'error.reason.gymClosed',
    'whatsapp_template_required': 'error.reason.whatsappTemplateRequired',
    'basic_daily_limit': 'error.reason.basicDailyLimit',
    'invalid_or_expired_qr': 'error.reason.qrExpired',
    'invalid_gym_qr': 'error.reason.invalidGymQr',
    'not_your_gym': 'error.reason.notYourGym',
    'gym_required': 'error.reason.gymRequired',
    'wrong_gym': 'error.reason.wrongGym',
    'gym_not_verified': 'error.reason.gymNotVerified',
    'trainer_not_verified': 'error.reason.trainerNotVerified',
    'operator_not_assigned_to_gym': 'error.reason.operatorNotAssigned',
    'member_not_found': 'error.reason.memberNotFound',
    'gym_not_found': 'error.reason.gymNotFound',
    'tier_not_configured': 'error.reason.tierNotConfigured',
    // Trainer booking.
    'slot_already_booked': 'error.reason.slotUnavailable',
    'slot_not_available': 'error.reason.slotUnavailable',
    'slot_in_past': 'error.reason.slotInPast',
    // Cancellations and refunds.
    'cancellation_window_passed': 'error.reason.cancelWindowPassed',
    'session_already_started': 'error.reason.sessionStarted',
    'booking_not_cancellable': 'error.reason.bookingNotCancellable',
    'order_already_dispatched': 'error.reason.orderDispatched',
    'order_already_delivered': 'error.reason.orderDispatched',
    'order_cancelled': 'error.reason.orderCancelled',
    'refund_already_requested': 'error.reason.refundAlreadyRequested',
    // Trainer session outcomes (fitflex-functions#231).
    'session_not_started': 'error.reason.sessionNotStarted',
    'booking_not_confirmable': 'error.reason.bookingNotConfirmable',
    'booking_not_confirmed': 'error.reason.bookingNotConfirmed',
    'no_show_window_passed': 'error.reason.noShowWindowPassed',
    'booking_cancelled': 'error.reason.bookingCancelled',
    'booking_changed': 'error.reason.bookingChanged',
    'booking_on_trainer_statement': 'error.reason.bookingOnTrainerStatement',
    'invalid_booking_time': 'error.reason.invalidBookingTime',
    'cannot_book_own_sessions': 'error.reason.cannotBookOwnSessions',
    // Pass and gym-plan purchases.
    'payment_already_pending': 'error.reason.paymentAlreadyPending',
    'plan_not_offered': 'error.reason.planNotOffered',
    'gym_not_available': 'error.reason.gymNotAvailable',
    'tier_not_available': 'error.reason.tierNotAvailable',
    // Manual Lipa Namba payment (fitflex-functions#188).
    'payment_reference_required': 'error.reason.paymentReferenceRequired',
    'payment_reference_invalid': 'error.reason.paymentReferenceInvalid',
    'payment_reference_duplicate': 'error.reason.paymentReferenceDuplicate',
    'manual_payment_submitted': 'error.reason.manualPaymentSubmitted',
    'payer_phone_required': 'error.reason.payerPhoneRequired',
    'payer_phone_invalid': 'error.reason.payerPhoneInvalid',
    'invalid_tier': 'error.reason.tierNotAvailable',
    'not_an_upgrade': 'error.reason.notAnUpgrade',
    'invalid_phone': 'error.reason.invalidPhone',
    'too_many_attempts': 'error.reason.tooManyAttempts',
    'payment_in_progress': 'error.reason.paymentInProgress',
    'provider_unavailable': 'error.reason.providerUnavailable',
    'provider_rejected': 'error.reason.providerRejected',
    'payment_not_pending': 'error.reason.paymentNotPending',
    'not_payable_this_way': 'error.reason.notPayableThisWay',
    'not_payable_by_role': 'error.reason.notPayableByRole',
    'group_slot_rebooked': 'error.reason.groupSlotRebooked',
    'unsupported_currency': 'error.reason.unsupportedCurrency',
    'sponsored_pass': 'error.reason.sponsoredPass',
    // Accounts.
    'email_already_used': 'error.reason.emailAlreadyUsed',
    'invalid_credentials': 'error.reason.invalidCredentials',
    'account_suspended': 'error.reason.accountSuspended',
    'acl_forbidden': 'error.reason.noPermission',
    'active_subscription_required': 'error.reason.activeSubscriptionRequired',
    // Communications.
    'confirm_large_send': 'error.reason.confirmLargeSend',
    'nobody_reachable': 'error.reason.nobodyReachable',
    'empty_audience': 'error.reason.emptyAudience',
    'invalid_state': 'error.reason.campaignChanged',
    'not_editable': 'error.reason.campaignChanged',
    'channel_unavailable': 'error.reason.channelUnavailable',
    'schedule_too_soon': 'error.reason.scheduleTooSoon',
    'invalid_content': 'error.reason.invalidContent',
    'invalid_audience': 'error.reason.invalidAudience',
    // Vendor products and verification.
    'invalid_category': 'error.reason.invalidCategory',
    'invalid_product_category': 'error.reason.invalidCategory',
    'invalid_position': 'error.reason.invalidPosition',
    // Reviews.
    'no_completed_booking': 'error.reason.noCompletedBooking',
    'no_checkin_or_direct_subscription': 'error.reason.noGymVisit',
    'rating_must_be_integer_1_to_5': 'error.reason.invalidRating',
    'text_too_short': 'error.reason.reviewTextTooShort',
    'text_too_long': 'error.reason.reviewTextTooLong',
    // Events (Marathon & Running Events S2, spec §14.6).
    'event_not_found': 'error.reason.eventNotFound',
    'feature_disabled': 'error.reason.featureDisabled',
    'rate_limited': 'error.reason.rateLimited',
    'not_your_organizer': 'error.reason.notYourOrganizer',
    'organizer_not_active': 'error.reason.organizerNotActive',
    'organizer_suspended': 'error.reason.organizerSuspended',
    'forbidden_role': 'error.reason.noPermission',
    'invalid_transition': 'error.reason.invalidTransition',
    'version_conflict': 'error.reason.versionConflict',
    'event_invalid': 'error.reason.eventInvalid',
    'change_note_required': 'error.reason.changeNoteRequired',
    'has_registrations': 'error.reason.hasRegistrations',
    'organizer_exists': 'error.reason.organizerExists',
    'persona_not_allowed': 'error.reason.personaNotAllowed',
    'already_staff': 'error.reason.alreadyStaff',
    'invalid_contact': 'error.reason.invalidContact',
    'cannot_invite_self': 'error.reason.cannotInviteSelf',
    'cannot_remove_owner': 'error.reason.cannotRemoveOwner',
    'kyc_incomplete': 'error.reason.kycIncomplete',
  };
  final key = keys[reason.trim().toLowerCase()];
  return key == null ? null : locale.t(key);
}

String _humanize(String value) {
  final clean = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.isEmpty) return value;
  return '${clean[0].toUpperCase()}${clean.substring(1)}';
}
