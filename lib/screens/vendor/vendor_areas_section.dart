// Shop Phase 2 S3: "Where you sell" on the vendor business profile
// ("Based in" and "Delivers to"), spec §7.4. Shown only when the server
// says `merch.shopAreas: true` (SHOP_NEAR_YOU on).
//
// Contract (fitflex-functions docs/shop-near-you-api.md): PUT
// /vendor/profile takes `cityId` (a city or district), `regionId` (a
// region; must contain the city) and `deliveryAreaIds` (any level; the
// country id = nationwide; `[]` = no delivery). Leaving a field out keeps
// the stored value, so nothing is sent until the areas have loaded.
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/shop_near_you.dart';
import '../../shared/widgets/ff_area_picker.dart';

enum VendorAreasLoad { loading, ready, none, failed }

/// The section's values. The form asks it for the request fields.
class VendorAreasController extends ChangeNotifier {
  VendorAreasController(Map<String, dynamic> profile)
    : cityId = _id(profile['cityId']),
      deliveryIds = {
        for (final id
            in profile['deliveryAreaIds'] is List
                ? profile['deliveryAreaIds'] as List
                : const [])
          if (_id(id) != null) _id(id)!,
      },
      backfilled = profile['areasSource'] == 'backfill';

  static String? _id(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  VendorAreasLoad load = VendorAreasLoad.loading;
  List<ShopArea> areas = const [];
  String? cityId;
  Set<String> deliveryIds;

  /// The server guessed these from the free-text address (migration).
  final bool backfilled;

  /// Publish was tapped without "Based in".
  bool showMissing = false;

  ShopArea? byId(String? id) {
    if (id == null) return null;
    for (final a in areas) {
      if (a.id == id) return a;
    }
    return null;
  }

  void setCity(String? id) {
    cityId = id;
    if (id != null) showMissing = false;
    notifyListeners();
  }

  void setDelivery(Set<String> ids) {
    deliveryIds = ids;
    notifyListeners();
  }

  void loaded(VendorAreasLoad state, [List<ShopArea> list = const []]) {
    load = state;
    areas = list;
    notifyListeners();
  }

  /// "Based in" is needed once the pickers are shown.
  bool get missingBasedIn => load == VendorAreasLoad.ready && cityId == null;

  /// The region "Based in" sits in (walking up from a district or city).
  String? get regionId {
    var area = byId(cityId);
    final seen = <String>{};
    while (area != null && seen.add(area.id)) {
      if (area.level == 'region') return area.id;
      area = byId(area.parentId);
    }
    return null;
  }

  /// The fields for PUT /vendor/profile, or none before the areas loaded
  /// (leaving them out keeps what is stored).
  Map<String, dynamic> body() {
    if (load != VendorAreasLoad.ready) return const {};
    return {
      'cityId': cityId,
      'regionId': ?regionId,
      'deliveryAreaIds': [
        for (final a in areas)
          if (deliveryIds.contains(a.id)) a.id,
      ],
    };
  }

  void flagMissing() {
    showMissing = true;
    notifyListeners();
  }
}

class VendorAreasSection extends StatefulWidget {
  const VendorAreasSection({super.key, required this.controller});
  final VendorAreasController controller;

  @override
  State<VendorAreasSection> createState() => _VendorAreasSectionState();
}

class _VendorAreasSectionState extends State<VendorAreasSection> {
  VendorAreasController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    _c.loaded(VendorAreasLoad.loading);
    try {
      final list = await ShopAreas.loadOrThrow(AppScope.of(context).api);
      _c.loaded(
        list.isEmpty ? VendorAreasLoad.none : VendorAreasLoad.ready,
        list,
      );
    } catch (_) {
      _c.loaded(VendorAreasLoad.failed);
    }
  }

  String _lang(BuildContext context) =>
      FFLocaleScope.of(context).locale.languageCode;

  /// "Kinondoni, Dar es Salaam" for a district, the name for a city.
  String _basedInName(BuildContext context, ShopArea area) {
    final lang = _lang(context);
    final parent = _c.byId(area.parentId);
    return area.level == 'district' && parent != null
        ? '${area.nameIn(lang)}, ${parent.nameIn(lang)}'
        : area.nameIn(lang);
  }

  String _areaName(BuildContext context, ShopArea a) => a.level == 'country'
      ? context
            .tr('vendor.areas.nationwide')
            .replaceAll('{area}', a.nameIn(_lang(context)))
      : a.nameIn(_lang(context));

  Future<void> _pickBasedIn() async {
    final picked = await showFFAreaPicker(
      context,
      title: context.tr('vendor.areas.basedIn'),
      areas: _c.areas,
      multi: false,
      levels: const {'city', 'district'},
      selected: {?_c.cityId},
    );
    if (picked != null && picked.isNotEmpty) _c.setCity(picked.first);
  }

  Future<void> _pickDelivery() async {
    final picked = await showFFAreaPicker(
      context,
      title: context.tr('vendor.areas.deliversTo'),
      areas: _c.areas,
      multi: true,
      levels: const {'country', 'region', 'city', 'district'},
      selected: _c.deliveryIds,
    );
    if (picked != null) _c.setDelivery(picked);
  }

  Widget _row({
    required Key key,
    required String text,
    String? sub,
    bool error = false,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(text, style: theme.textTheme.bodyLarge),
                      if (sub != null)
                        Text(
                          sub,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: error ? theme.colorScheme.error : null,
                          ),
                        ),
                    ],
                  ),
                ),
                const ExcludeSemantics(child: Icon(Icons.chevron_right)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
      child: Semantics(
        header: true,
        child: Text(
          context.tr('vendor.areas.title'),
          style: theme.textTheme.titleSmall,
        ),
      ),
    );
    switch (_c.load) {
      case VendorAreasLoad.loading:
        return Column(
          key: const Key('vendor-areas-loading'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: FFTokens.spacingSm),
            const FFSkeletonLine(),
          ],
        );
      case VendorAreasLoad.none:
        return Column(
          key: const Key('vendor-areas-none'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            Text(
              context.tr('vendor.areas.none'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        );
      case VendorAreasLoad.failed:
        return Column(
          key: const Key('vendor-areas-failed'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            Text(
              context.tr('vendor.areas.failed'),
              style: theme.textTheme.bodyMedium,
            ),
            FFButton(
              key: const Key('vendor-areas-retry'),
              label: context.tr('common.retry'),
              variant: FFButtonVariant.ghost,
              visualDensity: VisualDensity.standard,
              onPressed: _load,
            ),
          ],
        );
      case VendorAreasLoad.ready:
        break;
    }
    final city = _c.byId(_c.cityId);
    final picked = topPickedAreas(_c.deliveryIds, _c.areas);
    final names = [for (final a in picked.take(2)) _areaName(context, a)];
    final more = picked.length > 2
        ? ' ${context.tr('vendor.areas.deliversMore').replaceAll('{n}', '${picked.length - 2}')}'
        : '';
    return Column(
      key: const Key('vendor-areas'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        _row(
          key: const Key('vendor-areas-based-in'),
          text: city == null
              ? context.tr('vendor.areas.basedIn')
              : context
                    .tr('vendor.areas.basedInRow')
                    .replaceAll('{area}', _basedInName(context, city)),
          sub: _c.showMissing && city == null
              ? context.tr('vendor.areas.basedInMissing')
              : null,
          error: _c.showMissing && city == null,
          onTap: _pickBasedIn,
        ),
        _row(
          key: const Key('vendor-areas-delivers'),
          text: picked.isEmpty
              ? context.tr('vendor.areas.deliversTo')
              : '${context.tr('vendor.areas.deliversRow').replaceAll('{areas}', names.join(', '))}$more',
          sub: picked.isEmpty ? context.tr('vendor.areas.deliversEmpty') : null,
          onTap: _pickDelivery,
        ),
      ],
    );
  }
}
