import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_summary.dart';
import '../../../shared/events/event_time.dart';
import '../../../shared/i18n.dart';

/// `availability` → pill tone and label (events S2 spec §11.3). The pill
/// always carries text; colour alone never signals a state.
FFBadgeTone availabilityTone(EventAvailability a) => switch (a) {
  EventAvailability.open => FFBadgeTone.success,
  EventAvailability.closingSoon => FFBadgeTone.fuel,
  EventAvailability.soldOut => FFBadgeTone.gray,
  EventAvailability.closed => FFBadgeTone.gray,
  EventAvailability.notYetOpen => FFBadgeTone.defaultTone,
  EventAvailability.cancelled => FFBadgeTone.danger,
  EventAvailability.inProgress => FFBadgeTone.gray,
  EventAvailability.completed => FFBadgeTone.gray,
};

/// The pill's words for [e]'s availability in the active language.
/// `not_yet_open` carries the opening date in the event's zone.
String availabilityLabel(BuildContext context, EventSummary e) {
  final key = 'events.availability.${e.availability.wire}';
  final text = context.tr(key);
  if (e.availability != EventAvailability.notYetOpen) return text;
  final opens = e.registrationOpensAt;
  final lang = FFLocaleScope.of(context).locale.languageCode;
  final date = opens == null
      ? '—'
      : eventDayChip(opens, e.utcOffsetMinutes, locale: lang);
  return text.replaceFirst('{date}', date);
}

/// The availability pill.
class EventAvailabilityPill extends StatelessWidget {
  const EventAvailabilityPill({super.key, required this.event});

  final EventSummary event;

  @override
  Widget build(BuildContext context) => FFBadge(
    key: Key('event-pill-${event.availability.wire}'),
    label: availabilityLabel(context, event),
    tone: availabilityTone(event.availability),
  );
}

/// "Fuel" text colour for the theme: `fuel` on light, `fuelOnDark` on dark
/// (spec §11.10).
Color fuelTextColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? FFTokens.fuelOnDark
    : FFTokens.fuel;

/// `events.type.<type>` or the raw word for one the app does not know.
String eventTypeLabel(BuildContext context, String type) {
  final key = 'events.type.$type';
  final text = context.tr(key);
  return text == key ? type : text;
}
