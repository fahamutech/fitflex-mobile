// FFAreaPicker (shop Phase 2 S3, spec §7.4): pick one area ("Based in") or
// many ("Delivers to") from GET /shop/areas, as a tree. In multi mode a
// picked country, region or city covers everything beneath it: those rows
// show ticked and disabled with "Included in {parent}".
import 'package:flutter/material.dart';

import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import '../shop_near_you.dart';

/// Opens the picker. Resolves with the picked ids, or null on Cancel /
/// close. [levels] are the levels that can be picked; the others are shown
/// as context only (e.g. a region above its cities).
Future<Set<String>?> showFFAreaPicker(
  BuildContext context, {
  required String title,
  required List<ShopArea> areas,
  required bool multi,
  required Set<String> levels,
  Set<String> selected = const {},
}) => showFFSheet<Set<String>>(
  context,
  title: title,
  // A centred dialog 480 wide on desktop (spec §12).
  wideDialogWidth: 480,
  child: FFAreaPicker(
    areas: areas,
    multi: multi,
    levels: levels,
    initial: selected,
  ),
);

/// The country, region, city or district word for [level].
String areaLevelLabel(BuildContext context, String level) =>
    context.tr('vendor.areas.level.$level');

/// Ids picked in [selected] plus everything beneath them (multi mode's
/// coverage rule, the same as the server's).
Set<String> coveredAreaIds(Set<String> selected, List<ShopArea> areas) {
  final children = <String, List<String>>{};
  for (final a in areas) {
    if (a.parentId != null) (children[a.parentId!] ??= []).add(a.id);
  }
  final out = <String>{};
  void walk(String id) {
    for (final c in children[id] ?? const <String>[]) {
      if (out.add(c)) walk(c);
    }
  }

  for (final id in selected) {
    walk(id);
  }
  return out;
}

/// The picked areas a summary names: those not already covered by another
/// picked area, in tree order.
List<ShopArea> topPickedAreas(Set<String> selected, List<ShopArea> areas) {
  final covered = coveredAreaIds(selected, areas);
  return [
    for (final a in areas)
      if (selected.contains(a.id) && !covered.contains(a.id)) a,
  ];
}

class FFAreaPicker extends StatefulWidget {
  const FFAreaPicker({
    super.key,
    required this.areas,
    required this.multi,
    required this.levels,
    this.initial = const {},
  });

  final List<ShopArea> areas;
  final bool multi;
  final Set<String> levels;
  final Set<String> initial;

  @override
  State<FFAreaPicker> createState() => _FFAreaPickerState();
}

class _Row {
  const _Row(this.area, this.depth);
  final ShopArea area;
  final int depth;
}

class _FFAreaPickerState extends State<FFAreaPicker> {
  late Set<String> _selected = {...widget.initial};
  String _query = '';
  late final Map<String, ShopArea> _byId = {
    for (final a in widget.areas) a.id: a,
  };

  /// Every area in tree order (parents before their children, siblings by
  /// name), with its depth.
  late final List<_Row> _tree = () {
    final children = <String?, List<ShopArea>>{};
    for (final a in widget.areas) {
      final parent = a.parentId != null && _byId.containsKey(a.parentId)
          ? a.parentId
          : null;
      (children[parent] ??= []).add(a);
    }
    for (final list in children.values) {
      list.sort((a, b) {
        final byLevel = a.depth.compareTo(b.depth);
        return byLevel != 0 ? byLevel : a.name.compareTo(b.name);
      });
    }
    final out = <_Row>[];
    final seen = <String>{};
    void walk(String? parent, int depth) {
      for (final a in children[parent] ?? const <ShopArea>[]) {
        if (!seen.add(a.id)) continue;
        out.add(_Row(a, depth));
        walk(a.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }();

  /// Rows to show: all, or the ones matching the search plus their parents.
  List<_Row> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _tree;
    final keep = <String>{};
    for (final r in _tree) {
      if (!r.area.name.toLowerCase().contains(q)) continue;
      String? id = r.area.id;
      while (id != null && keep.add(id)) {
        id = _byId[id]?.parentId;
      }
    }
    return [
      for (final r in _tree)
        if (keep.contains(r.area.id)) r,
    ];
  }

  ShopArea? _coveringParent(ShopArea area) {
    var id = area.parentId;
    while (id != null) {
      if (_selected.contains(id)) return _byId[id];
      id = _byId[id]?.parentId;
    }
    return null;
  }

  void _toggle(ShopArea area) {
    setState(() {
      if (!widget.multi) {
        _selected = {area.id};
      } else if (!_selected.remove(area.id)) {
        _selected.add(area.id);
      }
    });
  }

  String _name(BuildContext context, ShopArea a, String lang) =>
      a.level == 'country'
      ? context
            .tr('vendor.areas.nationwide')
            .replaceAll('{area}', a.nameIn(lang))
      : a.nameIn(lang);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final rows = _visible;
    final summary = topPickedAreas(
      _selected,
      widget.areas,
    ).map((a) => _name(context, a, lang)).join(', ');
    return Column(
      key: const Key('ff-area-picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FFTextField(
          key: const Key('ff-area-search'),
          hint: context.tr('vendor.areas.search'),
          prefixIcon: const Icon(Icons.search, size: 20),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        for (final r in rows) _row(context, r, lang),
        const SizedBox(height: FFTokens.spacingSm),
        Semantics(
          liveRegion: true,
          child: Text(
            context
                .tr('vendor.areas.selected')
                .replaceAll(
                  '{areas}',
                  summary.isEmpty
                      ? context.tr('vendor.areas.noneSelected')
                      : summary,
                ),
            key: const Key('ff-area-summary'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        Row(
          children: [
            Expanded(
              child: FFButton(
                key: const Key('ff-area-cancel'),
                label: context.tr('common.cancel'),
                variant: FFButtonVariant.ghost,
                // 48 tall at every width, desktop too (QA2 #2).
                visualDensity: VisualDensity.standard,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: FFButton(
                key: const Key('ff-area-done'),
                label: context.tr('vendor.areas.done'),
                visualDensity: VisualDensity.standard,
                onPressed: () => Navigator.of(context).pop({..._selected}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(BuildContext context, _Row r, String lang) {
    final theme = Theme.of(context);
    final a = r.area;
    final pickable = widget.levels.contains(a.level);
    final cover = widget.multi ? _coveringParent(a) : null;
    final checked = _selected.contains(a.id) || cover != null;
    final enabled = pickable && cover == null;
    final parent = a.parentId == null ? null : _byId[a.parentId];
    final name = _name(context, a, lang);
    final level = areaLevelLabel(context, a.level);
    final label = parent == null
        ? context
              .tr('vendor.areas.a11yRowTop')
              .replaceAll('{area}', name)
              .replaceAll('{level}', level)
        : context
              .tr('vendor.areas.a11yRow')
              .replaceAll('{area}', name)
              .replaceAll('{level}', level)
              .replaceAll('{parent}', parent.nameIn(lang));
    final indent = 16.0 * (r.depth > 4 ? 4 : r.depth);
    final subtitle = cover != null
        ? context
              .tr('vendor.areas.included')
              .replaceAll('{parent}', _name(context, cover, lang))
        : null;
    if (!pickable) {
      // No "Nationwide" heading when only one place is picked (QA #6).
      if (!widget.multi && a.level == 'country') {
        return const SizedBox.shrink();
      }
      // Context only (e.g. the region above its cities in "Based in").
      return Padding(
        padding: EdgeInsetsDirectional.only(start: indent),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: Text(
                name,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final icon = widget.multi
        ? (checked ? Icons.check_box : Icons.check_box_outline_blank)
        : (checked ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    return Semantics(
      key: Key('ff-area-row-${a.id}'),
      button: true,
      // "Included in {parent}" is part of what is read (QA #6).
      label: subtitle == null ? label : '$label, $subtitle',
      // Single mode reads as a radio: checked + mutually exclusive, and
      // selected (QA #6).
      checked: checked,
      selected: widget.multi ? null : checked,
      inMutuallyExclusiveGroup: widget.multi ? null : true,
      enabled: enabled,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? () => _toggle(a) : null,
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: indent),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: enabled
                      ? theme.colorScheme.primary
                      : theme.disabledColor,
                ),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.bodyLarge),
                        if (subtitle != null)
                          Text(subtitle, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
