import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import 'home_feed.dart';
import 'widgets/phone_steps_card.dart';
import 'widgets/challenge_widgets.dart';
import 'widgets/goal_widgets.dart';
import 'widgets/home_cards.dart';
import 'widgets/pass_summary_card.dart';
import 'widgets/today_activity_card.dart';
import 'widgets/workout_widgets.dart';

class MemberHomeTab extends StatefulWidget {
  const MemberHomeTab({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

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
    final now = widget.now ?? DateTime.now();
    final picks = pickHomeCards(data, now, lat: _userLat, lng: _userLng);
    bool has(HomeCardKind k) => picks.any((p) => p.kind == k);

    return ListView(
      key: const Key('member-home'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(
          context.tr(
            now.hour < 12
                ? 'member.goodMorning'
                : now.hour < 17
                ? 'member.goodAfternoon'
                : 'member.goodEvening',
          ),
          style: TextStyle(
            color: Theme.of(context).textTheme.bodySmall?.color,
            fontSize: 14,
          ),
        ),
        FFPageHeader(title: displayName),
        for (final p in picks)
          KeyedSubtree(
            key: Key('home-card-${p.kind.name}'),
            child: _card(context, data, p, now, has),
          ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    MemberData data,
    HomeCardPick p,
    DateTime now,
    bool Function(HomeCardKind) has,
  ) {
    const gap = SizedBox(height: FFTokens.spacingSm);
    switch (p.kind) {
      case HomeCardKind.passport:
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: PassSummaryCard(data: data),
        );
      case HomeCardKind.todayActivity:
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TodayActivityCard(
                data: data,
                now: now,
                showWorkout: !has(HomeCardKind.todayWorkout),
                showStreak: !has(HomeCardKind.streak),
              ),
              const PhoneStepsCard(dismissible: true),
            ],
          ),
        );
      case HomeCardKind.todayWorkout:
        return Column(
          children: [
            gap,
            TodayWorkoutCard(data: data, now: now),
          ],
        );
      case HomeCardKind.streak:
        return Column(
          children: [
            gap,
            HomeStreakCard(pick: p),
          ],
        );
      case HomeCardKind.goal:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FFSectionTitle(context.tr('home.currentGoal')),
            if (p.goal case final g?)
              GoalCard(progress: g)
            else
              FFActionTile(
                key: const Key('home-set-goal'),
                icon: Icons.flag_outlined,
                title: context.tr('home.setGoal'),
                subtitle: context.tr('home.setGoalBody'),
                onTap: () => showAddGoalSheet(context),
              ),
          ],
        );
      case HomeCardKind.challenge:
        final s = p.standing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FFSectionTitle(
              context.tr(
                s != null ? 'home.activeChallenge' : 'home.tryChallenge',
              ),
            ),
            ChallengeCard(
              challenge: s?.challenge ?? p.invite!,
              progress: s?.progress,
              now: now,
            ),
          ],
        );
      case HomeCardKind.recommendation:
        final g = p.gym;
        return HomeRecommendation(
          pick: p,
          distanceKm: g == null
              ? null
              : gymDisplayDistanceKm(
                  g,
                  userLat: _userLat,
                  userLng: _userLng,
                  activeFilter: 'home',
                ),
        );
    }
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
