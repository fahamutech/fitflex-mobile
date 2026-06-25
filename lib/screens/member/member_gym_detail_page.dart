import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import 'widgets/gym_card.dart';
import 'widgets/trainer_card.dart';

class MemberGymDetailPage extends StatefulWidget {
  const MemberGymDetailPage({super.key, required this.gymId});

  final String gymId;

  @override
  State<MemberGymDetailPage> createState() => _MemberGymDetailPageState();
}

class _MemberGymDetailPageState extends State<MemberGymDetailPage> {
  bool _openingDirections = false;

  Future<void> _handleDirections(Gym gym) async {
    setState(() => _openingDirections = true);
    try {
      await openMapDirections(gym);
    } finally {
      if (mounted) setState(() => _openingDirections = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final gym = data.gyms.where((g) => g.id == widget.gymId).firstOrNull;

    if (gym == null) {
      return Center(child: FFEmptyState(title: context.tr('member.noData')));
    }

    final trainersAtGym = data.trainers
        .where((t) {
          return t.gymIds.contains(widget.gymId) ||
              t.gyms.any((g) => g.id == widget.gymId);
        })
        .take(2)
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.memberGyms),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('member.gymDetail')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          // Hero image
          _GymHero(gym: gym),

          // Name + location
          Row(
            children: [
              Flexible(
                child: Text(
                  gym.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (gymIsVerified(gym)) ...[
                const SizedBox(width: 6),
                const GymVerifiedIcon(size: 20),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            gym.location,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FFBadge(
                label: gym.tier.replaceAll('_', ' '),
                tone: FFBadgeTone.brand,
              ),
              if (gym.isFreeOnline) ...[
                const SizedBox(width: 6),
                FFBadge(
                  label: context.tr('gym.free'),
                  tone: FFBadgeTone.success,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Map toggle for directions
          InkWell(
            onTap: _openingDirections ? null : () => _handleDirections(gym),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _openingDirections
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.map_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('gym.getDirections'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // About
          FFSectionTitle(context.tr('member.about')),
          FFCard(
            child: Text(
              gym.venueType == 'online'
                  ? context.tr('member.planBody')
                  : '${context.tr('member.openNow')} - QR Check-in - ${gym.perVisitRate} TZS',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                height: 1.4,
              ),
            ),
          ),

          // Amenities & Equipment
          if (gym.amenities.isNotEmpty || gym.equipment.isNotEmpty) ...[
            FFSectionTitle(context.tr('gym.amenities')),
            if (gym.amenities.isNotEmpty)
              _CategorizedItems(
                items: gym.amenities,
                categories: _amenityCategories,
                tone: FFBadgeTone.brand,
              ),
            if (gym.equipment.isNotEmpty) ...[
              FFSectionTitle(context.tr('gym.equipment')),
              _CategorizedItems(
                items: gym.equipment,
                categories: _equipmentCategories,
                tone: FFBadgeTone.gray,
              ),
            ],
          ],

          // Trainers
          FFSectionTitle(context.tr('member.trainersAtGym')),
          if (trainersAtGym.isEmpty)
            FFEmptyState(title: context.tr('member.noData'))
          else
            ...trainersAtGym.map((t) => TrainerCard(trainer: t)),

          const SizedBox(height: 16),
          if (data.pendingPayment != null) ...[
            FFAlert(
              message: context.tr('home.qr.pendingBody'),
              tone: FFAlertTone.warning,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: data.pendingPayment != null
                      ? null
                      : () => context.go(AppRoutes.memberPasses),
                  child: Text(context.tr('member.subscribe')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.go(AppRoutes.memberQr),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.tr('member.visitWithPass')),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> openMapDirections(Gym gym) async {
  final origin = await _currentLocation();
  final uri = gymDirectionsUri(
    gym,
    originLat: origin?.latitude,
    originLng: origin?.longitude,
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<Position?> _currentLocation() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }

  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
  } catch (_) {
    return null;
  }
}

Uri gymDirectionsUri(Gym gym, {double? originLat, double? originLng}) {
  final query = <String, String>{
    'api': '1',
    'destination': gym.hasCoordinates
        ? '${gym.latitude},${gym.longitude}'
        : gym.location,
    'travelmode': 'driving',
  };
  if (originLat != null && originLng != null) {
    query['origin'] = '$originLat,$originLng';
  }

  return Uri.https('www.google.com', '/maps/dir/', query);
}

class _GymHero extends StatelessWidget {
  const _GymHero({required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) {
    final images = gym.images;
    return Container(
      height: 180,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      child: images.isNotEmpty
          ? PageView.builder(
              itemCount: images.length,
              itemBuilder: (context, index) => Stack(
                fit: StackFit.expand,
                children: [
                  FFRemoteImage(
                    src: images[index],
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    fallback: Center(
                      child: Icon(
                        Icons.fitness_center,
                        color: Theme.of(context).colorScheme.primary,
                        size: 48,
                      ),
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: FFBadge(
                        label: '${index + 1}/${images.length}',
                        tone: FFBadgeTone.gray,
                      ),
                    ),
                ],
              ),
            )
          : Center(
              child: Icon(
                Icons.fitness_center,
                color: Theme.of(context).colorScheme.primary,
                size: 48,
              ),
            ),
    );
  }
}

class _ItemCategory {
  const _ItemCategory(
    this.titleKey,
    this.icon,
    this.items, {
    this.asRatings = false,
  });

  final String titleKey;
  final IconData icon;
  final Set<String> items;
  final bool asRatings;
}

final _amenityCategories = [
  _ItemCategory('gym.category.wellness', Icons.spa_outlined, {
    'dry sauna',
    'infrared sauna',
    'steam room',
    'hot tub',
    'hot tub / jacuzzi',
    'jacuzzi',
    'cold plunge',
    'plunge pool',
    'indoor pool',
  }),
  _ItemCategory('gym.category.facilities', Icons.shower_outlined, {
    'lockers',
    'showers',
    'towel service',
    'wifi',
    'wi-fi',
    'reception',
  }),
  _ItemCategory('gym.category.environment', Icons.auto_awesome_outlined, {
    'cleanliness',
    'layout',
    'lighting',
    'size',
    'operating hours',
  }, asRatings: true),
];

final _equipmentCategories = [
  _ItemCategory('gym.category.strength', Icons.fitness_center, {
    'chest press',
    'smith machine',
    'leg press',
    'cable machines',
    'ez curl bars',
    'lat pulldown',
    'squat racks',
    'power racks',
    'benches',
    'dumbbell racks',
    'barbell + plate stations',
    'kettlebell sets',
  }),
  _ItemCategory('gym.category.functional', Icons.sports_gymnastics_outlined, {
    'battle ropes',
    'pull-up bars',
    'plyo boxes',
    'crossfit rig',
    'olympic platform',
    'trx',
    'suspension trainers',
    'multi-station',
    'jungle gym',
  }),
  _ItemCategory('gym.category.combat', Icons.sports_mma_outlined, {
    'heavy bags',
    'boxing',
  }),
  _ItemCategory('gym.category.mobility', Icons.self_improvement_outlined, {
    'yoga',
    'pilates',
    'stretching area',
  }),
  _ItemCategory('gym.category.cardio', Icons.directions_run, {
    'treadmills',
    'stationary bikes',
    'spin',
    'cycling bikes',
    'ellipticals',
    'rowing machines',
    'stair climbers',
  }),
];

class _CategorizedItems extends StatelessWidget {
  const _CategorizedItems({
    required this.items,
    required this.categories,
    required this.tone,
  });

  final List<String> items;
  final List<_ItemCategory> categories;
  final FFBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final remaining = [...items];
    final groups =
        <
          ({String titleKey, IconData icon, List<String> items, bool asRatings})
        >[];
    for (final category in categories) {
      final matched = remaining
          .where((item) => category.items.any((known) => _matches(item, known)))
          .toList();
      if (matched.isEmpty) continue;
      remaining.removeWhere(matched.contains);
      groups.add((
        titleKey: category.titleKey,
        icon: category.icon,
        items: matched,
        asRatings: category.asRatings,
      ));
    }
    if (remaining.isNotEmpty) {
      groups.add((
        titleKey: 'gym.category.other',
        icon: Icons.more_horiz,
        items: remaining,
        asRatings: false,
      ));
    }

    // Sort categories by item count descending (most items first)
    groups.sort((a, b) => b.items.length.compareTo(a.items.length));

    return Column(
      children: groups
          .map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ExpandableChipGroup(
                title: context.tr(group.titleKey),
                icon: group.icon,
                items: group.items,
                tone: tone,
                asRatings: group.asRatings,
                highlightAvailable: true,
              ),
            ),
          )
          .toList(),
    );
  }

  bool _matches(String value, String known) {
    final normalized = value.toLowerCase();
    return normalized == known || normalized.contains(known);
  }
}

class _ExpandableChipGroup extends StatefulWidget {
  const _ExpandableChipGroup({
    required this.title,
    required this.icon,
    required this.items,
    required this.tone,
    required this.asRatings,
    this.highlightAvailable = false,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final FFBadgeTone tone;
  final bool asRatings;
  final bool highlightAvailable;

  @override
  State<_ExpandableChipGroup> createState() => _ExpandableChipGroupState();
}

class _ExpandableChipGroupState extends State<_ExpandableChipGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visible = _expanded || widget.items.length <= 8
        ? widget.items
        : widget.items.take(8).toList();
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.icon,
                color: Theme.of(context).colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.asRatings)
            Column(
              children: visible
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _ratingLabel(item),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.star,
                            color: FFTokens.warning500,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _ratingValue(item).toStringAsFixed(1),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: visible
                  .map(
                    (item) => widget.highlightAvailable
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: FFTokens.success50,
                              border: Border.all(color: FFTokens.success200),
                              borderRadius: BorderRadius.circular(
                                FFTokens.radiusMd,
                              ),
                            ),
                            child: Text(
                              item,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: FFTokens.success700,
                              ),
                            ),
                          )
                        : FFBadge(label: item, tone: widget.tone),
                  )
                  .toList(),
            ),
          if (widget.items.length > 8) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded
                    ? context.tr('gym.showLess')
                    : context.tr('gym.viewAll'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _ratingLabel(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty && double.tryParse(part) == null)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  double _ratingValue(String value) {
    final match = RegExp(r'([0-5](?:\.\d)?)').firstMatch(value);
    final parsed = match == null ? null : double.tryParse(match.group(1)!);
    return parsed == null ? 4.0 : parsed.clamp(0, 5).toDouble();
  }
}
