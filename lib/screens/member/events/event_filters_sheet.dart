import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_filter.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import 'event_status.dart';

/// Opens the filter sheet (events S2 spec §11.2 item 3) over [initial] and
/// answers the filter the member chose with "Show results", or null when
/// the sheet was dismissed. Choices apply only on "Show results", so a slow
/// network is not asked for every tap.
Future<EventFilter?> showEventFiltersSheet(
  BuildContext context, {
  required EventFilter initial,
  required EventsOptions options,
  int? resultCount,
}) => showFFSheet<EventFilter>(
  context,
  title: context.tr('events.filters.title'),
  child: EventFiltersSheetBody(
    initial: initial,
    options: options,
    resultCount: resultCount,
  ),
);

class EventFiltersSheetBody extends StatefulWidget {
  const EventFiltersSheetBody({
    super.key,
    required this.initial,
    required this.options,
    this.resultCount,
  });

  final EventFilter initial;
  final EventsOptions options;

  /// The current list's count, when known (the primary button says it only
  /// when the sheet's choices still equal the applied filter).
  final int? resultCount;

  @override
  State<EventFiltersSheetBody> createState() => _EventFiltersSheetBodyState();
}

class _EventFiltersSheetBodyState extends State<EventFiltersSheetBody> {
  late EventFilter _f = widget.initial;

  void _set(EventFilter f) => setState(() => _f = f);

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _f.from : _f.to) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    _set(from ? _f.copyWith(from: picked) : _f.copyWith(to: picked));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final count = widget.resultCount;
    final showLabel = count != null && _f.signature == widget.initial.signature
        ? context.tr('events.filters.showCount').replaceFirst('{n}', '$count')
        : context.tr('events.filters.show');

    Widget title(String key) => Padding(
      padding: const EdgeInsets.only(
        top: FFTokens.spacingMd,
        bottom: FFTokens.spacingSm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          context.tr(key),
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Date ───────────────────────────────────────────────
                title('events.filters.date'),
                for (final (range, key) in const [
                  (EventDateRange.anytime, 'events.filters.date.anytime'),
                  (EventDateRange.thisMonth, 'events.filters.date.thisMonth'),
                  (EventDateRange.next3Months, 'events.filters.date.next3'),
                  (EventDateRange.custom, 'events.filters.date.custom'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                    child: FFChoiceTile(
                      key: Key('events-date-${range.name}'),
                      title: context.tr(key),
                      selected: _f.dateRange == range,
                      minHeight: 48,
                      onSelected: () => _set(
                        _f.copyWith(
                          dateRange: range,
                          clearDates: range != EventDateRange.custom,
                        ),
                      ),
                    ),
                  ),
                if (_f.dateRange == EventDateRange.custom)
                  Row(
                    children: [
                      Expanded(
                        child: FFButton(
                          key: const Key('events-date-from'),
                          label:
                              '${context.tr('events.filters.from')}: '
                              '${_f.from == null ? '—' : formatDate(_f.from, locale: lang)}',
                          variant: FFButtonVariant.secondary,
                          icon: Icons.calendar_today_outlined,
                          onPressed: () => _pickDate(from: true),
                        ),
                      ),
                      const SizedBox(width: FFTokens.spacingSm),
                      Expanded(
                        child: FFButton(
                          key: const Key('events-date-to'),
                          label:
                              '${context.tr('events.filters.to')}: '
                              '${_f.to == null ? '—' : formatDate(_f.to, locale: lang)}',
                          variant: FFButtonVariant.secondary,
                          icon: Icons.calendar_today_outlined,
                          onPressed: () => _pickDate(from: false),
                        ),
                      ),
                    ],
                  ),
                // ── Distance ───────────────────────────────────────────
                title('events.filters.distance'),
                Wrap(
                  spacing: FFTokens.spacingXs + 2,
                  children: [
                    for (final d in EventFilter.distanceBuckets)
                      FFFilterChip(
                        key: Key('events-distance-$d'),
                        label: d == 'other'
                            ? context.tr('events.filters.distance.other')
                            : d.toUpperCase(),
                        tone: FFFilterChipTone.tint,
                        selected: _f.distances.contains(d),
                        onSelected: () => _set(
                          _f.copyWith(
                            distances: _f.distances.contains(d)
                                ? ({..._f.distances}..remove(d))
                                : {..._f.distances, d},
                          ),
                        ),
                      ),
                  ],
                ),
                // ── Type ───────────────────────────────────────────────
                title('events.filters.type'),
                Wrap(
                  spacing: FFTokens.spacingXs + 2,
                  children: [
                    for (final t in EventFilter.typeCodes)
                      FFFilterChip(
                        key: Key('events-type-$t'),
                        label: eventTypeLabel(context, t),
                        tone: FFFilterChipTone.tint,
                        selected: _f.types.contains(t),
                        onSelected: () => _set(
                          _f.copyWith(
                            types: _f.types.contains(t)
                                ? ({..._f.types}..remove(t))
                                : {..._f.types, t},
                          ),
                        ),
                      ),
                  ],
                ),
                // ── Location ───────────────────────────────────────────
                title('events.filters.location'),
                FFDropdownField<String>(
                  key: const Key('events-region'),
                  value: _f.region ?? '',
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(context.tr('events.filters.anywhere')),
                    ),
                    for (final r in widget.options.regions)
                      DropdownMenuItem(
                        value: r.code,
                        child: Text(r.name(lang)),
                      ),
                  ],
                  onChanged: (v) => _set(
                    (v ?? '').isEmpty
                        ? _f.copyWith(clearRegion: true)
                        : _f.copyWith(region: v),
                  ),
                ),
                // ── Price ──────────────────────────────────────────────
                title('events.filters.price'),
                Wrap(
                  spacing: FFTokens.spacingXs + 2,
                  children: [
                    for (final (p, key) in const [
                      (EventPriceFilter.any, 'events.filters.price.any'),
                      (EventPriceFilter.free, 'events.filters.price.free'),
                      (
                        EventPriceFilter.under20k,
                        'events.filters.price.under20k',
                      ),
                      (
                        EventPriceFilter.under50k,
                        'events.filters.price.under50k',
                      ),
                    ])
                      FFFilterChip(
                        key: Key('events-price-${p.name}'),
                        label: context.tr(key),
                        tone: FFFilterChipTone.tint,
                        selected: _f.price == p,
                        onSelected: () => _set(_f.copyWith(price: p)),
                      ),
                  ],
                ),
                // ── Registration ───────────────────────────────────────
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    key: const Key('events-open-only'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.tr('events.filters.openOnly'),
                      style: tt.bodyMedium,
                    ),
                    value: _f.openOnly,
                    onChanged: (v) => _set(_f.copyWith(openOnly: v)),
                  ),
                ),
                const SizedBox(height: FFTokens.spacingSm),
              ],
            ),
          ),
        ),
        // ── Footer ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FFTokens.spacingLg,
            FFTokens.spacingSm,
            FFTokens.spacingLg,
            FFTokens.spacingMd,
          ),
          child: Row(
            children: [
              FFButton(
                key: const Key('events-filters-clear'),
                label: context.tr('events.filters.clear'),
                variant: FFButtonVariant.ghost,
                onPressed: () => _set(_f.cleared()),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: FFButton(
                  key: const Key('events-filters-show'),
                  label: showLabel,
                  fullWidth: true,
                  onPressed: () => Navigator.of(context).pop(_f),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
