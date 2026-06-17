import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import 'widgets/gym_card.dart';

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
  bool _showFilters = false;
  double? _userLat;
  double? _userLng;
  bool _locationLoading = false;

  static const _filters = ['all', 'nearest', 'standard', 'midtier', 'premium'];
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLocation());
  }

  @override
  void dispose() {
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
        setState(() => _locationLoading = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
        _locationLoading = false;
      });
    } catch (_) {
      setState(() => _locationLoading = false);
    }
  }

  String _norm(Object? v) => v?.toString().trim().toLowerCase() ?? '';

  String _gymTierKey(Gym gym) {
    final t = _norm(gym.tier).replaceAll('-', '_').replaceAll(' ', '_');
    if (t == 'mid_tier' || t == 'midrange' || t == 'mid_range') {
      return 'midtier';
    }
    if (t == 'luxury' || t == 'executive') {
      return 'luxury_executive';
    }
    return t;
  }

  List<Gym> _filtered(List<Gym> gyms) {
    var result = gyms;
    final q = _norm(_search);
    if (q.isNotEmpty) {
      result = result
          .where(
            (g) =>
                _norm(g.name).contains(q) ||
                _norm(g.location).contains(q) ||
                _norm(g.tier).contains(q) ||
                g.amenities.any((a) => _norm(a).contains(q)) ||
                g.equipment.any((e) => _norm(e).contains(q)),
          )
          .toList();
    }
    if (_filter == 'standard') {
      result = result.where((g) => _gymTierKey(g) == 'standard').toList();
    } else if (_filter == 'midtier') {
      result = result.where((g) => _gymTierKey(g) == 'midtier').toList();
    } else if (_filter == 'premium') {
      result = result.where((g) {
        final t = _gymTierKey(g);
        return t == 'premium' || t == 'luxury_executive';
      }).toList();
    } else if (_filter == 'nearest') {
      if (_userLat != null && _userLng != null) {
        result = List.from(result);
        result.sort(
          (a, b) => gymDistanceKm(
            a,
            _userLat!,
            _userLng!,
          ).compareTo(gymDistanceKm(b, _userLat!, _userLng!)),
        );
      }
    }

    // Price filter
    if (_priceFilter != 'any') {
      result = result.where((g) {
        final rate = g.ratePerMonth ?? g.perVisitRate;
        switch (_priceFilter) {
          case '<60k':
            return rate < 60000;
          case '<150k':
            return rate < 150000;
          case '<200k':
            return rate < 200000;
          case '<350k':
            return rate < 350000;
          case '350k+':
            return rate >= 350000;
          default:
            return true;
        }
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final gyms = _filtered(data.gyms);

    final filterLabels = [
      context.tr('member.all'),
      context.tr('member.nearest'),
      'Standard',
      'Mid-Range',
      'Premium',
    ];

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFPageHeader(title: context.tr('member.discoverGyms')),
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: context.tr('member.searchGyms'),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(FFTokens.radiusLg),
            ),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length + 1,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              // Last item is the "Other Filters" button
              if (i == _filters.length) {
                return GestureDetector(
                  onTap: () => setState(() => _showFilters = !_showFilters),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _showFilters
                          ? FFTokens.brand700
                          : FFTokens.bgSecondary,
                      border: Border.all(
                        color: _showFilters
                            ? FFTokens.brand700
                            : FFTokens.borderSecondary,
                      ),
                      borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune,
                          size: 14,
                          color: _showFilters
                              ? Colors.white
                              : FFTokens.fgSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.tr('member.otherFilters'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _showFilters
                                ? Colors.white
                                : FFTokens.fgSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final selected = _filter == _filters[i];
              return GestureDetector(
                onTap: () {
                  setState(() => _filter = _filters[i]);
                  if (_filters[i] == 'nearest') _fetchLocation();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? FFTokens.brand700 : FFTokens.bgSecondary,
                    border: Border.all(
                      color: selected
                          ? FFTokens.brand700
                          : FFTokens.borderSecondary,
                    ),
                    borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                  ),
                  child: Text(
                    filterLabels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: selected ? Colors.white : FFTokens.fgSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Price filter panel
        if (_showFilters) ...[
          const SizedBox(height: 12),
          FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('member.priceRange'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FFTokens.fgPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _priceFilters.map((p) {
                    final selected = _priceFilter == p;
                    return GestureDetector(
                      onTap: () => setState(() => _priceFilter = p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? FFTokens.brand100
                              : FFTokens.bgSecondary,
                          border: Border.all(
                            color: selected
                                ? FFTokens.brand500
                                : FFTokens.borderSecondary,
                          ),
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusMd,
                          ),
                        ),
                        child: Text(
                          p == 'any' ? context.tr('member.anyPrice') : p,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? FFTokens.brand700
                                : FFTokens.fgSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
        if (_locationLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        const SizedBox(height: 16),
        if (gyms.isEmpty)
          FFEmptyState(title: context.tr('member.noData'))
        else
          ...gyms.map(
            (g) => GymCard(
              gym: g,
              distanceKm: gymDisplayDistanceKm(
                g,
                userLat: _userLat,
                userLng: _userLng,
                activeFilter: _filter,
              ),
            ),
          ),
      ],
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
