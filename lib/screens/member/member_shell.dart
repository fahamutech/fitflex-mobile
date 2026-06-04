import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';

export 'member_home_tab.dart';
export 'member_gyms_tab.dart';
export 'member_gym_detail_page.dart';
export 'member_trainers_tab.dart';
export 'member_trainer_detail_page.dart';
export 'member_qr_tab.dart';
export 'member_profile_tab.dart';
export 'member_passes_page.dart';
export 'member_payment_page.dart';

/// Shared member data that all member tabs can access.
class MemberData extends ChangeNotifier {
  MemberMeResponse? me;
  List<Gym> gyms = [];
  List<TrainerProfile> trainers = [];
  List<CheckIn> checkins = [];
  List<PassTier> passes = [];
  bool passesLoaded = false;
  String? qrToken;
  String selectedTier = 'pro';
  bool loading = false;

  bool get hasActivePass => me?.hasActivePass == true;
  bool get needsOnboarding => me?.needsOnboarding == true;
  Subscription? get subscription => me?.subscription;
  PaymentRequest? get pendingPayment => me?.pendingPayment;

  void update(void Function(MemberData d) fn) {
    fn(this);
    notifyListeners();
  }
}

/// InheritedWidget exposing shared member data to subtree.
class MemberDataScope extends InheritedNotifier<MemberData> {
  const MemberDataScope({
    super.key,
    required MemberData data,
    required super.child,
  }) : super(notifier: data);

  static MemberData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MemberDataScope>();
    assert(scope != null, 'MemberDataScope missing');
    return scope!.notifier!;
  }
}

/// Bottom navigation shell for member screens.
class MemberShell extends StatefulWidget {
  const MemberShell({super.key, required this.state, required this.child});

  final GoRouterState state;
  final Widget child;

  @override
  MemberShellState createState() => MemberShellState();
}

class MemberShellState extends State<MemberShell> {
  final MemberData _data = MemberData();
  Timer? _qrTimer;
  bool _started = false;

  int get _tabIndex {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/member/gyms')) return 1;
    if (loc.startsWith('/member/trainers')) return 2;
    if (loc.startsWith('/member/qr')) return 3;
    if (loc.startsWith('/member/profile')) return 4;
    return 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _refreshAll();
    _qrTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshQr());
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    _data.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    _data.update((d) => d.loading = true);
    try {
      await Future.wait([
        _refreshMe(),
        _refreshGyms(),
        _refreshTrainers(),
        _refreshCheckins(),
        _refreshPasses(),
        _refreshQr(),
      ]);
    } finally {
      _data.update((d) => d.loading = false);
    }
  }

  Future<void> _refreshMe() async {
    try {
      final res = await AppScope.of(context).api.me();
      _data.update(
        (d) => d.me = MemberMeResponse.fromJson(
          Map<String, dynamic>.from(res as Map),
        ),
      );
    } catch (_) {
      // ignore
    }
  }

  Future<void> _refreshGyms() async {
    try {
      final res = await AppScope.of(context).api.listGyms();
      _data.update(
        (d) => d.gyms = res
            .whereType<Map<String, dynamic>>()
            .map(Gym.fromJson)
            .toList(),
      );
    } catch (_) {
      // ignore
    }
  }

  Future<void> _refreshTrainers() async {
    try {
      final res = await AppScope.of(context).api.listTrainers();
      _data.update(
        (d) => d.trainers = res
            .whereType<Map<String, dynamic>>()
            .map(TrainerProfile.fromJson)
            .toList(),
      );
    } catch (_) {
      // ignore
    }
  }

  Future<void> _refreshCheckins() async {
    try {
      final res = await AppScope.of(context).api.myCheckins();
      _data.update(
        (d) => d.checkins = res
            .whereType<Map<String, dynamic>>()
            .map(CheckIn.fromJson)
            .toList(),
      );
    } catch (_) {
      // ignore
    }
  }

  Future<void> _refreshPasses() async {
    final api = AppScope.of(context).api;
    try {
      // Prefer new subscription-tiers endpoint (includes gymAccess per plan)
      final res = await api.listSubscriptionTiers();
      final tiers = res
          .whereType<Map<String, dynamic>>()
          .map(PassTier.fromJson)
          .toList();
      if (tiers.isEmpty) throw Exception('empty_tiers');
      _data.update((d) {
        d.passes = tiers;
        d.passesLoaded = true;
      });
    } catch (_) {
      // Fallback to legacy /passes endpoint
      try {
        final res = await api.listPasses();
        _data.update((d) {
          d.passes = res
              .whereType<Map<String, dynamic>>()
              .map(PassTier.fromJson)
              .toList();
          d.passesLoaded = true;
        });
      } catch (_) {
        _data.update((d) => d.passesLoaded = true);
      }
    }
  }

  Future<void> _refreshQr() async {
    try {
      final res = await AppScope.of(context).api.myQr();
      _data.update((d) => d.qrToken = res['token'] as String?);
    } catch (_) {
      _data.update((d) => d.qrToken = null);
    }
  }

  Future<void> refreshPasses() async {
    await _refreshPasses();
  }

  Future<void> refreshQr() async {
    await _refreshQr();
  }

  Future<void> refreshMe() async {
    await _refreshMe();
  }

  void _onTab(int index) {
    final routes = [
      AppRoutes.memberHome,
      AppRoutes.memberGyms,
      AppRoutes.memberTrainers,
      AppRoutes.memberQr,
      AppRoutes.memberProfile,
    ];
    // Refresh QR when navigating to QR tab
    if (index == 3) {
      refreshQr();
      refreshMe();
    }
    context.go(routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    return MemberDataScope(
      data: _data,
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('app.title'))),
        body: RefreshIndicator(onRefresh: _refreshAll, child: widget.child),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: _onTab,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: context.tr('member.home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.fitness_center_outlined),
              selectedIcon: const Icon(Icons.fitness_center),
              label: context.tr('member.gyms'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.sports_gymnastics_outlined),
              selectedIcon: const Icon(Icons.sports_gymnastics),
              label: context.tr('member.trainers'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.qr_code_2_outlined),
              selectedIcon: const Icon(Icons.qr_code_2),
              label: context.tr('member.qr'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: context.tr('member.profile'),
            ),
          ],
        ),
      ),
    );
  }
}
