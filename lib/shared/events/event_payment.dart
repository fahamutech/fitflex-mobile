// Events S4 (docs/design/events-s4-payments-and-tickets.md §3.4, §3.5): the
// wire shapes of an order's payment, the manual-payment instructions the
// order carries, and refunds. Field names are the server's. The money state
// is only ever read from here: the app never marks anything paid itself.
import '../manual_payment.dart';
import 'event_summary.dart' show parseInstant;

int _int(Object? v, [int fallback = 0]) => v is num
    ? v.toInt()
    : (v is String ? int.tryParse(v) ?? fallback : fallback);

String _str(Object? v) => v?.toString() ?? '';

String? _opt(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// `payment.state` (spec §3.3). The server derives it; the app never infers
/// money state from anything else.
enum EventPaymentState {
  submitted,
  processing,
  confirmed,
  rejected,
  failed,
  expired,
  needsAttention,
  other;

  static EventPaymentState parse(Object? v) => switch (v?.toString()) {
    'submitted' => submitted,
    'processing' => processing,
    'confirmed' => confirmed,
    'rejected' => rejected,
    'failed' => failed,
    'expired' => expired,
    'needs_attention' => needsAttention,
    _ => other,
  };

  /// The wire word, for i18n keys (`events.payment.status.<wire>`).
  String get wire => switch (this) {
    needsAttention => 'needs_attention',
    other => 'other',
    _ => name,
  };

  /// Still open: the page keeps polling.
  bool get isLive => this == submitted || this == processing;
}

/// Closed set of rejection reasons (spec §3.5 `rejectCode`).
const eventRejectCodes = [
  'reference_not_found',
  'amount_mismatch',
  'wrong_account',
  'duplicate_reference',
  'other',
];

/// `PaymentView` (spec §3.5).
class EventPaymentView {
  const EventPaymentView({
    required this.id,
    this.state = EventPaymentState.other,
    this.method = 'manual',
    this.amountTzs = 0,
    this.currency = 'TZS',
    this.reference,
    this.payerPhoneMasked,
    this.submittedAt,
    this.decidedAt,
    this.confirmTargetAt,
    this.rejectCode,
    this.memberNote,
    this.late = false,
    this.canRetry = false,
    this.refundId,
  });

  final String id;
  final EventPaymentState state;

  /// `manual` | `provider` | `free`.
  final String method;
  final int amountTzs;
  final String currency;

  /// The member's own transaction ID, back to the member who typed it.
  final String? reference;
  final String? payerPhoneMasked;
  final DateTime? submittedAt;
  final DateTime? decidedAt;

  /// `submittedAt + manualConfirmHours`: a target to quote, never a promise.
  final DateTime? confirmTargetAt;
  final String? rejectCode;

  /// The admin's note written for the member (<= 140 characters).
  final String? memberNote;
  final bool late;

  /// Order awaiting payment, hold not over, no live payment.
  final bool canRetry;
  final String? refundId;

  bool get isFree => method == 'free';

  static EventPaymentView? fromJson(Object? json) {
    if (json is! Map) return null;
    return EventPaymentView(
      id: _str(json['id']),
      state: EventPaymentState.parse(json['state']),
      method: _opt(json['method']) ?? 'manual',
      amountTzs: _int(json['amountTzs']),
      currency: _opt(json['currency']) ?? 'TZS',
      reference: _opt(json['reference']),
      payerPhoneMasked: _opt(json['payerPhoneMasked']),
      submittedAt: parseInstant(json['submittedAt']),
      decidedAt: parseInstant(json['decidedAt']),
      confirmTargetAt: parseInstant(json['confirmTargetAt']),
      rejectCode: _opt(json['rejectCode']),
      memberNote: _opt(json['memberNote']),
      late: json['late'] == true,
      canRetry: json['canRetry'] == true,
      refundId: _opt(json['refundId']),
    );
  }
}

/// `next.instructions` of an order for `next.payment == 'manual'` (spec
/// §3.5): shaped like `/payments/options.manual` plus the order's amount and
/// reference, so the page can say "pay exactly TSh 120,000".
class EventManualInstructions {
  const EventManualInstructions({
    required this.manual,
    this.amountTzs,
    this.reference = '',
  });

  /// Lipa Namba, account name, network, the admin's own instructions and
  /// the two "required" switches, in the shared manual-payment shape.
  final ManualPayment manual;

  /// The amount the server wants for this order, when it said so.
  final int? amountTzs;

  /// The order reference to quote.
  final String reference;

  /// Null when the block is missing, or lacks the number or account name.
  static EventManualInstructions? fromJson(Object? json) {
    if (json is! Map) return null;
    final block = {...Map<String, dynamic>.from(json), 'enabled': true};
    final manual = ManualPayment.fromOptions({'manual': block});
    if (manual == null) return null;
    return EventManualInstructions(
      manual: manual,
      amountTzs: json['amountTzs'] is num
          ? (json['amountTzs'] as num).toInt()
          : null,
      reference: _str(json['reference']),
    );
  }
}

/// `RefundView` (spec §3.5): one refund the member can read.
class EventRefundView {
  const EventRefundView({
    required this.id,
    this.status = 'requested',
    this.scope = 'registration',
    this.amountTzs = 0,
    this.currency = 'TZS',
    this.requestedAt,
    this.decidedAt,
    this.paidAt,
    this.paidTo,
    this.paymentReference,
    this.rejectionNote,
  });

  final String id;

  /// `requested` | `approved` | `paid` | `rejected`.
  final String status;

  /// `registration` | `order` | `event_cancelled` | `unfulfilled_payment`.
  final String scope;
  final int amountTzs;
  final String currency;
  final DateTime? requestedAt;
  final DateTime? decidedAt;
  final DateTime? paidAt;
  final String? paidTo;

  /// The payout reference, only once paid.
  final String? paymentReference;

  /// The member-visible note on a refusal.
  final String? rejectionNote;

  bool get isPaid => status == 'paid';
  bool get isOpen => status == 'requested' || status == 'approved';

  static EventRefundView? fromJson(Object? json) {
    if (json is! Map) return null;
    return EventRefundView(
      id: _str(json['id']),
      status: _opt(json['status']) ?? 'requested',
      scope: _opt(json['scope']) ?? 'registration',
      amountTzs: _int(json['amountTzs']),
      currency: _opt(json['currency']) ?? 'TZS',
      requestedAt: parseInstant(json['requestedAt']),
      decidedAt: parseInstant(json['decidedAt']),
      paidAt: parseInstant(json['paidAt']),
      paidTo: _opt(json['paidTo']),
      paymentReference: _opt(json['paymentReference']),
      rejectionNote: _opt(json['rejectionNote']),
    );
  }

  static List<EventRefundView> listFrom(Object? json) => json is List
      ? [for (final r in json) ?EventRefundView.fromJson(r)]
      : const [];
}

/// `GET /me/event-orders/:id/payment-status` (spec §3.5): cheap, one order,
/// safe to poll every 30 seconds while a screen is open.
class EventPaymentStatus {
  const EventPaymentStatus({
    this.orderStatus = '',
    this.holdExpiresAt,
    this.totalTzs = 0,
    this.currency = 'TZS',
    this.payment,
    this.refund,
  });

  final String orderStatus;
  final DateTime? holdExpiresAt;
  final int totalTzs;
  final String currency;
  final EventPaymentView? payment;
  final EventRefundView? refund;

  static EventPaymentStatus fromJson(Map json) {
    final order = json['order'] is Map ? json['order'] as Map : const {};
    return EventPaymentStatus(
      orderStatus: _str(order['status']),
      holdExpiresAt: parseInstant(order['holdExpiresAt']),
      totalTzs: _int(order['totalTzs']),
      currency: _opt(order['currency']) ?? 'TZS',
      payment: EventPaymentView.fromJson(json['payment']),
      refund: EventRefundView.fromJson(json['refund']),
    );
  }
}

/// The 201 / replayed 200 of `POST /me/event-orders/:id/payment` (§3.4.1).
class EventPaymentSubmission {
  const EventPaymentSubmission({
    this.payment,
    this.orderStatus = '',
    this.holdExpiresAt,
    this.mode = 'manual',
    this.paymentRequestId,
    this.late = false,
    this.replayed = false,
    this.amountTzs = 0,
  });

  final EventPaymentView? payment;
  final String orderStatus;
  final DateTime? holdExpiresAt;

  /// `next.payment`: `manual` | `provider` | `none` (a free order).
  final String mode;
  final String? paymentRequestId;
  final bool late;
  final bool replayed;
  final int amountTzs;

  static EventPaymentSubmission fromJson(Map json) {
    final order = json['order'] is Map ? json['order'] as Map : const {};
    final next = json['next'] is Map ? json['next'] as Map : const {};
    return EventPaymentSubmission(
      payment: EventPaymentView.fromJson(json['payment']),
      orderStatus: _str(order['status']),
      holdExpiresAt: parseInstant(order['holdExpiresAt']),
      mode: _opt(next['payment']) ?? 'manual',
      paymentRequestId: _opt(next['paymentRequestId']),
      late: json['late'] == true,
      replayed: json['replayed'] == true,
      amountTzs: _int(order['totalTzs']),
    );
  }
}
