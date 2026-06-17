import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import 'widgets/gym_card.dart';
import 'widgets/trainer_card.dart';
import 'widgets/pass_summary_card.dart';
import 'widgets/checkin_list.dart';

class MemberHomeTab extends StatefulWidget {
  const MemberHomeTab({super.key});

  @override
  State<MemberHomeTab> createState() => _MemberHomeTabState();
}

class _MemberHomeTabState extends State<MemberHomeTab> {
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    // Refresh QR and user data when home tab becomes visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
      _fetchLocation();
    });
  }

  Future<void> _refreshData() async {
    final shellState = context.findAncestorStateOfType<MemberShellState>();
    await shellState?.refreshQr();
    await shellState?.refreshMe();
  }

  Future<void> _fetchLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
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
      });
    } catch (_) {
      // Location is optional on home. Keep showing the backend gym list.
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final me = data.me;
    final displayName = me?.user.resolvedName ?? context.tr('home.welcome');
    final gyms = memberHomeNearGyms(
      data.gyms,
      userLat: _userLat,
      userLng: _userLng,
    );
    final trainers = data.trainers.take(2).toList();

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(
          context.tr('member.goodMorning'),
          style: const TextStyle(color: FFTokens.fgQuaternary, fontSize: 14),
        ),
        FFPageHeader(title: displayName),

        // Pass summary
        PassSummaryCard(data: data),

        // Near gyms
        _SectionRow(
          title: context.tr('member.nearGyms'),
          onSeeAll: () => context.go(AppRoutes.memberGyms),
        ),
        ...gyms.map(
          (g) => GymCard(
            gym: g,
            distanceKm: gymDisplayDistanceKm(
              g,
              userLat: _userLat,
              userLng: _userLng,
              activeFilter: 'home',
            ),
          ),
        ),

        // Featured trainers
        _SectionRow(
          title: context.tr('member.featuredTrainers'),
          onSeeAll: () => context.go(AppRoutes.memberTrainers),
        ),
        ...trainers.map((t) => TrainerCard(trainer: t)),

        // Activity
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 10),
          child: Text(
            context.tr('member.activity'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
            ),
          ),
        ),
        CheckinList(checkins: data.checkins, limit: 3),
      ],
    );
  }
}

List<Gym> memberHomeNearGyms(
  List<Gym> gyms, {
  double? userLat,
  double? userLng,
}) {
  if (userLat == null || userLng == null) return gyms.take(2).toList();
  final sorted = List<Gym>.from(gyms);
  sorted.sort(
    (a, b) => gymDistanceKm(
      a,
      userLat,
      userLng,
    ).compareTo(gymDistanceKm(b, userLat, userLng)),
  );
  return sorted.take(2).toList();
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.title, required this.onSeeAll});

  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: FFTokens.fgPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: onSeeAll,
            child: Text(context.tr('home.seeAll')),
          ),
        ],
      ),
    );
  }
}
