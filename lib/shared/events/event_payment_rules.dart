// Events S4 (spec §3.4.1, §5.2): small rules about when an order may be
// paid. The server is the judge; these only decide which screen to show.
import 'event_order.dart';
import 'events_options.dart';

/// The moment an expired order closed (its hold ended).
DateTime? eventOrderClosedAt(EventOrder o) => o.closedAt ?? o.holdExpiresAt;

/// An order that expired on its own may still be paid for a while (the
/// manual path only): the member who already paid can send the transaction
/// ID within `hold.lateGraceHours`, and the server re-reserves the places if
/// it can, or refunds in full. A cancelled order is never revived.
bool eventOrderLatePayable(EventOrder o, EventsOptions options, DateTime now) {
  if (o.status != EventOrderStatus.expired) return false;
  if (o.closeReason != null && o.closeReason != 'expired') return false;
  if (options.payment != 'manual') return false;
  final closed = eventOrderClosedAt(o);
  if (closed == null) return false;
  return now.isBefore(closed.add(Duration(hours: options.hold.lateGraceHours)));
}
