import 'api_client.dart';
import 'i18n.dart';

/// Converts API failures into user-facing copy. Backend validation/decline
/// reasons win over the HTTP status so a 400 never leaks into the UI alone.
String apiErrorMessage(FFLocale locale, ApiException exception) {
  final reason = _firstReason(exception.body);
  if (reason != null && reason.isNotEmpty) {
    final translated = _knownReason(locale, reason) ?? _humanize(reason);
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

String? _knownReason(FFLocale locale, String reason) {
  const keys = {
    'membership_expired': 'error.reason.membershipExpired',
    'gym_tier_not_covered': 'error.reason.gymTierNotCovered',
    'visit_cap_reached': 'error.reason.visitCapReached',
    'slot_unavailable': 'error.reason.slotUnavailable',
    'payment_declined': 'error.reason.paymentDeclined',
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
