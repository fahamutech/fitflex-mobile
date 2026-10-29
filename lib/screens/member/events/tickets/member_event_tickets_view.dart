import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_ticket.dart';
import '../../../../shared/events/event_time.dart';
import '../../../../shared/events/events_cache.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';

/// The ticket wallet's list state (events S4 spec §5.4): page 1 from
/// `GET /me/event-tickets`, more on scroll, the last good page when there
/// is no signal. The list never carries a token.
class EventTicketsController extends ChangeNotifier {
  EventTicketsController({required this.api, this.pageSize = 20});

  final ApiClient api;
  final int pageSize;

  List<EventTicketRow> items = [];
  String? nextCursor;
  bool loading = true;
  bool loadingMore = false;
  bool loaded = false;
  Object? error;
  DateTime? cachedAt;

  bool get hasActive => items.any((t) => t.isActive);

  Future<void> load() async {
    loading = items.isEmpty;
    error = null;
    cachedAt = null;
    notifyListeners();
    try {
      final page = await api.listEventTickets(limit: pageSize);
      items = _rows(page);
      nextCursor = page['nextCursor']?.toString();
      loading = false;
      loaded = true;
      EventsCache.putMine('tickets', page);
    } catch (e) {
      if (isNetworkError(e)) {
        final cached = await EventsCache.getMine('tickets');
        if (cached != null) {
          items = _rows(cached.$2);
          cachedAt = cached.$1;
          nextCursor = null;
          loading = false;
          loaded = true;
          notifyListeners();
          return;
        }
      }
      loading = false;
      loaded = true;
      error = e;
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (nextCursor == null || loadingMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await api.listEventTickets(
        cursor: nextCursor,
        limit: pageSize,
      );
      items = [...items, ..._rows(page)];
      nextCursor = page['nextCursor']?.toString();
    } catch (_) {
      // The next scroll tries again.
    }
    loadingMore = false;
    notifyListeners();
  }

  static List<EventTicketRow> _rows(Map<String, dynamic> page) => [
    for (final t in page['items'] is List ? page['items'] as List : [])
      if (t is Map) EventTicketRow.fromJson(t),
  ];
}

/// The "Tickets" segment of `MemberEventOrdersPage`: upcoming tickets first,
/// then past and cancelled ones. Rendered inside the page's scroll view.
class MemberEventTicketsView extends StatelessWidget {
  const MemberEventTicketsView({super.key, required this.controller, this.now});

  final EventTicketsController controller;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final c = controller;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final clock = now ?? DateTime.now();
    if (c.loading) {
      return [
        FFSkeletonList(
          key: const Key('tickets-loading'),
          count: 3,
          semanticLabel: context.tr('common.loading'),
        ),
      ];
    }
    if (c.error != null && c.items.isEmpty) {
      return [
        FFErrorState(
          key: const Key('tickets-error'),
          message: errorMessage(FFLocaleScope.of(context), c.error!),
          retryLabel: context.tr('common.retry'),
          onRetry: c.load,
        ),
      ];
    }
    if (c.items.isEmpty) {
      return [
        FFEmptyState(
          key: const Key('tickets-empty'),
          icon: Icons.confirmation_number,
          title: context.tr('events.tickets.empty.title'),
          body: context.tr('events.tickets.empty.body'),
          action: FFButton(
            key: const Key('tickets-browse'),
            label: context.tr('events.mine.empty.action'),
            variant: FFButtonVariant.secondary,
            onPressed: () => context.go(AppRoutes.memberEvents),
          ),
        ),
      ];
    }
    final upcoming = [
      for (final t in c.items)
        if (t.isActive && !t.isPast(clock)) t,
    ];
    final past = [
      for (final t in c.items)
        if (!(t.isActive && !t.isPast(clock))) t,
    ];
    return [
      if (c.cachedAt != null)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('tickets-offline'),
            tone: FFAlertTone.warning,
            message: context
                .tr('events.offline.savedCopy')
                .replaceFirst(
                  '{time}',
                  formatDateTime(c.cachedAt, locale: lang),
                ),
          ),
        ),
      if (upcoming.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.tickets.section.upcoming')),
        for (final t in upcoming) _TicketCard(ticket: t),
      ],
      if (past.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.tickets.section.past')),
        for (final t in past) _TicketCard(ticket: t),
      ],
      if (c.loadingMore)
        const Padding(
          padding: EdgeInsets.all(FFTokens.spacingMd),
          child: Center(child: FFSpinner()),
        ),
    ];
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});

  final EventTicketRow ticket;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final e = t.event;
    final when = (t.categoryStartsAt ?? e?.startsAt) == null
        ? ''
        : eventDateTime(
            (t.categoryStartsAt ?? e!.startsAt)!,
            e?.utcOffsetMinutes ?? 0,
            e?.timezoneAbbr ?? '',
            locale: lang,
          );
    final (stateLabel, stateTone) = t.isActive
        ? (context.tr('events.ticket.ready'), FFBadgeTone.success)
        : (
            context.tr(
              t.eventCancelled
                  ? 'events.ticket.revoked.event_cancelled'
                  : 'events.ticket.revoked.cancelled',
            ),
            FFBadgeTone.gray,
          );
    final relation = switch (t.relation) {
      'self' => context.tr('events.participant.you'),
      'purchased' => context.tr('events.mine.byYou'),
      'claimed' => context.tr('events.claim.chip.claimed'),
      _ => '',
    };
    final category = [
      t.categoryName,
      t.ticketTypeName,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Semantics(
      button: true,
      label: [
        e?.title ?? '',
        t.categoryName,
        t.participantName,
        stateLabel,
      ].where((s) => s.isNotEmpty).join(', '),
      child: FFCard(
        key: Key('ticket-card-${t.registrationId}'),
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () =>
              context.push(AppRoutes.memberEventTicketPath(t.registrationId)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e?.title ?? '',
                      style: tt.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (when.isNotEmpty)
                      Text(
                        when,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    if (category.isNotEmpty)
                      Text(category, style: tt.bodyMedium),
                    Text(
                      [
                        t.participantName,
                        if (t.bibNumber != null)
                          context
                              .tr('events.ticket.bib')
                              .replaceFirst('{number}', t.bibNumber!),
                      ].join(' · '),
                      key: Key('ticket-subtitle-${t.registrationId}'),
                      style: tt.bodyMedium,
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    Wrap(
                      spacing: FFTokens.spacingSm,
                      runSpacing: FFTokens.spacingXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FFBadge(label: stateLabel, tone: stateTone),
                        if (relation.isNotEmpty)
                          FFBadge(label: relation, tone: FFBadgeTone.brand),
                        if (t.displayCode.isNotEmpty)
                          Text(
                            t.displayCode,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        context.tr('events.ticket.show'),
                        style: tt.labelLarge?.copyWith(color: cs.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
