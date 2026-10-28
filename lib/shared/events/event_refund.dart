// Events S4 (docs/design/events-s4-payments-and-tickets.md §3.12.2, §5.7):
// the cancel-and-refund preview. Every number comes from the server; the app
// shows the amount and sends it back only as an equality check
// (`expectedRefundTzs`), never as the amount to refund.
import 'event_detail.dart' show EventText;
import 'event_summary.dart' show parseInstant;

String _str(Object? v) => v?.toString() ?? '';

String? _opt(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

int _int(Object? v) => v is num ? v.toInt() : 0;

/// How a cancellation will be handled (`mode`, spec §3.12.2).
enum CancelMode {
  /// A refund (> 0) is raised with the cancellation.
  auto,

  /// The policy gives nothing: cancelled with no refund.
  none,

  /// A person decides: only a request is created.
  manualReview,

  /// Not possible any more (see `blocked`).
  closed;

  static CancelMode parse(Object? v) => switch (v?.toString()) {
    'auto' => auto,
    'none' => none,
    'manual_review' => manualReview,
    _ => closed,
  };
}

/// One place covered by the cancellation.
class CancelPlace {
  const CancelPlace({
    required this.registrationId,
    this.name = '',
    this.paidTzs = 0,
    this.refundTzs = 0,
  });

  final String registrationId;
  final String name;
  final int paidTzs;
  final int refundTzs;

  static CancelPlace fromJson(Map json) => CancelPlace(
    registrationId: _str(json['registrationId']),
    name: _str(json['name']),
    paidTzs: _int(json['paidTzs']),
    refundTzs: _int(json['refundTzs']),
  );
}

/// `cancel-preview` of a registration or an order.
class CancelPreview {
  const CancelPreview({
    this.eligible = false,
    this.mode = CancelMode.closed,
    this.percent = 0,
    this.paidTzs = 0,
    this.refundTzs = 0,
    this.currency = 'TZS',
    this.deadlineAt,
    this.policyPreset = '',
    this.policyText = const EventText(),
    this.policyGenerated = const EventText(),
    this.places = const [],
    this.releaseInventory = false,
    this.blocked,
  });

  final bool eligible;
  final CancelMode mode;
  final int percent;
  final int paidTzs;
  final int refundTzs;
  final String currency;
  final DateTime? deadlineAt;
  final String policyPreset;
  final EventText policyText;

  /// The server's plain policy line: the single source (never built here).
  final EventText policyGenerated;
  final List<CancelPlace> places;
  final bool releaseInventory;

  /// `payment_submitted` | `refund_in_progress` | `cancellation_window_closed`
  /// | `event_cancelled` | `purchaser_only` | `kit_collected`, or null.
  final String? blocked;

  bool get isBlocked =>
      blocked != null || !eligible || mode == CancelMode.closed;

  static CancelPreview fromJson(Map json) {
    final policy = json['policy'] is Map ? json['policy'] as Map : const {};
    return CancelPreview(
      eligible: json['eligible'] == true,
      mode: CancelMode.parse(json['mode']),
      percent: _int(json['percent']),
      paidTzs: _int(json['paidTzs']),
      refundTzs: _int(json['refundTzs']),
      currency: _opt(json['currency']) ?? 'TZS',
      deadlineAt: parseInstant(json['deadlineAt']),
      policyPreset: _str(policy['preset']),
      policyText: policy['text'] is Map
          ? EventText.fromJson(policy['text'])
          : const EventText(),
      policyGenerated: policy['generated'] is Map
          ? EventText.fromJson(policy['generated'])
          : const EventText(),
      places: json['places'] is List
          ? [
              for (final p in json['places'] as List)
                if (p is Map) CancelPlace.fromJson(p),
            ]
          : const [],
      releaseInventory: json['releaseInventory'] == true,
      blocked: _opt(json['blocked']),
    );
  }
}
