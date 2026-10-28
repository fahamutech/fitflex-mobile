// Shop Phase 2 S3: the "Popular near you" invite card, the location
// rationale sheet, turning near-you on and off, the location line in the Why
// and Privacy sheets, and the "Delivers to your area" badge.
// Spec: docs/design/shop-home-phase2.md §7.1–7.3, §6.3 item 5, §10.7.
//
// The rationale sheet always comes before the OS / browser prompt, and is
// shown even when the OS already lets FitFlex read the location (for gyms):
// the shop is a different use (O-7).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../api_client.dart';
import '../../components/components.dart';
import '../../design_tokens.dart';
import '../../i18n.dart';
import '../../shop_near_you.dart';
import '../ff_area_picker.dart';
import 'shop_focus_ring.dart';

/// The card in the near-you slot, before the person has answered.
class ShopNearYouInviteCard extends StatelessWidget {
  const ShopNearYouInviteCard({
    super.key,
    required this.onUse,
    required this.onNotNow,
    this.offline = false,
  });

  final VoidCallback onUse;
  final VoidCallback onNotNow;

  /// No connection: the button is disabled with "Needs internet".
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        // Desktop: at most 560 wide, left-aligned (spec §12).
        constraints: const BoxConstraints(maxWidth: 560, minHeight: 96),
        child: FFCard(
          key: const Key('shop-near-you-invite'),
          margin: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          padding: const EdgeInsets.fromLTRB(
            FFTokens.spacingMd,
            FFTokens.spacingSm,
            0,
            FFTokens.spacingMd,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.near_me_outlined,
                    size: 24,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Semantics(
                      header: true,
                      child: Text(
                        context.tr('shop.near.inviteTitle'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    Text(
                      context.tr('shop.near.inviteBody'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: FFTokens.spacingSm),
                    FFButton(
                      key: const Key('shop-near-you-use'),
                      label: context.tr('shop.near.use'),
                      variant: FFButtonVariant.secondary,
                      // 48 tall at every width (QA #3).
                      visualDensity: VisualDensity.standard,
                      icon: Icons.my_location_outlined,
                      onPressed: offline ? null : onUse,
                    ),
                    if (offline)
                      Padding(
                        padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                        child: Text(
                          context.tr('shop.near.offline'),
                          key: const Key('shop-near-you-offline'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('shop-near-you-not-now'),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  visualDensity: VisualDensity.standard,
                ),
                tooltip: context.tr('shop.near.notNow'),
                icon: const Icon(Icons.close),
                onPressed: onNotNow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The in-app rationale (spec §7.2). Resolves true for "Use my location",
/// false for "Not now", null when closed without an answer.
Future<bool?> showShopLocationRationale(
  BuildContext context, {
  required bool alreadyAllowed,
}) => showFFSheet<bool>(
  context,
  title: context.tr('shop.near.sheetTitle'),
  // A centred dialog 480 wide on desktop (QA #11).
  wideDialogWidth: 480,
  child: _RationaleBody(alreadyAllowed: alreadyAllowed),
);

class _RationaleBody extends StatelessWidget {
  const _RationaleBody({required this.alreadyAllowed});
  final bool alreadyAllowed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget point(IconData icon, String key) => Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: Text(
              context.tr(key),
              key: Key('shop-location-$key'),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
    return Column(
      key: const Key('shop-location-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        point(Icons.location_city_outlined, 'shop.near.point1'),
        point(Icons.phonelink_lock_outlined, 'shop.near.point2'),
        point(Icons.toggle_off_outlined, 'shop.near.point3'),
        if (alreadyAllowed)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Text(
              context.tr('shop.near.alreadyAllowed'),
              key: const Key('shop-location-already'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        Text(
          context.tr('privacy.shop.draft'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        // 48 tall at every width (QA #3); two-tone focus rings (QA #7).
        ShopFocusRing(
          onPhoto: true,
          builder: (node) => FFButton(
            key: const Key('shop-location-use'),
            focusNode: node,
            label: context.tr('shop.near.use'),
            fullWidth: true,
            visualDensity: VisualDensity.standard,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        ShopFocusRing(
          onPhoto: true,
          builder: (node) => FFButton(
            key: const Key('shop-location-not-now'),
            focusNode: node,
            label: context.tr('shop.near.notNow'),
            variant: FFButtonVariant.ghost,
            fullWidth: true,
            visualDensity: VisualDensity.standard,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ),
      ],
    );
  }
}

/// Turning near-you on and off. Every path keeps the position inside
/// [detectShopArea]; only the area's id and name are kept and sent.
class ShopNearYouFlow {
  ShopNearYouFlow._();

  static String? _uid(BuildContext context) =>
      AppScope.of(context).auth.user?['id']?.toString();

  /// "Not now" on the card or the sheet: nothing until turned on again.
  static Future<void> notNow(BuildContext context) => ShopNearYouStore.save(
    _uid(context),
    const ShopNearYouState(choice: ShopNearYouChoice.off),
  );

  /// "Turn off": forget the area; nothing is read again.
  static Future<void> turnOff(BuildContext context) => notNow(context);

  /// Rationale sheet first, then (only if needed) the OS prompt, one
  /// low-accuracy fix and the area worked out on the phone. Says what
  /// happened in a snackbar. Returns the new state, or null when the person
  /// closed the sheet without answering.
  ///
  /// [onLocating] is called once the person said yes, while the area is
  /// being worked out (the Shop home shows card shapes in the slot).
  static Future<ShopNearYouState?> turnOn(
    BuildContext context, {
    VoidCallback? onLocating,
  }) async {
    final scope = AppScope.of(context);
    final uid = _uid(context);
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final lang = locale.locale.languageCode;
    final locator = shopLocator;
    var alreadyAllowed = false;
    try {
      // Only reads the current permission: never prompts.
      alreadyAllowed = await locator.check() == ShopLocationAccess.granted;
    } catch (_) {}
    if (!context.mounted) return null;
    final use = await showShopLocationRationale(
      context,
      alreadyAllowed: alreadyAllowed,
    );
    if (use == null) return null;
    if (!use) {
      const off = ShopNearYouState(choice: ShopNearYouChoice.off);
      await ShopNearYouStore.save(uid, off);
      return off;
    }
    onLocating?.call();
    return _locate(
      api: scope.api,
      uid: uid,
      snack: snack,
      locale: locale,
      lang: lang,
      locator: locator,
    );
  }

  /// After a yes on the rationale sheet: the area list, the OS prompt (only
  /// if needed), one fix and the area. When the area list can't be fetched
  /// (no connection, 5xx) nothing changes and the snackbar offers Try again
  /// (#6), which runs this again without the sheet.
  static Future<ShopNearYouState> _locate({
    required ApiClient api,
    required String? uid,
    required FFSnackMessenger snack,
    required FFLocale locale,
    required String lang,
    required ShopLocator locator,
  }) async {
    final areas = await ShopAreas.tryLoad(api);
    if (areas == null) {
      snack.info(
        locale.t('shop.near.failed'),
        actionLabel: locale.t('common.retry'),
        onAction: () => unawaited(
          _locate(
            api: api,
            uid: uid,
            snack: snack,
            locale: locale,
            lang: lang,
            locator: locator,
          ),
        ),
      );
      return ShopNearYouStore.peek(uid) ?? ShopNearYouState.empty;
    }
    final (outcome, area) = await detectShopArea(
      areas: areas,
      ask: true,
      locator: locator,
    );
    ShopNearYouStore.markRead(uid);
    final ShopNearYouState next;
    switch (outcome) {
      case ShopAreaOutcome.found:
        next = ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: area!.id,
          areaName: area.nameIn(lang),
        );
      case ShopAreaOutcome.noArea:
        next = const ShopNearYouState(choice: ShopNearYouChoice.on);
        snack.info(locale.t('shop.near.noArea'));
      case ShopAreaOutcome.unavailable:
        // Stays on: tried again next session.
        next = const ShopNearYouState(choice: ShopNearYouChoice.on);
        snack.info(locale.t('shop.near.failed'));
      case ShopAreaOutcome.denied:
        next = const ShopNearYouState(choice: ShopNearYouChoice.off);
        snack.info(locale.t('shop.near.denied'));
      case ShopAreaOutcome.deniedForever:
        next = const ShopNearYouState(choice: ShopNearYouChoice.off);
        if (locator.canOpenSettings) {
          snack.info(
            locale.t('shop.near.denied'),
            actionLabel: locale.t('shop.near.openSettings'),
            onAction: () => locator.openAppSettings(),
          );
        } else {
          snack.info(
            '${locale.t('shop.near.denied')} '
            '${locale.t('shop.near.browserBlocked')}',
          );
        }
      case ShopAreaOutcome.servicesOff:
        // Nothing was refused: the card stays so they can try again.
        snack.info(locale.t('shop.near.servicesOff'));
        return ShopNearYouStore.peek(uid) ?? ShopNearYouState.empty;
    }
    await ShopNearYouStore.save(uid, next);
    return next;
  }

  /// Once a session, for an account that turned near-you on: read the
  /// position again (never prompting) and update the area. A permission
  /// taken back in the OS turns near-you off, silently. Returns whether
  /// anything changed.
  static Future<bool> refresh(BuildContext context, String lang) async {
    final uid = _uid(context);
    final api = AppScope.of(context).api;
    final state = await ShopNearYouStore.load(uid);
    if (state.choice != ShopNearYouChoice.on || state.manual) return false;
    if (ShopNearYouStore.readThisSession(uid)) return false;
    ShopNearYouStore.markRead(uid);
    final areas = await ShopAreas.tryLoad(api);
    // No list (offline) or none at all: keep what is kept; next session.
    if (areas == null || areas.isEmpty) return false;
    final (outcome, area) = await detectShopArea(areas: areas, ask: false);
    final ShopNearYouState next;
    switch (outcome) {
      case ShopAreaOutcome.found:
        if (area!.id == state.areaId) return false;
        next = ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: area.id,
          areaName: area.nameIn(lang),
        );
      case ShopAreaOutcome.noArea:
        if (state.areaId == null) return false;
        next = const ShopNearYouState(choice: ShopNearYouChoice.on);
      case ShopAreaOutcome.denied || ShopAreaOutcome.deniedForever:
        next = const ShopNearYouState(choice: ShopNearYouChoice.off);
      case ShopAreaOutcome.unavailable || ShopAreaOutcome.servicesOff:
        // Keep the area last worked out; try again next session.
        return false;
    }
    await ShopNearYouStore.save(uid, next);
    return true;
  }

  /// "Change area": pick a city or district by hand. The position is then
  /// not read again until location is turned on again.
  static Future<void> changeArea(BuildContext context) async {
    final api = AppScope.of(context).api;
    final uid = _uid(context);
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final lang = locale.locale.languageCode;
    List<ShopArea> areas;
    try {
      areas = await ShopAreas.loadOrThrow(api);
    } catch (_) {
      snack.error(locale.t('vendor.areas.failed'));
      return;
    }
    if (!context.mounted) return;
    final current = ShopNearYouStore.peek(uid)?.areaId;
    // Only areas the server lets stand for "where you are" (QA #2):
    // locatable cities and districts, with their parents for context.
    final picked = await showFFAreaPicker(
      context,
      title: context.tr('shop.near.pickArea'),
      areas: locatableWithParents(areas, const {'city', 'district'}),
      multi: false,
      levels: const {'city', 'district'},
      selected: {?current},
    );
    if (picked == null || picked.isEmpty) return;
    final area = areas.firstWhere((a) => a.id == picked.first);
    await ShopNearYouStore.save(
      uid,
      ShopNearYouState(
        choice: ShopNearYouChoice.on,
        areaId: area.id,
        areaName: area.nameIn(lang),
        manual: true,
      ),
    );
  }
}

/// "Popular near you: On · {area}" with Change area / Turn off, or
/// "Popular near you: Off" with Turn on (spec §6.3 item 5). Shown in the
/// Why sheet and the Privacy sheet while near-you is available.
class ShopNearYouLine extends StatefulWidget {
  const ShopNearYouLine({
    super.key,
    this.onChanged,
    this.serverArea,
    this.inHome = false,
  });

  /// The area the last Shop home answer was built for (`nearYou.areaId`
  /// and its name).
  final ({String id, String name})? serverArea;

  /// In the Shop home's Why sheet: only the area the server echoed is
  /// named; none echoed means "No sellers listed for your area yet" (#5).
  /// Elsewhere (Privacy) the name comes from GET /shop/areas.
  final bool inHome;

  /// After any change (the Shop home reloads).
  final VoidCallback? onChanged;

  @override
  State<ShopNearYouLine> createState() => _ShopNearYouLineState();
}

class _ShopNearYouLineState extends State<ShopNearYouLine> {
  ShopNearYouState? _state;
  bool _busy = false;

  /// The kept area's name from /shop/areas (Privacy sheet).
  String? _listedName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final scope = AppScope.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final state = await ShopNearYouStore.load(
      scope.auth.user?['id']?.toString(),
    );
    String? name;
    if (!widget.inHome && state.areaId != null) {
      final areas = await ShopAreas.tryLoad(scope.api) ?? const [];
      for (final a in areas) {
        if (a.id == state.areaId) name = a.nameIn(lang);
      }
    }
    if (mounted) {
      setState(() {
        _state = state;
        _listedName = name;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) return const SizedBox(height: 48);
    final theme = Theme.of(context);
    final on = state.choice == ShopNearYouChoice.on;
    final server = widget.serverArea;
    final area = widget.inHome
        ? (server != null && server.id == state.areaId ? server.name : '')
        : _listedName ?? state.areaName ?? '';
    final text = !on
        ? context.tr('shop.why.nearOff')
        : area.isEmpty
        ? context.tr('shop.why.nearNoArea')
        : context.tr('shop.why.nearOn').replaceAll('{area}', area);
    return Column(
      key: const Key('shop-near-you-line'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.place_outlined,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: Text(
                text,
                key: const Key('shop-near-you-status'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: FFTokens.spacingSm,
          children: [
            if (on) ...[
              FFButton(
                key: const Key('shop-near-you-change'),
                label: context.tr('shop.near.changeArea'),
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: _busy
                    ? null
                    : () => _run(() => ShopNearYouFlow.changeArea(context)),
              ),
              FFButton(
                key: const Key('shop-near-you-turn-off'),
                label: context.tr('shop.why.turnOff'),
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: _busy
                    ? null
                    : () => _run(() => ShopNearYouFlow.turnOff(context)),
              ),
            ] else
              FFButton(
                key: const Key('shop-near-you-turn-on'),
                label: context.tr('shop.why.turnOn'),
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await ShopNearYouFlow.turnOn(context);
                      }),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Delivers to your area" (neutral badge; the icon is not read out).
class ShopDeliversBadge extends StatelessWidget {
  const ShopDeliversBadge({super.key});

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('shop-delivers-badge'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const ExcludeSemantics(
        child: Icon(Icons.local_shipping_outlined, size: 16),
      ),
      const SizedBox(width: FFTokens.spacingXs),
      Flexible(
        child: FFBadge(
          label: context.tr('shop.near.badge'),
          tone: FFBadgeTone.gray,
          wrap: true,
        ),
      ),
    ],
  );
}

/// The near-you slot while the area is being worked out: a heading line and
/// three card shapes, announced once.
class ShopNearYouSkeleton extends StatelessWidget {
  const ShopNearYouSkeleton({super.key, required this.cardWidth});
  final double cardWidth;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('shop-near-you-finding'),
    container: true,
    liveRegion: true,
    label: context.tr('shop.near.finding'),
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: FFTokens.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FFSkeleton(width: 160, height: 18),
            const SizedBox(height: FFTokens.spacingMd),
            ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      FFSkeleton(
                        width: cardWidth,
                        height: cardWidth,
                        radius: FFTokens.radiusMd,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
