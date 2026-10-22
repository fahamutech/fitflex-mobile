import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_summary.dart';
import '../../../shared/events/event_time.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';

/// Home "Upcoming events" (events S2 spec §11.1): the two soonest open
/// events as compact rows and a "See all" link. The caller hides it when
/// there are none.
class HomeEventsCard extends StatelessWidget {
  const HomeEventsCard({super.key, required this.events});

  final List<EventSummary> events;

  @override
  Widget build(BuildContext context) {
    final shown = events.take(2).toList();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: context
          .tr('home.events.semantics')
          .replaceFirst('{n}', '${shown.length}'),
      child: FFCard(
        key: const Key('home-events-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      context.tr('home.events.title'),
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                FFButton(
                  key: const Key('home-events-see-all'),
                  label: context.tr('home.events.seeAll'),
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                  onPressed: () => context.push(AppRoutes.memberEvents),
                ),
              ],
            ),
            for (final e in shown)
              _Row(
                key: Key('home-event-${e.id}'),
                event: e,
                lang: lang,
                onTap: () => context.push('${AppRoutes.memberEvents}/${e.id}'),
                muted: cs.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.event,
    required this.lang,
    required this.onTap,
    required this.muted,
  });

  final EventSummary event;
  final String lang;
  final VoidCallback onTap;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final e = event;
    final date = e.startsAt == null
        ? ''
        : eventDayChip(e.startsAt!, e.utcOffsetMinutes, locale: lang);
    final price = e.fromPriceTzs == null
        ? ''
        : e.fromPriceTzs == 0
        ? context.tr('events.card.free')
        : context
              .tr('events.card.from')
              .replaceFirst(
                '{amount}',
                formatCurrency(e.fromPriceTzs!, currency: e.currency),
              );
    return Semantics(
      button: true,
      label: [
        e.title,
        date,
        e.venue.cityLine,
        price,
      ].where((s) => s.isNotEmpty).join(', '),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingSm),
              child: Row(
                children: [
                  if (date.isNotEmpty)
                    FFBadge(label: date, tone: FFBadgeTone.defaultTone),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          [
                            e.venue.cityLine,
                            price,
                          ].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
