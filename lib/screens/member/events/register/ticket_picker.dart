import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_detail.dart';
import '../../../../shared/events/event_summary.dart';
import '../../../../shared/events/event_time.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../event_status.dart';

/// Step 1 of the register flow (events S3 spec §5.3): one card per active
/// category with a quantity stepper per ticket type on sale, a live
/// estimate line and the per-order cap hint.
class TicketPicker extends StatelessWidget {
  const TicketPicker({
    super.key,
    required this.detail,
    required this.lines,
    required this.maxParticipants,
    required this.onChanged,
  });

  final EventDetail detail;

  /// ticketTypeId → quantity.
  final Map<String, int> lines;
  final int maxParticipants;
  final ValueChanged<Map<String, int>> onChanged;

  int get total => lines.values.fold(0, (a, b) => a + b);

  static bool onSale(EventTicketType t) =>
      t.availability == EventAvailability.open ||
      t.availability == EventAvailability.closingSoon;

  /// Client-side sum of unit prices (labelled an estimate until the quote).
  int estimate(EventDetail d) {
    var sum = 0;
    for (final c in d.categories) {
      for (final t in c.ticketTypes) {
        sum += (lines[t.id] ?? 0) * t.priceTzs;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = detail.summary;
    final atMax = total >= maxParticipants;
    final sum = estimate(detail);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in detail.categories)
          if (c.ticketTypes.isNotEmpty)
            FFCard(
              key: Key('ticket-category-${c.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(c.name, style: tt.titleSmall)),
                      if (c.distanceM > 0)
                        FFPill(label: distanceLabel(c.distanceM)),
                    ],
                  ),
                  if (c.startsAt != null)
                    Text(
                      eventDateTime(
                        c.startsAt!,
                        s.utcOffsetMinutes,
                        s.timezoneAbbr,
                        locale: lang,
                      ),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  Wrap(
                    spacing: FFTokens.spacingSm,
                    children: [
                      if (c.minAge != null)
                        Text(
                          context
                              .tr('events.register.minAge')
                              .replaceFirst('{n}', '${c.minAge}'),
                          key: Key('ticket-minage-${c.id}'),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      if (c.remaining != null)
                        Text(
                          context
                              .tr('events.register.left')
                              .replaceFirst('{n}', '${c.remaining}'),
                          key: Key('ticket-left-${c.id}'),
                          style: tt.bodySmall?.copyWith(
                            color: fuelTextColor(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  for (final t in c.ticketTypes) _row(context, s, t, atMax),
                ],
              ),
            ),
        const SizedBox(height: FFTokens.spacingSm),
        Semantics(
          liveRegion: true,
          child: Text(
            context
                .tr('events.register.estimate')
                .replaceFirst('{n}', '$total')
                .replaceFirst(
                  '{amount}',
                  sum == 0
                      ? context.tr('events.card.free')
                      : formatCurrency(sum, currency: s.currency),
                ),
            key: const Key('ticket-estimate'),
            style: tt.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (atMax)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('ticket-max-hint'),
              tone: FFAlertTone.info,
              message: context
                  .tr('events.register.maxPerOrder')
                  .replaceFirst('{max}', '$maxParticipants'),
            ),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    EventSummary s,
    EventTicketType t,
    bool atMax,
  ) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sale = onSale(t);
    final price = t.isFree
        ? context.tr('events.card.free')
        : formatCurrency(t.priceTzs, currency: t.currency);
    final until = t.saleClosesAt == null
        ? null
        : context
              .tr('events.detail.until')
              .replaceFirst(
                '{date}',
                eventDate(t.saleClosesAt!, s.utcOffsetMinutes, locale: lang),
              );
    final qty = lines[t.id] ?? 0;
    return Padding(
      key: Key('ticket-row-${t.id}'),
      padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${t.name} · $price',
                  style: tt.bodyMedium?.copyWith(
                    color: sale ? null : cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (until != null)
                  Text(
                    until,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                if (!sale)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                    child: EventAvailabilityPill(
                      event: EventSummary(
                        id: t.id,
                        title: t.name,
                        availability: t.availability,
                        utcOffsetMinutes: s.utcOffsetMinutes,
                        registrationOpensAt: t.saleOpensAt,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          FFQuantityStepper(
            key: Key('ticket-qty-${t.id}'),
            value: qty,
            min: t.minPerOrder,
            max: t.maxPerOrder,
            enabled: sale,
            canIncrement: !atMax,
            label: context
                .tr('events.register.qty')
                .replaceFirst('{ticket}', t.name),
            addLabel: context.tr('events.register.qty.add'),
            removeLabel: context.tr('events.register.qty.remove'),
            onChanged: sale
                ? (v) {
                    final next = Map<String, int>.from(lines);
                    if (v <= 0) {
                      next.remove(t.id);
                    } else {
                      next[t.id] = v;
                    }
                    onChanged(next);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
