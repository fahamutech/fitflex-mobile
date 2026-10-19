import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/discovery_loader.dart';
import '../../shared/promotion_events.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/photo_hero_flag.dart';
import '../../shared/promotion.dart';
import 'member_shell.dart';
import 'widgets/gym_card.dart';
import 'widgets/directory_states.dart';
import 'widgets/gym_filters.dart';

class MemberGymsTab extends StatefulWidget {
  const MemberGymsTab({super.key});

  @override
  State<MemberGymsTab> createState() => _MemberGymsTabState();
}

class _MemberGymsTabState extends State<MemberGymsTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _filter = 'all';
  String _priceFilter = 'any';
  final Set<String> _amenityFilter = {};
  bool _verifiedOnly = false;
  bool _showFilters = false;
  double? _userLat;
  double? _userLng;
  bool _locationLoading = false;

  /// The server's ranked answer for the current search and filters: a Featured
  /// section and the results below it. Null until it arrives, or if the server
  /// cannot be reached, in which case the plain list is filtered on the phone.
  DiscoverResult<Gym>? _discovery;
  bool _discoveryLoading = false;
  late final DiscoveryLoader<Gym> _loader = DiscoveryLoader<Gym>(
    fetch: (q) async => DiscoverResult.fromJson<Gym>(
      await AppScope.of(
        context,
      ).api.discover('gyms', q.withSession(discoverSessionId())),
      Gym.fromJson,
    ),
    onResult: (r) {
      if (mounted) setState(() => _discovery = r);
    },
    onLoading: (v) {
      if (mounted) setState(() => _discoveryLoading = v);
    },
  );

  static const _filters = [
    'all',
    'saved',
    'nearest',
    'standard',
    'midtier',
    'premium',
  ];
  static const _priceFilters = [
    'any',
    '<60k',
    '<150k',
    '<200k',
    '<350k',
    '350k+',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLocation();
      _requestDiscovery(immediate: true);
    });
  }

  @override
  void dispose() {
    _loader.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    if (_userLat != null) return;
    setState(() => _locationLoading = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _locationLoading = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
        _locationLoading = false;
      });
      _requestDiscovery(immediate: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationLoading = false);
    }
  }

  /// Ask the server to rank for what the customer has typed and chosen. The
  /// tier chip, the verified switch, 'nearest' and the search go to the server;
  /// price, amenities and 'saved' are applied on the phone to what comes back.
  void _requestDiscovery({bool immediate = false}) {
    const tiers = {'standard', 'midtier', 'premium'};
    final nearest =
        _filter == 'nearest' && _userLat != null && _userLng != null;
    _loader.request(
      DiscoverQuery(
        q: _search,
        lat: _userLat,
        lng: _userLng,
        sort: nearest ? 'distance' : null,
        filters: {
          if (tiers.contains(_filter)) 'tier': _filter,
          if (_verifiedOnly) 'verified': 'true',
        },
        limit: 50,
      ),
      immediate: immediate,
    );
  }

  /// What the customer sees: the server's ranked list when there is one (the
  /// search, tier and verified filters are already applied), otherwise the
  /// full list filtered here, exactly as before discovery existed.
  List<Gym> _filtered(List<Gym> gyms, Set<String> favoriteIds) {
    final ranked = _discovery;
    if (ranked != null) {
      // 'saved' needs the Featured gyms too, so they are not lost from the list.
      final pool = _filter == 'saved'
          ? [...ranked.featured, ...ranked.items]
          : ranked.items;
      return _clientFilters(pool, favoriteIds);
    }
    return _plainFiltered(gyms, favoriteIds);
  }

  /// The Featured section: only gyms the server featured for this search, and
  /// only those that also pass the filters applied here.
  List<Gym> _featured(Set<String> favoriteIds) {
    final ranked = _discovery;
    if (ranked == null || _filter == 'saved') return const [];
    return _clientFilters(ranked.featured, favoriteIds);
  }

  List<Gym> _clientFilters(List<Gym> gyms, Set<String> favoriteIds) {
    final pool = _filter == 'saved'
        ? gyms.where((g) => favoriteIds.contains(g.id)).toList()
        : gyms;
    return applyGymFilter(
      pool,
      GymFilter(price: _priceFilter, amenities: _amenityFilter),
    );
  }

  List<Gym> _plainFiltered(List<Gym> gyms, Set<String> favoriteIds) {
    var result = applyGymFilter(
      _filter == 'saved'
          ? gyms.where((g) => favoriteIds.contains(g.id)).toList()
          : gyms,
      GymFilter(
        search: _search,
        tier: _filter == 'saved' ? 'all' : _filter,
        price: _priceFilter,
        amenities: _amenityFilter,
        verifiedOnly: _verifiedOnly,
      ),
    );
    if (_filter == 'nearest' && _userLat != null && _userLng != null) {
      result = List.from(result);
      result.sort(
        (a, b) => gymDistanceKm(
          a,
          _userLat!,
          _userLng!,
        ).compareTo(gymDistanceKm(b, _userLat!, _userLng!)),
      );
    }
    return result;
  }

  /// Whether the search or any filter is narrowing the list.
  bool get _filtersActive =>
      _search.isNotEmpty ||
      _filter != 'all' ||
      _priceFilter != 'any' ||
      _amenityFilter.isNotEmpty ||
      _verifiedOnly;

  /// "Clear search and filters": back to the full list.
  void _clearSearchAndFilters() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _filter = 'all';
      _priceFilter = 'any';
      _amenityFilter.clear();
      _verifiedOnly = false;
    });
    _requestDiscovery(immediate: true);
  }

  /// Returns the responsive column count based on available width.
  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final gyms = _filtered(data.gyms, data.favoriteGymIds);
    final featured = _featured(data.favoriteGymIds);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final filterLabels = [
      context.tr('member.all'),
      context.tr('member.saved'),
      context.tr('member.nearest'),
      tierLabel(context, 'standard'),
      tierLabel(context, 'midtier'),
      tierLabel(context, 'premium'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = ffCardGridColumns(context, constraints.maxWidth);

        return CustomScrollView(
          key: const Key('gym-page-scroll'),
          slivers: [
            // ── Header + controls ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (photoHeroUi) ...[
                      // PHOTO_HERO_UI (increment plan, slice 1): a band
                      // replaces the page title and carries the Trainers
                      // button; search and filters stay right below it.
                      FFHeroBand(
                        key: const Key('gyms-hero'),
                        photo: FFHeroPhoto.gyms,
                        minHeight: 160,
                        wideHeight: 200,
                        // Not "Discover gyms": the section strip below
                        // already says it (spec §32.2).
                        eyebrow: context.tr('member.gyms'),
                        headlineLead: context.tr('hero.gyms.lead'),
                        headlineAccent: context.tr('hero.gyms.accent'),
                        actions: [
                          FFButton(
                            key: const Key('member-find-trainer'),
                            label: context.tr('member.trainers'),
                            onPressed: () =>
                                context.go(AppRoutes.memberTrainers),
                            variant: FFButtonVariant.onPhoto,
                            size: FFButtonSize.sm,
                            icon: Icons.sports_gymnastics_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: FFTokens.spacingMd),
                    ] else
                      FFPageHeader(
                        title: context.tr('member.discoverGyms'),
                        // Trainer discovery moved here from the bottom nav
                        // when Activity took that slot.
                        actions: FFButton(
                          key: const Key('member-find-trainer'),
                          label: context.tr('member.trainers'),
                          onPressed: () => context.go(AppRoutes.memberTrainers),
                          variant: FFButtonVariant.ghost,
                          size: FFButtonSize.sm,
                          icon: Icons.sports_gymnastics_outlined,
                        ),
                      ),
                    FFSearchFocusScroll(
                      enabled: photoHeroUi,
                      builder: (context, focusNode) => TextField(
                        key: const Key('gym-search'),
                        focusNode: focusNode,
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: context.tr('member.searchGyms'),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: context.tr('common.close'),
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _search = '');
                                    _requestDiscovery(immediate: true);
                                  },
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              FFTokens.radiusLg,
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          setState(() => _search = v);
                          _requestDiscovery();
                        },
                      ),
                    ),
                    if (_discoveryLoading)
                      const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 12),
                    // ── Tier filter chips ──────────────────────────────
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        key: const Key('gym-filter-scroll'),
                        scrollDirection: Axis.horizontal,
                        itemCount: _filters.length + 1,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          if (i == _filters.length) {
                            return GestureDetector(
                              key: const Key('gym-filter-more'),
                              onTap: () =>
                                  setState(() => _showFilters = !_showFilters),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _showFilters ? cs.primary : cs.surface,
                                  border: Border.all(
                                    color: _showFilters
                                        ? cs.primary
                                        : cs.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    FFTokens.radiusXl,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.tune,
                                      size: 14,
                                      color: _showFilters
                                          ? cs.onPrimary
                                          : cs.onSurface,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      context.tr('member.otherFilters'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: _showFilters
                                            ? cs.onPrimary
                                            : cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final selected = _filter == _filters[i];
                          return GestureDetector(
                            key: Key('gym-filter-${_filters[i]}'),
                            onTap: () {
                              setState(() => _filter = _filters[i]);
                              if (_filters[i] == 'nearest') {
                                _fetchLocation();
                              }
                              _requestDiscovery(immediate: true);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selected ? cs.primary : cs.surface,
                                border: Border.all(
                                  color: selected ? cs.primary : cs.outline,
                                ),
                                borderRadius: BorderRadius.circular(
                                  FFTokens.radiusXl,
                                ),
                              ),
                              child: Text(
                                filterLabels[i],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: selected ? cs.onPrimary : cs.onSurface,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // ── Filters panel (A9): price + amenities + verified ──
                    if (_showFilters) ...[
                      const SizedBox(height: 12),
                      FFCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('member.priceRange'),
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _priceFilters.map((p) {
                                final sel = _priceFilter == p;
                                return GestureDetector(
                                  onTap: () => setState(() => _priceFilter = p),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? cs.primary.withValues(alpha: 0.1)
                                          : cs.surface,
                                      border: Border.all(
                                        color: sel ? cs.primary : cs.outline,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        FFTokens.radiusMd,
                                      ),
                                    ),
                                    child: Text(
                                      p == 'any'
                                          ? context.tr('member.anyPrice')
                                          : p,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: sel
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: sel ? cs.primary : cs.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.tr('gym.amenities'),
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: availableAmenityOptions(data.gyms).map((
                                amenity,
                              ) {
                                final sel = _amenityFilter.contains(amenity);
                                return FilterChip(
                                  label: Text(
                                    amenity,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  selected: sel,
                                  onSelected: (value) => setState(() {
                                    if (value) {
                                      _amenityFilter.add(amenity);
                                    } else {
                                      _amenityFilter.remove(amenity);
                                    }
                                  }),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            Material(
                              color: Colors.transparent,
                              child: SwitchListTile(
                                key: const Key('gym-filter-verified'),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  context.tr('member.verifiedOnly'),
                                  style: tt.labelMedium,
                                ),
                                value: _verifiedOnly,
                                onChanged: (v) {
                                  setState(() => _verifiedOnly = v);
                                  _requestDiscovery(immediate: true);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_locationLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Featured (labelled; only gyms that match this search) ───────
            SliverToBoxAdapter(
              child: FFFeaturedStrip(
                title: context.tr('member.featuredGyms'),
                count: featured.length,
                // As tall as the tallest card: a two-line name or a
                // wrapped "Not verified" is never clipped (H3).
                fitContent: true,
                itemBuilder: (context, i) => GymGridCard(
                  key: Key('gym-featured-${featured[i].id}'),
                  gym: featured[i],
                  placement: _discovery?.placement,
                  distanceKm: gymDisplayDistanceKm(
                    featured[i],
                    userLat: _userLat,
                    userLng: _userLng,
                    activeFilter: _filter,
                  ),
                ),
              ),
            ),

            // ── Section header ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.symmetric(
                  horizontal: FFTokens.spacingLg,
                  vertical: 10,
                ),
                color: cs.surfaceContainerLow,
                child: Row(
                  children: [
                    Text(
                      context.tr('member.discoverGyms'),
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (gyms.isNotEmpty)
                      Text(
                        '${gyms.length}',
                        style: tt.bodySmall?.copyWith(color: cs.primary),
                      ),
                  ],
                ),
              ),
            ),

            // ── Grid ────────────────────────────────────────────────────
            // F-12: loading and failure have their own states (flag on and
            // off); "Nothing to show yet." only once loaded and empty.
            if (data.gyms.isEmpty && !data.gymsLoaded)
              DirectorySkeletonGrid(
                key: const Key('gym-grid-loading'),
                columns: cols,
                childAspectRatio: 0.72,
              )
            else if (data.gyms.isEmpty && data.gymsLoadFailed)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: FFErrorState(
                    key: const Key('gym-load-error'),
                    title: context.tr('member.gymsLoadError'),
                    retryLabel: context.tr('common.retry'),
                    onRetry: () => context
                        .findAncestorStateOfType<MemberShellState>()
                        ?.refreshGyms(),
                  ),
                ),
              )
            else if (gyms.isEmpty && featured.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: data.gyms.isNotEmpty && _filtersActive
                      ? FFEmptyState(
                          key: const Key('gym-no-match'),
                          title: context.tr('member.gymsNoMatch'),
                          action: FFButton(
                            key: const Key('gym-clear-search'),
                            label: context.tr('member.clearSearchFilters'),
                            variant: FFButtonVariant.ghost,
                            onPressed: _clearSearchAndFilters,
                          ),
                        )
                      : FFEmptyState(title: context.tr('member.noData')),
                ),
              )
            else if (gyms.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                // Rows as tall as their tallest card: a two-line name or
                // a wrapped "Not verified" is never clipped (H3).
                sliver: SliverFFRowGrid(
                  columns: cols,
                  itemCount: gyms.length,
                  itemBuilder: (context, i) => GymGridCard(
                    key: Key('gym-card-${gyms[i].id}'),
                    gym: gyms[i],
                    placement: _discovery?.placement,
                    imageAspectRatio: cols == 1 ? 16 / 9 : 4 / 3,
                    distanceKm: gymDisplayDistanceKm(
                      gyms[i],
                      userLat: _userLat,
                      userLng: _userLng,
                      activeFilter: _filter,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

double? gymDisplayDistanceKm(
  Gym gym, {
  required double? userLat,
  required double? userLng,
  required String activeFilter,
}) {
  if (userLat == null || userLng == null || !gym.hasCoordinates) return null;
  return gymDistanceKm(gym, userLat, userLng);
}

double gymDistanceKm(Gym gym, double userLat, double userLng) {
  final lat = gym.latitude;
  final lng = gym.longitude;
  if (lat == null || lng == null) return double.infinity;
  return haversineKm(userLat, userLng, lat, lng);
}

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const radiusKm = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return radiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _deg2rad(double deg) => deg * (math.pi / 180);
