import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_summary.dart';
import '../../../shared/events/event_time.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/tone_theme.dart';
import 'event_status.dart';

/// One event in the discovery list (events S2 spec §11.2 "Card anatomy").
/// The whole card is one button with a composed label; its children are
/// excluded from semantics. The optional Save heart (favourites flag) sits
/// on top with its own semantics.
class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.saved,
    this.onToggleSave,
  });

  final EventSummary event;
  final VoidCallback onTap;

  /// Null hides the heart (favourites off).
  final bool? saved;
  final VoidCallback? onToggleSave;

  /// Width of the thumbnail the server sends (§11.8).
  static const thumbWidth = 600.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final cs = theme.colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final e = event;
    final dateChip = e.startsAt == null
        ? ''
        : eventDayChip(e.startsAt!, e.utcOffsetMinutes, locale: lang);
    final price = _priceLine(context);
    final status = availabilityLabel(context, e);
    final distances = e.distancesM.map(distanceLabel).toList();
    final shown = distances.take(4).toList();
    final more = distances.length - shown.length;

    final body = FFCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(FFTokens.radiusXl),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _EventThumb(event: e),
                    if (dateChip.isNotEmpty)
                      Positioned(
                        left: FFTokens.spacingSm + 2,
                        bottom: FFTokens.spacingSm + 2,
                        child: FFBadge(
                          key: const Key('event-card-date'),
                          label: dateChip,
                          tone: FFBadgeTone.onPhoto,
                        ),
                      ),
                    Positioned(
                      right: FFTokens.spacingSm + 2,
                      top: FFTokens.spacingSm + 2,
                      // The longest pill ("Inafungwa karibuni") gets room.
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: EventAvailabilityPill(event: e),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: FFTokens.spacingXs),
                  if (e.venue.cityLine.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: FFTokens.iconSm,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: FFTokens.spacingXs),
                        Expanded(
                          child: Text(
                            e.venue.cityLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (shown.isNotEmpty) ...[
                    const SizedBox(height: FFTokens.spacingSm),
                    Wrap(
                      spacing: FFTokens.spacingXs + 2,
                      runSpacing: FFTokens.spacingXs,
                      children: [
                        for (final d in shown) FFPill(label: d),
                        if (more > 0) FFPill(label: '+$more'),
                      ],
                    ),
                  ],
                  const SizedBox(height: FFTokens.spacingSm),
                  Text(
                    price,
                    key: const Key('event-card-price'),
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (e.organizer.name.isNotEmpty) ...[
                    const SizedBox(height: FFTokens.spacingXs),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.organizer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (e.organizer.verified) ...[
                          const SizedBox(width: FFTokens.spacingXs),
                          Icon(
                            Icons.verified,
                            key: const Key('event-card-verified'),
                            size: FFTokens.iconSm,
                            color: FFToneTheme.of(context).success.fg,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final label = [
      e.title,
      if (dateChip.isNotEmpty) dateChip,
      if (e.venue.city.isNotEmpty) e.venue.city,
      price,
      status,
      if (e.organizer.verified) context.tr('events.card.verifiedOrganizer'),
    ].join(', ');

    final card = Semantics(
      key: Key('event-card-${e.id}'),
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(child: body),
    );
    if (saved == null || onToggleSave == null) return card;
    return Stack(
      children: [
        card,
        Positioned(
          left: FFTokens.spacingXs,
          top: FFTokens.spacingXs,
          child: _SaveHeart(
            key: Key('event-save-${e.id}'),
            saved: saved!,
            onPressed: onToggleSave!,
            onPhoto: true,
          ),
        ),
      ],
    );
  }

  String _priceLine(BuildContext context) {
    final p = event.fromPriceTzs;
    if (p == null) return '';
    if (p == 0) return context.tr('events.card.free');
    return context
        .tr('events.card.from')
        .replaceFirst('{amount}', formatCurrency(p, currency: event.currency));
  }
}

/// The 16:9 thumbnail, or the placeholder when there is none or it fails:
/// slate ground, a runner icon and the type label (§11.2).
class _EventThumb extends StatelessWidget {
  const _EventThumb({required this.event});

  final EventSummary event;

  @override
  Widget build(BuildContext context) {
    final placeholder = EventImagePlaceholder(type: event.type);
    final url = event.heroThumbUrl;
    if (url == null) return placeholder;
    return FFRemoteImage(
      src: url,
      width: EventCard.thumbWidth,
      height: EventCard.thumbWidth * 9 / 16,
      fit: BoxFit.cover,
      fallback: placeholder,
    );
  }
}

/// Slate ground with a runner icon and the type label. Used by the card and
/// by the detail when the event has no cover (hero flag off).
class EventImagePlaceholder extends StatelessWidget {
  const EventImagePlaceholder({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('event-image-placeholder'),
    color: FFTokens.heroPlaceholder,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_run, size: 40, color: Colors.white),
          if (type.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              eventTypeLabel(context, type),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: Colors.white),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The Save heart (favourites flag, §11.7): a 44dp+ toggle with a tooltip.
class _SaveHeart extends StatelessWidget {
  const _SaveHeart({
    super.key,
    required this.saved,
    required this.onPressed,
    this.onPhoto = false,
  });

  final bool saved;
  final VoidCallback onPressed;
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final tip = context.tr(saved ? 'events.saved' : 'events.save');
    return Semantics(
      toggled: saved,
      child: IconButton(
        tooltip: tip,
        onPressed: onPressed,
        style: onPhoto
            ? IconButton.styleFrom(
                backgroundColor: FFTokens.heroScrim.withValues(alpha: 0.6),
                foregroundColor: Colors.white,
              )
            : null,
        icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
      ),
    );
  }
}

/// The hero's Save heart for the detail page (same control, exported).
class EventSaveButton extends StatelessWidget {
  const EventSaveButton({
    super.key,
    required this.saved,
    required this.onPressed,
    this.onPhoto = false,
  });

  final bool saved;
  final VoidCallback onPressed;
  final bool onPhoto;

  @override
  Widget build(BuildContext context) =>
      _SaveHeart(saved: saved, onPressed: onPressed, onPhoto: onPhoto);
}
