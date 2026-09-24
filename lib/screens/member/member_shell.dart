import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/activity.dart';
import '../../shared/activity/activity_config.dart';
import '../../shared/activity/activity_provider.dart';
import '../../shared/activity/challenge.dart';
import '../../shared/activity/goal.dart';
import '../../shared/activity/gym_sharing.dart';
import '../../shared/activity/trainer_connection.dart';
import '../../shared/activity/workout.dart';
import '../../shared/api_error_message.dart';
import '../../shared/auth_state.dart';
import '../../shared/components/theme_toggle_button.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/root_back_navigation.dart';

export 'member_home_tab.dart';
export 'member_activity_tab.dart';
export 'member_workout_page.dart';
export 'member_challenge_page.dart';
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
  Set<String> favoriteGymIds = {};
  // Fitness activity — separate from gym [checkins]; a visit is not a workout.
  List<Activity> activities = [];
  bool activityLoaded = false;
  bool activityIsSample = false;
  List<Goal> goals = [];
  bool goalsLoaded = false;
  List<Workout> workouts = [];
  bool workoutsLoaded = false;
  List<TrainerConnection> trainerConnections = [];
  List<GymSharing> gymSharing = [];
  List<Challenge> challenges = [];
  bool challengesLoaded = false;

  /// Gym check-ins as the challenge engine needs them.
  List<({DateTime at, String? gymId})> get checkInMoments => [
    for (final c in checkins)
      if (DateTime.tryParse(c.timestamp) case final at?)
        (at: at, gymId: c.gymId),
  ];

  /// The open (pending or active) connection with [trainerId], if any.
  TrainerConnection? connectionWith(String trainerId) => trainerConnections
      .where((c) => c.trainerId == trainerId && c.status.isOpen)
      .firstOrNull;

  /// Display name for a trainer, from the directory or a connection.
  String? trainerName(String? trainerId) {
    if (trainerId == null) return null;
    final t = trainers.where((t) => t.id == trainerId).firstOrNull;
    if (t != null) return t.displayName;
    return trainerConnections
        .where((c) => c.trainerId == trainerId)
        .firstOrNull
        ?.trainer
        ?.displayName;
  }

  bool passesLoaded = false;
  String? qrToken;
  String selectedTier = 'pro';
  bool loading = false;

  /// The last refresh couldn't reach FitFlex. Screens keep showing what was
  /// loaded before; the shell says so.
  bool offline = false;

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
  AuthState? _auth;
  String? _lastToken;

  int get _tabIndex {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/member/activity')) return 1;
    // Trainer discovery lives under Gyms now that Activity has the tab.
    if (loc.startsWith('/member/gyms')) return 2;
    if (loc.startsWith('/member/trainers')) return 2;
    if (loc.startsWith('/member/shop')) return 3;
    if (loc.startsWith('/member/profile')) return 4;
    if (loc.startsWith('/member/privacy')) return 4;
    return 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A10: track auth-session changes so a fresh sign-up/sign-in reloads
    // gyms/trainers without requiring an app restart.
    final auth = AppScope.of(context).auth;
    if (!identical(_auth, auth)) {
      _auth?.removeListener(_onAuthChanged);
      _auth = auth;
      _lastToken = auth.token;
      auth.addListener(_onAuthChanged);
    }
    if (_started) return;
    _started = true;
    _refreshAll();
    _qrTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_data.hasActivePass) _refreshQr();
    });
  }

  void _onAuthChanged() {
    final token = _auth?.token;
    if (token != null && token != _lastToken) {
      _lastToken = token;
      _refreshAll();
    } else {
      _lastToken = token;
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
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
        _refreshFavorites(),
        _refreshActivity(),
        _refreshGoals(),
        _refreshWorkouts(),
        _refreshConnections(),
        _refreshGymSharing(),
        _refreshChallenges(),
      ]);
      if (_data.hasActivePass) await _refreshQr();
    } finally {
      _data.update((d) => d.loading = false);
    }
  }

  Future<void> _refreshMe() async {
    try {
      final res = await AppScope.of(context).api.me();
      _data.update(
        (d) => d
          ..me = MemberMeResponse.fromJson(
            Map<String, dynamic>.from(res as Map),
          )
          ..offline = false,
      );
    } catch (error) {
      // The profile call is the connectivity check for the whole shell.
      if (isNetworkError(error)) _data.update((d) => d.offline = true);
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
      final trainers = <TrainerProfile>[];
      for (final item in res.whereType<Map>()) {
        try {
          trainers.add(
            TrainerProfile.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (error) {
          // A single malformed public profile must not hide the rest of the
          // trainer directory from members.
          debugPrint('[MemberShell] Skipping malformed trainer: $error');
        }
      }
      _data.update((d) => d.trainers = trainers);
    } catch (error) {
      debugPrint('[MemberShell] Could not refresh trainers: $error');
    }
  }

  Future<void> _refreshFavorites() async {
    try {
      final ids = await AppScope.of(context).api.favoriteGymIds();
      _data.update((d) => d.favoriteGymIds = ids.toSet());
    } catch (_) {
      // Saved gyms are a convenience; the rest of the tab still works.
    }
  }

  Future<void> _refreshActivity() async {
    final provider = AppScope.of(context).activity;
    final userId = _auth?.user?['id']?.toString() ?? '';
    try {
      final now = DateTime.now();
      final activities = await provider.getActivities(
        userId: userId,
        from: DateTime(now.year, now.month, now.day - activityHistoryDays + 1),
        to: now.add(const Duration(days: 1)),
      );
      _data.update((d) {
        d.activities = activities;
        d.activityIsSample = provider.kind == ActivityProviderKind.sample;
        d.activityLoaded = true;
      });
    } catch (error) {
      debugPrint('[MemberShell] Could not load activity: $error');
      _data.update((d) => d.activityLoaded = true);
    }
  }

  Future<void> _refreshGoals() async {
    try {
      final goals = await AppScope.of(context).goals.list();
      _data.update((d) {
        d.goals = goals;
        d.goalsLoaded = true;
      });
    } catch (error) {
      debugPrint('[MemberShell] Could not load goals: $error');
      _data.update((d) => d.goalsLoaded = true);
    }
  }

  Future<void> refreshGoals() async {
    await _refreshGoals();
  }

  Future<void> _refreshWorkouts() async {
    try {
      final now = DateTime.now();
      final workouts = await AppScope.of(context).workouts.list(
        from: DateTime(now.year, now.month, now.day - activityHistoryDays + 1),
        to: DateTime(now.year, now.month, now.day + 14),
      );
      _data.update((d) {
        d.workouts = workouts;
        d.workoutsLoaded = true;
      });
    } catch (error) {
      debugPrint('[MemberShell] Could not load workouts: $error');
      _data.update((d) => d.workoutsLoaded = true);
    }
  }

  Future<void> _refreshConnections() async {
    try {
      final rows = await AppScope.of(context).api.myTrainerConnections();
      _data.update(
        (d) => d.trainerConnections = [
          for (final r in rows.whereType<Map>())
            TrainerConnection.fromJson(Map<String, dynamic>.from(r)),
        ],
      );
    } catch (error) {
      debugPrint('[MemberShell] Could not load trainer connections: $error');
    }
  }

  Future<void> refreshConnections() async {
    await _refreshConnections();
  }

  Future<void> _refreshChallenges() async {
    try {
      final rows = await AppScope.of(context).api.myChallenges();
      _data.update((d) {
        d.challenges = [
          for (final r in rows.whereType<Map>())
            ?Challenge.tryParse(Map<String, dynamic>.from(r)),
        ];
        d.challengesLoaded = true;
      });
    } catch (error) {
      debugPrint('[MemberShell] Could not load challenges: $error');
      _data.update((d) => d.challengesLoaded = true);
    }
  }

  Future<void> refreshChallenges() async {
    await _refreshChallenges();
  }

  Future<void> _refreshGymSharing() async {
    try {
      final rows = await AppScope.of(context).api.myGymSharing();
      _data.update(
        (d) => d.gymSharing = [
          for (final r in rows.whereType<Map>())
            ?GymSharing.tryParse(Map<String, dynamic>.from(r)),
        ],
      );
    } catch (error) {
      debugPrint('[MemberShell] Could not load gym sharing: $error');
    }
  }

  /// After a workout changes: its list, and — once finished — the activity
  /// it was recorded as, which moves goals, progress and streaks.
  Future<void> refreshAfterWorkout() async {
    await Future.wait([_refreshWorkouts(), _refreshActivity()]);
  }

  Future<void> refreshTrainers() async {
    await _refreshTrainers();
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
      // A7: the "Online Free" option must not be offered to members.
      final tiers = res
          .whereType<Map<String, dynamic>>()
          .map(PassTier.fromJson)
          .where((t) => t.id != 'online_free')
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
              .where((t) => t.id != 'online_free')
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
    if (_data.hasActivePass) await _refreshQr();
  }

  Future<void> refreshMe() async {
    await _refreshMe();
  }

  void _onTab(int index) {
    final routes = [
      AppRoutes.memberHome,
      AppRoutes.memberActivity,
      AppRoutes.memberGyms,
      AppRoutes.memberShop,
      AppRoutes.memberProfile,
    ];
    context.go(routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isRootTab = <String>{
      AppRoutes.memberHome,
      AppRoutes.memberActivity,
      AppRoutes.memberGyms,
      AppRoutes.memberTrainers,
      AppRoutes.memberShop,
      AppRoutes.memberProfile,
    }.contains(location);
    return PopScope(
      canPop: !isRootTab,
      onPopInvokedWithResult: (didPop, _) {
        if (isRootTab) handleRootBack(didPop: didPop);
      },
      child: MemberDataScope(
        data: _data,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(context.tr('app.title')),
            actions: const [ThemeToggleButton()],
          ),
          body: Column(
            children: [
              ListenableBuilder(
                listenable: _data,
                builder: (context, _) => _data.offline
                    ? _OfflineBanner(onRetry: _refreshAll)
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: widget.child,
                ),
              ),
            ],
          ),
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
                key: const Key('member-nav-activity'),
                icon: const Icon(Icons.directions_run_outlined),
                selectedIcon: const Icon(Icons.directions_run),
                label: context.tr('activity.title'),
              ),
              NavigationDestination(
                key: const Key('member-nav-gyms'),
                icon: const Icon(Icons.fitness_center_outlined),
                selectedIcon: const Icon(Icons.fitness_center),
                label: context.tr('member.gyms'),
              ),
              NavigationDestination(
                key: const Key('member-nav-shop'),
                icon: const Icon(Icons.storefront_outlined),
                selectedIcon: const Icon(Icons.storefront),
                label: context.tr('member.shop'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: context.tr('member.profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim notice under the app bar while FitFlex can't be reached.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('member-offline-banner'),
      color: FFTokens.warning500.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FFTokens.spacingMd,
          FFTokens.spacingXs,
          FFTokens.spacingXs,
          FFTokens.spacingXs,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: FFTokens.iconSm,
              color: FFTokens.warning500,
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: Text(
                context.tr('offline.banner'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              key: const Key('member-offline-retry'),
              onPressed: onRetry,
              child: Text(context.tr('home.retry')),
            ),
          ],
        ),
      ),
    );
  }
}
