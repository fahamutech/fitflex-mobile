import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_order.dart';
import '../../../../shared/events/event_payment.dart';
import '../../../../shared/events/event_time.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';

/// Tone of an order's status pill (events S4 spec §5.10). Green only for a
/// confirmed order; an unpaid order is a warning, everything else gray.
FFBadgeTone eventOrderStatusTone(EventOrderStatus s) => switch (s) {
  EventOrderStatus.awaitingPayment => FFBadgeTone.warning,
  EventOrderStatus.confirmed => FFBadgeTone.success,
  EventOrderStatus.partiallyCancelled ||
  EventOrderStatus.refundPending => FFBadgeTone.warning,
  _ => FFBadgeTone.gray,
};

/// The pill words for a payment state (`events.payment.status.*`).
String eventPaymentStatusLabel(BuildContext context, EventPaymentState s) =>
    context.tr('events.payment.status.${s.wire}');

/// What the order page's payment slot shows (spec §5.1). Chosen from the
/// server's `payment.state` and `order.status`; never from anything the app
/// did itself.
enum EventPaymentSlot {
  /// Awaiting payment, nothing sent yet.
  due,
  submitted,
  processing,
  rejected,
  failed,
  attention,
  refundDue,
  expiredPending,
  confirmed,
  none,
}

/// Which slot applies to [order] with its latest [payment] and [refunds].
EventPaymentSlot eventPaymentSlotFor(
  EventOrder order,
  EventPaymentView? payment,
  List<EventRefundView> refunds,
) {
  final state = payment?.state;
  // Money was taken but the places could not be kept: never green.
  if (state == EventPaymentState.needsAttention) {
    final refund = refunds.isNotEmpty || payment?.refundId != null;
    return refund ? EventPaymentSlot.refundDue : EventPaymentSlot.attention;
  }
  if (order.status == EventOrderStatus.expired) {
    return state == EventPaymentState.submitted ||
            state == EventPaymentState.processing
        ? EventPaymentSlot.expiredPending
        : EventPaymentSlot.none;
  }
  // Confirmed shows only from the order's own status (spec §5.11 rule 4):
  // a payment that reads confirmed while the order does not yet is shown as
  // nothing until the next read agrees.
  if (order.status == EventOrderStatus.confirmed) {
    return EventPaymentSlot.confirmed;
  }
  if (!order.isAwaitingPayment || state == EventPaymentState.confirmed) {
    return EventPaymentSlot.none;
  }
  return switch (state) {
    null => EventPaymentSlot.due,
    EventPaymentState.submitted => EventPaymentSlot.submitted,
    EventPaymentState.processing => EventPaymentSlot.processing,
    EventPaymentState.rejected => EventPaymentSlot.rejected,
    EventPaymentState.failed ||
    EventPaymentState.expired => EventPaymentSlot.failed,
    _ => EventPaymentSlot.due,
  };
}

/// The status card for the order page's payment slot (spec §5.1). The card
/// is a polite live region; a state change is announced once by its page.
class EventPaymentStatusCard extends StatelessWidget {
  const EventPaymentStatusCard({
    super.key,
    required this.slot,
    required this.order,
    required this.options,
    this.payment,
    this.refunds = const [],
    this.ticketCount = 0,
    this.eventTitle = '',
    this.utcOffsetMinutes = 0,
    this.timezoneAbbr = '',
    this.now,
    this.onTryAgain,
    this.onCheck,
    this.onOpenTickets,
  });

  final EventPaymentSlot slot;
  final EventOrder order;
  final EventsOptions options;
  final EventPaymentView? payment;
  final List<EventRefundView> refunds;
  final int ticketCount;
  final String eventTitle;
  final int utcOffsetMinutes;
  final String timezoneAbbr;
  final DateTime? now;

  /// "Try again": back to the pay page, prefilled.
  final VoidCallback? onTryAgain;

  /// "Check status" for a provider prompt.
  final VoidCallback? onCheck;
  final VoidCallback? onOpenTickets;

  String _time(BuildContext context, DateTime? at) {
    if (at == null) return '—';
    final lang = FFLocaleScope.of(context).locale.languageCode;
    return eventTime(at, utcOffsetMinutes, timezoneAbbr, locale: lang);
  }

  String _dateTime(BuildContext context, DateTime? at) {
    if (at == null) return '—';
    final lang = FFLocaleScope.of(context).locale.languageCode;
    return eventDateTime(at, utcOffsetMinutes, timezoneAbbr, locale: lang);
  }

  Future<void> _copy(BuildContext context, String text) async {
    final snack = FFSnack.of(context);
    final copied = context.tr('common.copied');
    await Clipboard.setData(ClipboardData(text: text));
    snack.success(copied);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = payment;
    final amount = formatCurrency(
      p?.amountTzs ?? order.totalTzs,
      currency: order.currency,
    );
    final hours = '${options.manualConfirmHours}';
    final manual = options.payment == 'manual' || p?.method == 'manual';

    Widget body(String text, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
      child: Text(text, key: key, style: tt.bodyMedium),
    );
    Widget small(String text, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
      child: Text(
        text,
        key: key,
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );

    String title;
    FFBadgeTone? pillTone;
    String? pill;
    final children = <Widget>[];

    switch (slot) {
      case EventPaymentSlot.due:
        title = context.tr('events.pay.exact').replaceFirst('{amount}', amount);
        if (manual) {
          pill = context.tr('events.pay.manual.badge');
          pillTone = FFBadgeTone.defaultTone;
          children.add(
            small(
              context
                  .tr('events.pay.manual.banner.body')
                  .replaceFirst('{hours}', hours),
            ),
          );
        }
      case EventPaymentSlot.submitted:
        title = context.tr('events.pay.submitted.title');
        pill = eventPaymentStatusLabel(context, EventPaymentState.submitted);
        pillTone = FFBadgeTone.defaultTone;
        children.add(
          body(
            context
                .tr('events.pay.submitted.body')
                .replaceFirst('{ref}', p?.reference ?? '')
                .replaceFirst('{hours}', hours)
                .replaceFirst('{time}', _time(context, order.holdExpiresAt)),
            key: const Key('pay-submitted-body'),
          ),
        );
        children.add(
          small(
            context
                .tr('events.pay.submitted.sent')
                .replaceFirst('{time}', _dateTime(context, p?.submittedAt))
                .replaceFirst('{phone}', p?.payerPhoneMasked ?? ''),
            key: const Key('pay-submitted-sent'),
          ),
        );
        if ((p?.reference ?? '').isNotEmpty) {
          children.add(
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                key: const Key('pay-copy-reference'),
                tooltip: context.tr('common.copy'),
                icon: const Icon(Icons.copy_outlined, size: 20),
                onPressed: () => _copy(context, p!.reference!),
              ),
            ),
          );
        }
        children.add(
          small(
            context.tr('events.pay.submitted.noCancel'),
            key: const Key('pay-no-cancel'),
          ),
        );
      case EventPaymentSlot.processing:
        title = context.tr('events.pay.processing.title');
        pill = eventPaymentStatusLabel(context, EventPaymentState.processing);
        pillTone = FFBadgeTone.defaultTone;
        children.add(
          body(
            context
                .tr('events.pay.processing.body')
                .replaceFirst('{phone}', p?.payerPhoneMasked ?? '')
                .replaceFirst('{amount}', amount),
          ),
        );
        final since = p?.submittedAt;
        final clock = now ?? DateTime.now();
        if (since != null &&
            clock.difference(since) > const Duration(minutes: 2)) {
          children.add(
            small(
              context.tr('events.pay.slowWait'),
              key: const Key('pay-slow'),
            ),
          );
        }
        if (onCheck != null) {
          children.add(const SizedBox(height: FFTokens.spacingSm));
          children.add(
            FFButton(
              key: const Key('pay-check-status'),
              label: context.tr('events.pay.processing.check'),
              variant: FFButtonVariant.secondary,
              onPressed: onCheck,
            ),
          );
        }
      case EventPaymentSlot.rejected:
        title = context.tr('events.pay.rejected.title');
        pill = eventPaymentStatusLabel(context, EventPaymentState.rejected);
        pillTone = FFBadgeTone.warning;
        final code = eventRejectCodes.contains(p?.rejectCode)
            ? p!.rejectCode!
            : 'other';
        children.add(
          body(
            context
                .tr('events.pay.rejected.$code')
                .replaceFirst('{amount}', amount),
            key: const Key('pay-rejected-reason'),
          ),
        );
        if ((p?.memberNote ?? '').isNotEmpty) {
          children.add(
            small(
              context
                  .tr('events.pay.rejected.note')
                  .replaceFirst('{note}', p!.memberNote!),
              key: const Key('pay-rejected-note'),
            ),
          );
        }
        if (p?.canRetry == true && onTryAgain != null) {
          children.add(const SizedBox(height: FFTokens.spacingSm));
          children.add(
            FFButton(
              key: const Key('pay-try-again'),
              label: context
                  .tr('events.pay.rejected.retry')
                  .replaceFirst('{time}', _time(context, order.holdExpiresAt)),
              fullWidth: true,
              maxLines: 2,
              onPressed: onTryAgain,
            ),
          );
        } else {
          children.add(
            small(
              context.tr('events.pay.rejected.noHold'),
              key: const Key('pay-rejected-nohold'),
            ),
          );
        }
      case EventPaymentSlot.failed:
        title = context.tr('events.pay.failed.title');
        pill = eventPaymentStatusLabel(context, EventPaymentState.failed);
        pillTone = FFBadgeTone.warning;
        children.add(
          body(
            context
                .tr('events.pay.failed.body')
                .replaceFirst('{ref}', order.reference),
          ),
        );
        if (p?.canRetry == true && onTryAgain != null) {
          children.add(const SizedBox(height: FFTokens.spacingSm));
          children.add(
            FFButton(
              key: const Key('pay-try-again'),
              label: context.tr('common.retry'),
              onPressed: onTryAgain,
            ),
          );
        }
      case EventPaymentSlot.attention:
        title = context.tr('events.pay.attention.title');
        pill = eventPaymentStatusLabel(
          context,
          EventPaymentState.needsAttention,
        );
        pillTone = FFBadgeTone.warning;
        children.add(body(context.tr('events.pay.attention.body')));
      case EventPaymentSlot.refundDue:
        title = context.tr('events.pay.refundDue.title');
        children.add(
          body(
            context
                .tr('events.pay.refundDue.body')
                .replaceFirst(
                  '{amount}',
                  formatCurrency(
                    refunds.isNotEmpty
                        ? refunds.first.amountTzs
                        : (p?.amountTzs ?? order.totalTzs),
                    currency: order.currency,
                  ),
                ),
            key: const Key('pay-refund-due-body'),
          ),
        );
      case EventPaymentSlot.expiredPending:
        title = context.tr('events.pay.expiredPending.title');
        pill = eventPaymentStatusLabel(context, EventPaymentState.submitted);
        pillTone = FFBadgeTone.warning;
        children.add(body(context.tr('events.pay.expiredPending.body')));
      case EventPaymentSlot.confirmed:
        title = context.tr('events.pay.confirmed.title');
        pill = context.tr('events.status.order.paid');
        pillTone = FFBadgeTone.success;
        children.add(
          body(
            context
                .tr('events.pay.confirmed.body')
                .replaceFirst('{n}', '$ticketCount')
                .replaceFirst('{event}', eventTitle),
            key: const Key('pay-confirmed-body'),
          ),
        );
        if (onOpenTickets != null) {
          children.add(const SizedBox(height: FFTokens.spacingSm));
          children.add(
            FFButton(
              key: const Key('pay-open-tickets'),
              label: context.tr('events.pay.confirmed.open'),
              fullWidth: true,
              onPressed: onOpenTickets,
            ),
          );
        }
      case EventPaymentSlot.none:
        return const SizedBox.shrink();
    }

    return FFCard(
      key: Key('pay-card-${slot.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    key: const Key('pay-card-title'),
                    style: tt.titleSmall,
                  ),
                ),
                if (pill != null) ...[
                  const SizedBox(width: FFTokens.spacingSm),
                  FFBadge(
                    key: const Key('pay-card-pill'),
                    label: pill,
                    tone: pillTone ?? FFBadgeTone.defaultTone,
                  ),
                ],
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// One refund, as the order and registration pages show it (spec §5.7).
/// Text first; green only once the money has been sent.
class EventRefundCard extends StatelessWidget {
  const EventRefundCard({
    super.key,
    required this.refund,
    required this.options,
    this.utcOffsetMinutes = 0,
  });

  final EventRefundView refund;
  final EventsOptions options;
  final int utcOffsetMinutes;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tone = switch (refund.status) {
      'paid' => FFBadgeTone.success,
      'rejected' => FFBadgeTone.warning,
      _ => FFBadgeTone.defaultTone,
    };
    final status = context.tr('events.refund.status.${refund.status}');
    final scopeKey = 'events.refund.scope.${refund.scope}';
    final scope = context.tr(scopeKey);
    final amount = formatCurrency(refund.amountTzs, currency: refund.currency);
    Widget line(String text, {Key? key, bool strong = false}) => Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
      child: Text(
        text,
        key: key,
        style: strong
            ? tt.bodyMedium
            : tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
    return FFCard(
      key: Key('refund-card-${refund.id}'),
      child: Semantics(
        container: true,
        label: [
          context.tr('events.refund.title'),
          status,
          amount,
          if (scope != scopeKey) scope,
        ].join(', '),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      context.tr('events.refund.title'),
                      style: tt.titleSmall,
                    ),
                  ),
                ),
                FFBadge(
                  key: Key('refund-status-${refund.id}'),
                  label: status,
                  tone: tone,
                ),
              ],
            ),
            line(amount, key: const Key('refund-amount'), strong: true),
            if (scope != scopeKey) line(scope),
            if (refund.requestedAt != null)
              line(
                context
                    .tr('events.refund.requestedOn')
                    .replaceFirst(
                      '{date}',
                      eventDate(
                        refund.requestedAt!,
                        utcOffsetMinutes,
                        locale: lang,
                      ),
                    ),
              ),
            if (refund.isOpen)
              line(
                context
                    .tr('events.refund.eta')
                    .replaceFirst('{days}', '${options.refundDays}'),
                key: const Key('refund-eta'),
              ),
            if (refund.isPaid)
              line(
                context
                    .tr('events.refund.sentTo')
                    .replaceFirst('{phone}', refund.paidTo ?? '—')
                    .replaceFirst('{ref}', refund.paymentReference ?? '—'),
                key: const Key('refund-sent'),
              ),
            if (refund.status == 'rejected') ...[
              if ((refund.rejectionNote ?? '').isNotEmpty)
                line(
                  refund.rejectionNote!,
                  key: const Key('refund-note'),
                  strong: true,
                ),
              line(
                context.tr('events.refund.rejected.help'),
                key: const Key('refund-help'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
