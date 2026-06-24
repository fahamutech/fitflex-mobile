import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/theme_toggle_button.dart';
import '../../shared/i18n.dart';

export 'owner_checkins_page.dart';
export 'owner_earnings_page.dart';
export 'owner_home_tab.dart';
export 'owner_manage_gyms_page.dart';
export 'owner_profile_page.dart';
export 'owner_trainers_page.dart';

/// Shared owner data that all owner tabs can access.
class OwnerData extends ChangeNotifier {
  Map<String, dynamic>? me;
  Map<String, dynamic>? dashboard;
  List<Map<String, dynamic>> ownerGyms = [];
  List<Map<String, dynamic>> ownerTrainers = [];
  bool loading = false;

  // Dashboard filters
  String? dashboardGymId;
  String dashboardMemberType = 'all';
  DateTime? statsFrom;
  DateTime? statsTo;

  String get displayName {
    final user = me?['user'] as Map?;
    return (user?['displayName'] ?? user?['email'] ?? user?['phone'] ?? 'Owner')
        .toString();
  }

  void update(void Function(OwnerData d) fn) {
    fn(this);
    notifyListeners();
  }
}

/// InheritedWidget exposing shared owner data to subtree.
class OwnerDataScope extends InheritedNotifier<OwnerData> {
  const OwnerDataScope({
    super.key,
    required OwnerData data,
    required super.child,
  }) : super(notifier: data);

  static OwnerData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<OwnerDataScope>();
    assert(scope != null, 'OwnerDataScope missing');
    return scope!.notifier!;
  }
}

/// Bottom navigation shell for owner screens.
class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key, required this.state, required this.child});

  final GoRouterState state;
  final Widget child;

  @override
  OwnerShellState createState() => OwnerShellState();
}

class OwnerShellState extends State<OwnerShell> {
  final OwnerData _data = OwnerData();
  bool _started = false;

  int get _tabIndex {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/owner/gyms')) return 1;
    if (loc.startsWith('/owner/trainers')) return 2;
    if (loc.startsWith('/owner/profile')) return 3;
    return 0;
  }

  String get _title {
    switch (_tabIndex) {
      case 1:
        return context.tr('owner.manageGyms');
      case 2:
        return context.tr('owner.trainers');
      case 3:
        return context.tr('owner.profile');
      default:
        return context.tr('owner.dashboard');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    refreshAll();
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> refreshAll() async {
    _data.update((d) => d.loading = true);
    try {
      await Future.wait([
        _refreshMe(),
        _refreshOwnerGyms(),
        refreshDashboard(),
        _refreshOwnerTrainers(),
      ]);
    } finally {
      _data.update((d) => d.loading = false);
    }
  }

  Future<void> _refreshMe() async {
    try {
      final res = await AppScope.of(context).api.me();
      _data.me = res;
    } on ApiException {
      // ignore
    }
  }

  Future<void> _refreshOwnerGyms() async {
    try {
      final res = await AppScope.of(context).api.ownerGyms();
      _data.ownerGyms = res.cast<Map<String, dynamic>>();
    } on ApiException {
      // ignore
    }
  }

  Future<void> refreshDashboard() async {
    try {
      String dateOnly(DateTime v) => v.toIso8601String().split('T').first;
      final res = await AppScope.of(context).api.operatorDashboard(
        gymId: _data.dashboardGymId,
        periodStart: _data.statsFrom == null
            ? null
            : dateOnly(_data.statsFrom!),
        periodEnd: _data.statsTo == null ? null : dateOnly(_data.statsTo!),
        memberType: _data.dashboardMemberType,
      );
      _data.dashboard = res;
    } on ApiException {
      // ignore
    }
  }

  Future<void> _refreshOwnerTrainers() async {
    try {
      final res = await AppScope.of(context).api.ownerTrainers();
      _data.ownerTrainers = res.cast<Map<String, dynamic>>();
    } on ApiException {
      // ignore
    }
  }

  void _onTab(int index) {
    const routes = [
      '/owner/home',
      '/owner/gyms',
      '/owner/trainers',
      '/owner/profile',
    ];
    context.go(routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    return OwnerDataScope(
      data: _data,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: const [ThemeToggleButton()],
        ),
        body: RefreshIndicator(onRefresh: refreshAll, child: widget.child),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: _onTab,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: context.tr('owner.home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.fitness_center_outlined),
              selectedIcon: const Icon(Icons.fitness_center),
              label: context.tr('owner.manageGyms'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.sports_gymnastics_outlined),
              selectedIcon: const Icon(Icons.sports_gymnastics),
              label: context.tr('owner.trainers'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: context.tr('owner.profile'),
            ),
          ],
        ),
      ),
    );
  }
}
