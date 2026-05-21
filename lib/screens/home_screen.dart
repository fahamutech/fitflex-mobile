import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_scope.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/components/ff_remote_image.dart';
import '../shared/design_tokens.dart';
import '../shared/i18n.dart';
import '../shared/widgets/gym_form_page.dart';
import '../shared/widgets/profile_form_page.dart';
import '../shared/widgets/trainer_form_page.dart';
import 'language_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _me;
  String? _qrToken;
  List<dynamic> _passes = const [];
  bool _passesLoaded = false;
  List<dynamic> _gyms = const [];
  List<dynamic> _trainers = const [];
  List<dynamic> _checkins = const [];
  Timer? _qrTimer;
  bool _started = false;
  int _tab = 0;
  int _onboardingStep = 0;
  final List<String> _goals = [];
  String _level = 'beginner';
  String _selectedTier = '';
  Map<String, dynamic>? _selectedGym;
  Map<String, dynamic>? _selectedTrainer;
  String _gymFilter = 'all';
  String _trainerFilter = 'all';
  String _gymSearch = '';
  String _gymAmenityFilter = '';
  String _gymPriceFilter = 'any';
  String _trainerSearch = '';
  bool _showPassSelection = false;
  bool _showPayment = false;
  Position? _userPosition;
  final TextEditingController _gymSearchCtrl = TextEditingController();
  final TextEditingController _trainerSearchCtrl = TextEditingController();

  // Owner sub-views
  String? _ownerView; // null=dashboard, 'checkins', 'trainers', 'earnings'
  Map<String, dynamic>? _selectedOwnerGym;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _refreshAll();
    if (_userType == 'member') {
      _qrTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refreshQr(),
      );
    }
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    _gymSearchCtrl.dispose();
    _trainerSearchCtrl.dispose();
    super.dispose();
  }

  String get _userType =>
      AppScope.of(context).auth.user?['userType']?.toString() ??
      AppScope.of(context).auth.role;

  Future<void> _refreshAll() async {
    final isMember = _isMemberExperience;
    final isOwner = _userType == 'gym_operator';
    await Future.wait([
      _refreshMe(),
      _refreshGyms(),
      _refreshTrainers(),
      if (isMember) _refreshPasses(),
      if (isMember) _refreshCheckins(),
      if (isMember) _refreshQr(),
      if (isOwner) _refreshOwnerData(),
    ]);
  }

  Future<void> _refreshMe() async {
    try {
      final res = await AppScope.of(context).api.me();
      if (mounted) setState(() => _me = res);
    } on ApiException {
      /* ignore */
    }
  }

  Future<void> _refreshPasses() async {
    final api = AppScope.of(context).api;
    // Prefer admin-managed /subscription-tiers (reflects portal changes).
    // Fallback to legacy /passes if that endpoint fails.
    try {
      final res = await api.listSubscriptionTiers();
      final normalized = res.whereType<Map>().map<Map<String, dynamic>>((p) {
        final visits = (p['visits'] as num?)?.toInt();
        return {
          'id': p['id'] ?? p['key'],
          'price': p['price'] ?? p['monthlyPrice'] ?? 0,
          'visitCap':
              (p['visitCap'] as num?)?.toInt() ??
              (visits == -1 ? null : visits),
          'label': p['label'],
          'gymAccess': p['gymAccess'],
        };
      }).toList();
      if (normalized.isEmpty) throw Exception('empty_tiers');
      if (mounted) {
        setState(() {
          _passes = normalized;
          _passesLoaded = true;
        });
      }
    } catch (_) {
      try {
        final res = await api.listPasses();
        if (mounted) {
          setState(() {
            _passes = res;
            _passesLoaded = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _passesLoaded = true);
      }
    }
  }

  Future<void> _refreshGyms() async {
    try {
      final res = await AppScope.of(context).api.listGyms();
      if (mounted) setState(() => _gyms = res);
    } on ApiException {
      /* ignore */
    }
  }

  Future<void> _requestLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (mounted) setState(() => _userPosition = pos);
    } catch (_) {}
  }

  double _distanceToGym(Map<String, dynamic> gym) {
    if (_userPosition == null) return double.infinity;
    final coords = gym['coordinates'];
    if (coords == null) return double.infinity;
    double? lat, lng;
    if (coords is Map) {
      lat = (coords['lat'] as num?)?.toDouble();
      lng = (coords['lng'] as num?)?.toDouble();
    } else if (coords is List && coords.length >= 2) {
      lat = (coords[0] as num?)?.toDouble();
      lng = (coords[1] as num?)?.toDouble();
    }
    if (lat == null || lng == null) return double.infinity;
    return _haversineKm(
      _userPosition!.latitude,
      _userPosition!.longitude,
      lat,
      lng,
    );
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180);

  Future<void> _refreshTrainers() async {
    try {
      final res = await AppScope.of(context).api.listTrainers();
      if (mounted) setState(() => _trainers = res);
    } on ApiException {
      /* ignore */
    }
  }

  Future<void> _refreshCheckins() async {
    try {
      final res = await AppScope.of(context).api.myCheckins();
      if (mounted) setState(() => _checkins = res);
    } on ApiException {
      /* ignore */
    }
  }

  Future<void> _refreshQr() async {
    try {
      final res = await AppScope.of(context).api.myQr();
      if (mounted) setState(() => _qrToken = res['token'] as String?);
    } on ApiException {
      if (mounted) setState(() => _qrToken = null);
    }
  }

  // Owner-specific data
  List<dynamic> _ownerGyms = const [];
  Map<String, dynamic>? _dashboard;
  List<dynamic> _ownerTrainers = const [];

  Future<void> _refreshOwnerData() async {
    await Future.wait([
      _refreshOwnerGyms(),
      _refreshDashboard(),
      _refreshOwnerTrainers(),
    ]);
  }

  Future<void> _refreshOwnerGyms() async {
    try {
      final res = await AppScope.of(context).api.ownerGyms();
      if (mounted) setState(() => _ownerGyms = res);
    } on ApiException {
      /* ignore */
    }
  }

  Future<void> _refreshDashboard() async {
    try {
      final res = await AppScope.of(context).api.operatorDashboard();
      if (mounted) setState(() => _dashboard = res);
    } on ApiException {
      /* ignore */
    }
  }

  Future<void> _refreshOwnerTrainers() async {
    try {
      final res = await AppScope.of(context).api.ownerTrainers();
      if (mounted) setState(() => _ownerTrainers = res);
    } on ApiException {
      /* ignore */
    }
  }

  Future<void> _saveOnboarding() async {
    try {
      await AppScope.of(context).api.updateProfile({
        'displayName': _displayName,
        'fitnessGoals': _goals,
        'fitnessLevel': _level,
        'preferredWorkoutTimes': ['early_morning', 'evening'],
        'onboardingCompleted': true,
        'notificationPreferences': {
          'checkinReminders': true,
          'promotionAlerts': true,
          'trainerBookingUpdates': true,
        },
      });
      await _refreshMe();
      if (!mounted) return;
      // Re-hydrate auth user so router/widgets know onboarding is done
      if (_me != null && _me!['user'] != null) {
        final user = Map<String, dynamic>.from(_me!['user'] as Map);
        await AppScope.of(
          context,
        ).auth.signIn(AppScope.of(context).auth.token!, user);
      }
      if (mounted) setState(() => _onboardingStep = 0);
    } on ApiException catch (e) {
      _toast('Error ${e.status}');
    }
  }

  Future<void> _requestSelectedPass() async {
    try {
      await AppScope.of(context).api.requestPass(_selectedTier);
      await _refreshAll();
      if (!mounted) return;
      setState(() {
        _showPayment = false;
        _showPassSelection = false;
        _selectedGym = null;
        _tab = 0;
      });
      _toast(context.tr('member.paymentSubmitted'));
    } on ApiException catch (e) {
      _toast('Error ${e.status}');
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('home.signout')),
        content: Text(context.tr('confirm.signout')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FFTokens.error500),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('home.signout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppScope.of(context).auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LanguageScreen()),
      (_) => false,
    );
  }

  void _openWhatsAppSupport() {
    final uri = Uri.parse('https://wa.me/255786670499');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showEditProfileDialog() async {
    final user = Map<String, dynamic>.from(
      (_me?['user'] as Map?) ?? AppScope.of(context).auth.user ?? const {},
    );
    final saved = await openProfileForm(
      context,
      title: context.tr('member.editDetails'),
      initialUser: user,
      onSignOut: _signOut,
    );
    if (saved == true) {
      if (!mounted) return;
      final message = context.tr('member.profileUpdated');
      await _refreshMe();
      if (!mounted) return;
      if (_me != null && _me!['user'] != null) {
        final user = Map<String, dynamic>.from(_me!['user'] as Map);
        final token = AppScope.of(context).auth.token;
        if (token != null) {
          await AppScope.of(context).auth.signIn(token, user);
        }
      }
      setState(() {});
      _toast(message);
    }
  }

  // ── Owner Gym CRUD ──
  Future<void> _showAddGymDialog() async {
    final payload = await openGymForm(context);
    if (payload == null) return;
    if (!mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.gymAdded');
    try {
      await api.ownerCreateGym(payload);
      await _refreshOwnerData();
      if (!mounted) return;
      setState(() {});
      _toast(message);
    } on ApiException catch (e) {
      _toast('Error ${e.status}');
    }
  }

  Future<void> _showEditGymDialog(Map<String, dynamic> gym) async {
    final payload = await openGymForm(context, initial: gym);
    if (payload == null) return;
    if (!mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.gymUpdated');
    try {
      await api.ownerUpdateGym(gym['id'].toString(), payload);
      await _refreshOwnerData();
      if (!mounted) return;
      setState(() {});
      _toast(message);
    } on ApiException catch (e) {
      _toast('Error ${e.status}');
    }
  }

  void _confirmDeleteGym(Map<String, dynamic> gym) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('owner.deleteGym')),
        content: Text(context.tr('owner.confirmDelete')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final api = AppScope.of(context).api;
              final message = context.tr('owner.gymDeleted');
              try {
                await api.ownerDeleteGym(gym['id'].toString());
                await _refreshOwnerData();
                if (!mounted) return;
                setState(() {});
                _toast(message);
              } on ApiException catch (e) {
                _toast('Error ${e.status}');
              }
            },
            child: Text(context.tr('owner.deleteGym')),
          ),
        ],
      ),
    );
  }

  // ── Owner Trainer Management ──
  Future<void> _showAddTrainerDialog() async {
    final ownerGymIds = _ownerGyms
        .cast<Map<String, dynamic>>()
        .map((g) => g['id'].toString())
        .toList();
    final payload = await openTrainerForm(
      context,
      title: context.tr('owner.addTrainer'),
      defaultGymIds: ownerGymIds,
    );
    if (payload == null) return;
    if (!mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.trainerAdded');
    try {
      await api.ownerAddTrainer(payload);
      await _refreshOwnerData();
      if (!mounted) return;
      setState(() {});
      _toast(message);
    } on ApiException catch (e) {
      _toast('Error ${e.status}');
    }
  }

  Future<void> _showEditTrainerDialog(Map<String, dynamic> trainer) async {
    final payload = await openTrainerForm(
      context,
      title: context.tr('owner.editTrainer'),
      initial: trainer,
    );
    if (payload == null) return;
    // Email is immutable on edit; backend can ignore but strip locally too.
    payload.remove('email');
    if (!mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.trainerUpdated');
    try {
      await api.ownerUpdateTrainer(trainer['id'].toString(), payload);
      await _refreshOwnerData();
      if (!mounted) return;
      setState(() {});
      _toast(message);
    } on ApiException catch (e) {
      _toast('Error ${e.status}');
    }
  }

  void _confirmRemoveTrainer(Map<String, dynamic> trainer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('owner.removeTrainer')),
        content: Text(context.tr('owner.confirmRemoveTrainer')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final api = AppScope.of(context).api;
              final message = context.tr('owner.trainerRemoved');
              try {
                await api.ownerRemoveTrainer(trainer['id'].toString());
                await _refreshOwnerData();
                if (!mounted) return;
                setState(() {});
                _toast(message);
              } on ApiException catch (e) {
                _toast('Error ${e.status}');
              }
            },
            child: Text(context.tr('owner.removeTrainer')),
          ),
        ],
      ),
    );
  }

  // ── Owner Member Registration ──
  Future<void> _showAddMemberDialog() async {
    final ownerGymIds = _ownerGyms
        .cast<Map<String, dynamic>>()
        .map((g) => g['id'].toString())
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddMemberSheet(
        ownerGymIds: ownerGymIds,
        onSaved: (payload) async {
          if (!mounted) return;
          final api = AppScope.of(context).api;
          try {
            await api.ownerCreateMember(payload);
            if (!mounted) return;
            _toast(context.tr('owner.memberAdded'));
            await _refreshOwnerData();
            if (mounted) setState(() {});
          } on ApiException catch (e) {
            if (!mounted) return;
            _toast('Error ${e.status}');
          }
        },
      ),
    );
  }

  String get _displayName {
    final user = (_me?['user'] as Map?) ?? AppScope.of(context).auth.user;
    return (user?['displayName'] ??
            user?['email'] ??
            user?['phone'] ??
            'Member')
        .toString();
  }

  Map? get _subscription => _me?['subscription'] as Map?;
  Map? get _pendingPayment => _me?['pendingPayment'] as Map?;
  bool get _hasActivePass =>
      _subscription != null && _subscription?['status'] == 'active';
  bool get _isMemberExperience =>
      _userType != 'gym_operator' && _userType != 'trainer';

  String _norm(Object? value) => value?.toString().trim().toLowerCase() ?? '';

  String _gymTierKey(Map<String, dynamic> gym) {
    final tier = _norm(gym['tier']).replaceAll('-', '_').replaceAll(' ', '_');
    if (tier == 'mid_tier' || tier == 'midrange' || tier == 'mid_range') {
      return 'midtier';
    }
    if (tier == 'luxury' || tier == 'executive') return 'luxury_executive';
    return tier;
  }

  bool _containsQuery(Object? value, String query) =>
      _norm(value).contains(query);

  bool _listContainsQuery(Object? value, String query) =>
      (value as List? ?? const []).any((item) => _containsQuery(item, query));

  String _gymAccessLabel(String access, BuildContext context) {
    switch (access) {
      case 'luxury_executive':
        return context.tr('member.accessAll');
      case 'premium':
        return context.tr('member.accessPremium');
      case 'midtier':
        return context.tr('member.accessMidtier');
      default:
        return context.tr('member.accessStandard');
    }
  }

  bool get _needsOnboarding {
    // Only show member onboarding for actual member userType
    if (_userType != 'member') return false;
    // If auth.user already says onboarded, trust it (cached from prefs)
    if (AppScope.of(context).auth.user?['onboardingCompleted'] == true) {
      return false;
    }
    // Check fresh /me response
    final user = _me?['user'] as Map?;
    return _me != null && user?['onboardingCompleted'] != true;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openTab(int tab) {
    setState(() {
      _tab = tab;
      _selectedGym = null;
      _selectedTrainer = null;
      _showPassSelection = false;
      _showPayment = false;
    });
    if (tab == 3 && _hasActivePass) {
      _refreshQr();
    }
  }

  void _openOwnerTab(int tab) {
    setState(() {
      _tab = tab;
      _ownerView = null;
      _selectedOwnerGym = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final userType =
        AppScope.of(context).auth.user?['userType']?.toString() ??
        AppScope.of(context).auth.role;
    if (userType == 'gym_operator') {
      return _ownerScaffold();
    }
    if (userType == 'trainer') {
      return _roleScaffold(
        context.tr('trainer.dashboard'),
        _trainerDashboard(),
      );
    }

    if (_needsOnboarding) {
      return Scaffold(body: SafeArea(child: _onboarding()));
    }

    Widget body;
    if (_showPayment) {
      body = _paymentScreen();
    } else if (_showPassSelection) {
      body = _passSelectionScreen();
    } else if (_selectedGym != null) {
      body = _gymDetail(_selectedGym!);
    } else if (_selectedTrainer != null) {
      body = _trainerDetail(_selectedTrainer!);
    } else {
      body = [
        _homeTab(),
        _gymsTab(),
        _trainersTab(),
        _qrTab(),
        _profileTab(),
      ][_tab];
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.title'))),
      body: RefreshIndicator(onRefresh: _refreshAll, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _openTab,
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
    );
  }

  Widget _roleScaffold(String title, Widget body) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_ownerView != null)
            IconButton(
              tooltip: context.tr('home.back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                _ownerView = null;
                _selectedOwnerGym = null;
              }),
            ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _refreshAll, child: body),
    );
  }

  Widget _ownerScaffold() {
    final ownerTab = _tab.clamp(0, 3).toInt();
    Widget body;
    if (_ownerView == 'checkins' && _selectedOwnerGym != null) {
      body = _ownerCheckinsView(_selectedOwnerGym!);
    } else if (_ownerView == 'earnings') {
      body = _ownerEarningsView();
    } else {
      body = [
        _ownerDashboard(),
        _ownerManageGymsView(),
        _ownerTrainersView(showBack: false),
        _ownerProfileView(),
      ][ownerTab];
    }

    final title = _ownerView == 'checkins'
        ? context.tr('owner.gymCheckins')
        : _ownerView == 'earnings'
        ? context.tr('owner.earnings')
        : [
            context.tr('owner.dashboard'),
            context.tr('owner.manageGyms'),
            context.tr('owner.trainers'),
            context.tr('owner.profile'),
          ][ownerTab];

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _ownerView != null
            ? IconButton(
                tooltip: context.tr('home.back'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _ownerView = null;
                  _selectedOwnerGym = null;
                }),
              )
            : null,
        // actions: [
        //   if (_ownerView != null)
        //     IconButton(
        //       tooltip: context.tr('home.back'),
        //       icon: const Icon(Icons.arrow_back),
        //       onPressed: () => setState(() {
        //         _ownerView = null;
        //         _selectedOwnerGym = null;
        //       }),
        //     ),
        // ],
      ),
      body: RefreshIndicator(onRefresh: _refreshAll, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: ownerTab,
        onDestinationSelected: _openOwnerTab,
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
    );
  }

  Widget _ownerDashboard() {
    final todayCount = (_dashboard?['todayCount'] as num?)?.toInt() ?? 0;
    final monthVisits = (_dashboard?['monthVisits'] as num?)?.toInt() ?? 0;
    final dashGym = _dashboard?['gym'] as Map<String, dynamic>?;
    final ownerGymList = _ownerGyms.cast<Map<String, dynamic>>().toList();
    final primaryGym = ownerGymList.isNotEmpty ? ownerGymList.first : dashGym;

    return _scroll([
      _muted(context.tr('owner.dashboardBody')),
      const SizedBox(height: 14),
      // Primary gym card
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(context.tr('owner.gymProfile')),
            Text(
              primaryGym?['name']?.toString() ??
                  context.tr('owner.pendingApproval'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            _muted(
              primaryGym?['location']?.toString() ??
                  context.tr('owner.gymPending'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      // Stats row
      Row(
        children: [
          Expanded(
            child: _metric('$todayCount', context.tr('owner.todayCheckins')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metric('$monthVisits', context.tr('owner.monthCheckins')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metric(
              primaryGym?['tier']?.toString() ?? '-',
              context.tr('owner.tier'),
            ),
          ),
        ],
      ),
      _section(context.tr('owner.actions')),
      _actionTile(
        icon: Icons.qr_code_scanner,
        title: context.tr('owner.scan'),
        onTap: () => context.push(AppRoutes.ownerQrScanner),
      ),
      _actionTile(
        icon: Icons.people,
        title: context.tr('owner.members'),
        subtitle: '${context.tr('owner.checkins')}: $monthVisits',
        onTap: () {
          if (primaryGym != null) {
            setState(() {
              _ownerView = 'checkins';
              _selectedOwnerGym = primaryGym;
            });
          }
        },
      ),
      _actionTile(
        icon: Icons.person_add,
        title: context.tr('owner.addMember'),
        onTap: _showAddMemberDialog,
      ),
      _actionTile(
        icon: Icons.sports_gymnastics,
        title: context.tr('owner.trainers'),
        subtitle: '${_ownerTrainers.length}',
        onTap: () => _openOwnerTab(2),
      ),
      _actionTile(
        icon: Icons.payments,
        title: context.tr('owner.earnings'),
        onTap: () => setState(() => _ownerView = 'earnings'),
      ),
      _actionTile(
        icon: Icons.person_outline,
        title: context.tr('owner.profile'),
        onTap: () => _openOwnerTab(3),
      ),
      // _actionTile(
      //   icon: Icons.logout,
      //   title: context.tr('home.signout'),
      //   onTap: _signOut,
      // ),
      // My Gyms section
      _section(context.tr('owner.myGyms')),
      if (ownerGymList.isEmpty)
        _empty()
      else
        ...ownerGymList.take(2).map(_ownerGymCard),
      if (ownerGymList.length > 2)
        OutlinedButton.icon(
          onPressed: () => _openOwnerTab(1),
          icon: const Icon(Icons.fitness_center),
          label: Text(context.tr('owner.manageGyms')),
        ),
    ]);
  }

  Widget _ownerManageGymsView() {
    final ownerGymList = _ownerGyms.cast<Map<String, dynamic>>().toList();
    return _scroll([
      _title(context.tr('owner.manageGyms')),
      _muted(context.tr('owner.gymProfile')),
      const SizedBox(height: 14),
      if (ownerGymList.isEmpty)
        _empty()
      else
        ...ownerGymList.map(_ownerGymCard),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _showAddGymDialog,
        icon: const Icon(Icons.add),
        label: Text(context.tr('owner.addGym')),
      ),
    ]);
  }

  // Owner stats date filter
  DateTime? _statsFrom;
  DateTime? _statsTo;

  Future<void> _pickStatsRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: (_statsFrom != null && _statsTo != null)
          ? DateTimeRange(start: _statsFrom!, end: _statsTo!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _statsFrom = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        _statsTo = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
    }
  }

  Widget _ownerCheckinsView(Map<String, dynamic> gym) {
    final gymId = gym['id']?.toString() ?? '';
    final rangeLabel = (_statsFrom != null && _statsTo != null)
        ? '${_statsFrom!.toLocal().toString().split(' ').first} → '
              '${_statsTo!.toLocal().toString().split(' ').first}'
        : context.tr('owner.allTime');
    return _scroll([
      // _backTitle(context.tr('owner.gymCheckins'), () {
      //   setState(() {
      //     _ownerView = null;
      //     _selectedOwnerGym = null;
      //   });
      // }),
      _muted(gym['name']?.toString() ?? ''),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickStatsRange,
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(rangeLabel, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (_statsFrom != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.tr('owner.clearFilter'),
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() {
                _statsFrom = null;
                _statsTo = null;
              }),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      FutureBuilder<List<dynamic>>(
        future: AppScope.of(context).api.ownerGymCheckins(gymId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          var items = (snap.data ?? []).cast<Map<String, dynamic>>();
          if (_statsFrom != null && _statsTo != null) {
            items = items.where((c) {
              final ts = DateTime.tryParse(c['timestamp']?.toString() ?? '');
              if (ts == null) return false;
              return !ts.isBefore(_statsFrom!) && !ts.isAfter(_statsTo!);
            }).toList();
          }
          if (items.isEmpty) {
            return _card(
              Text(
                context.tr('owner.noCheckins'),
                style: const TextStyle(color: FFTokens.textMuted),
              ),
            );
          }
          return Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      '${items.length}',
                      context.tr('owner.checkins'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...items.take(50).map((c) {
                final member = c['member'] as Map?;
                final memberName =
                    member?['displayName']?.toString() ??
                    member?['email']?.toString() ??
                    c['memberName']?.toString() ??
                    c['memberId']?.toString() ??
                    '';
                return _actionTile(
                  icon: Icons.check_circle_outline,
                  title: memberName,
                  subtitle: c['timestamp']?.toString() ?? '',
                  onTap: () {},
                );
              }),
            ],
          );
        },
      ),
    ]);
  }

  Widget _ownerTrainersView({bool showBack = true}) {
    final items = _ownerTrainers.cast<Map<String, dynamic>>().toList();
    return _scroll([
      // if (showBack)
      //   _backTitle(context.tr('owner.trainers'), () {
      //     setState(() => _ownerView = null);
      //   })
      // else
      //   _title(context.tr('owner.trainers')),
      const SizedBox(height: 14),
      if (items.isEmpty)
        _empty()
      else
        ...items.map(
          (t) => _card(
            Row(
              children: [
                const Icon(Icons.sports_gymnastics, color: FFTokens.brandDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['displayName']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        (t['specialties'] as List? ?? []).join(' / '),
                        style: const TextStyle(
                          color: FFTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (t['phone'] != null)
                        Text(
                          t['phone'].toString(),
                          style: const TextStyle(
                            color: FFTokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showEditTrainerDialog(t),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.person_remove,
                    size: 20,
                    color: Colors.red,
                  ),
                  onPressed: () => _confirmRemoveTrainer(t),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _showAddTrainerDialog,
        icon: const Icon(Icons.add),
        label: Text(context.tr('owner.addTrainer')),
      ),
    ]);
  }

  Widget _ownerProfileView() {
    final user = (_me?['user'] as Map?) ?? AppScope.of(context).auth.user ?? {};
    final email = user['email']?.toString() ?? '';
    final phone = user['phone']?.toString() ?? '';
    return _scroll([
      _card(
        Row(
          children: [
            const CircleAvatar(radius: 30, child: Icon(Icons.person)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _muted(email.isNotEmpty ? email : phone),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _metric('${_ownerGyms.length}', context.tr('owner.myGyms')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metric(
              '${_ownerTrainers.length}',
              context.tr('owner.trainers'),
            ),
          ),
        ],
      ),
      _section(context.tr('member.accountSettings')),
      _actionTile(
        icon: Icons.edit,
        title: context.tr('member.editDetails'),
        onTap: _showEditProfileDialog,
      ),
      _actionTile(
        icon: Icons.help_outline,
        title: context.tr('member.help'),
        onTap: _openWhatsAppSupport,
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout, color: FFTokens.fgTertiary),
        label: Text(
          context.tr('home.signout'),
          style: const TextStyle(color: FFTokens.fgTertiary),
        ),
      ),
    ]);
  }

  Widget _ownerEarningsView() {
    return _scroll([
      // _backTitle(context.tr('owner.earnings'), () {
      //   setState(() => _ownerView = null);
      // }),
      const SizedBox(height: 14),
      FutureBuilder<Map<String, dynamic>>(
        future: AppScope.of(context).api.ownerEarnings(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ?? {};
          final totalPaid = (data['totalPaid'] as num?)?.toInt() ?? 0;
          final totalPending = (data['totalPending'] as num?)?.toInt() ?? 0;
          final paidCount = (data['paidCount'] as num?)?.toInt() ?? 0;
          final pendingCount = (data['pendingCount'] as num?)?.toInt() ?? 0;
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      'TZS $totalPaid',
                      context.tr('owner.earningsTotal'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metric(
                      'TZS $totalPending',
                      context.tr('owner.earningsPending'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _actionTile(
                icon: Icons.check_circle,
                title: '$paidCount paid invoices',
                subtitle: 'TZS $totalPaid',
                onTap: () {},
              ),
              _actionTile(
                icon: Icons.pending,
                title: '$pendingCount pending invoices',
                subtitle: 'TZS $totalPending',
                onTap: () {},
              ),
            ],
          );
        },
      ),
    ]);
  }

  Widget _trainerDashboard() {
    final email = AppScope.of(context).auth.user?['email']?.toString();
    final trainer = _trainers
        .cast<Map<String, dynamic>>()
        .where((t) => t['email']?.toString() == email)
        .firstOrNull;
    final gyms = (trainer?['gyms'] as List?)?.whereType<Map>().toList() ?? [];
    return _scroll([
      _title(context.tr('trainer.dashboard')),
      _muted(context.tr('trainer.dashboardBody')),
      const SizedBox(height: 14),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(context.tr('trainer.profile')),
            Text(
              trainer?['displayName']?.toString() ?? _displayName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            _muted((trainer?['specialties'] as List? ?? []).join(' / ')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [_pill('${trainer?['sessionRateCurrency'] ?? 'TZS'} ${trainer?['hourlyRateTzs'] ?? 0}/hr')],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _metric('${gyms.length}', context.tr('trainer.gyms')),
          ),
        ],
      ),
      _section(context.tr('trainer.sessions')),
      _actionTile(
        icon: Icons.event_available,
        title: context.tr('trainer.todaySessions'),
        onTap: () {},
      ),
      _actionTile(
        icon: Icons.payments,
        title: context.tr('trainer.earnings'),
        onTap: () {},
      ),
      _actionTile(
        icon: Icons.edit,
        title: context.tr('trainer.editProfile'),
        onTap: () {},
      ),
      _section(context.tr('trainer.gyms')),
      if (gyms.isEmpty)
        _empty()
      else
        ...gyms.map(
          (g) => _actionTile(
            icon: Icons.fitness_center,
            title: g['name']?.toString() ?? '',
            subtitle: g['location']?.toString(),
            onTap: () {},
          ),
        ),
    ]);
  }

  Widget _scroll(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: children,
    );
  }

  Widget _onboarding() {
    if (_onboardingStep == 0) {
      return _scroll([
        _stepText(context.tr('member.goalsStep')),
        _title(context.tr('member.goalsTitle')),
        _muted(context.tr('member.goalsBody')),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _multiChoice(
              'gain_muscle',
              context.tr('member.goal.gain_muscle'),
              _goals,
            ),
            _multiChoice(
              'lose_weight',
              context.tr('member.goal.lose_weight'),
              _goals,
            ),
            _multiChoice(
              'stay_fit',
              context.tr('member.goal.stay_fit'),
              _goals,
            ),
            _multiChoice(
              'flexibility',
              context.tr('member.goal.flexibility'),
              _goals,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _section(context.tr('member.detailsTitle')),
        Row(
          children: [
            Expanded(
              child: _choice(
                'beginner',
                context.tr('member.level.beginner'),
                _level,
                (v) => setState(() => _level = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _choice(
                'intermediate',
                context.tr('member.level.intermediate'),
                _level,
                (v) => setState(() => _level = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _choice(
                'advanced',
                context.tr('member.level.advanced'),
                _level,
                (v) => setState(() => _level = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => setState(() => _onboardingStep = 1),
          child: Text(context.tr('member.continue')),
        ),
        TextButton(
          onPressed: _saveOnboarding,
          child: Text(context.tr('member.skip')),
        ),
      ]);
    }
    if (_onboardingStep == 1) {
      return _scroll([
        _stepText(context.tr('member.detailsStep')),
        _title(context.tr('member.detailsTitle')),
        _muted(context.tr('member.detailsBody')),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _readonlyInput(context.tr('member.height'), '172')),
            const SizedBox(width: 10),
            Expanded(child: _readonlyInput(context.tr('member.weight'), '74')),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => setState(() => _onboardingStep = 2),
          child: Text(context.tr('member.continue')),
        ),
        TextButton(
          onPressed: () => setState(() => _onboardingStep = 2),
          child: Text(context.tr('member.skip')),
        ),
      ]);
    }
    return _scroll([
      const Icon(Icons.verified, size: 72, color: FFTokens.brand),
      const SizedBox(height: 18),
      _title(context.tr('member.welcomeTitle')),
      _muted(context.tr('member.welcomeBody')),
      const SizedBox(height: 18),
      _actionTile(
        icon: Icons.fitness_center,
        title: context.tr('member.browseGyms'),
        onTap: () async {
          await _saveOnboarding();
          _openTab(1);
        },
      ),
      _actionTile(
        icon: Icons.sports_gymnastics,
        title: context.tr('member.findTrainer'),
        onTap: () async {
          await _saveOnboarding();
          _openTab(2);
        },
      ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _saveOnboarding,
        child: Text(context.tr('member.enterApp')),
      ),
    ]);
  }

  Widget _homeTab() {
    final gyms = _gyms.take(2).cast<Map<String, dynamic>>().toList();
    final trainers = _trainers.take(2).cast<Map<String, dynamic>>().toList();
    return _scroll([
      Text(
        context.tr('member.goodMorning'),
        style: const TextStyle(color: FFTokens.textMuted),
      ),
      _title(_displayName),
      const SizedBox(height: 12),
      _passSummary(),
      _sectionRow(context.tr('member.nearGyms'), () => _openTab(1)),
      ...gyms.map(_compactGymCard),
      _sectionRow(context.tr('member.featuredTrainers'), () => _openTab(2)),
      ...trainers.map(_trainerCard),
      _section(context.tr('member.activity')),
      _checkinList(limit: 3),
    ]);
  }

  Widget _gymsTab() {
    var gyms = _gyms.cast<Map<String, dynamic>>().toList();

    // Search
    final gymQuery = _norm(_gymSearch);
    if (gymQuery.isNotEmpty) {
      gyms = gyms
          .where(
            (g) =>
                _containsQuery(g['name'], gymQuery) ||
                _containsQuery(g['location'], gymQuery) ||
                _containsQuery(g['tier'], gymQuery) ||
                _listContainsQuery(g['amenities'], gymQuery) ||
                _listContainsQuery(g['equipment'], gymQuery),
          )
          .toList();
    }

    // Tier / sort filter
    if (_gymFilter == 'nearest') {
      if (_userPosition == null) {
        _requestLocation();
      } else {
        gyms.sort((a, b) => _distanceToGym(a).compareTo(_distanceToGym(b)));
      }
    } else if (_gymFilter == 'standard') {
      gyms = gyms.where((g) => _gymTierKey(g) == 'standard').toList();
    } else if (_gymFilter == 'midtier') {
      gyms = gyms.where((g) => _gymTierKey(g) == 'midtier').toList();
    } else if (_gymFilter == 'premium') {
      gyms = gyms.where((g) {
        final tier = _gymTierKey(g);
        return tier == 'premium' || tier == 'luxury_executive';
      }).toList();
    } else if (_gymFilter == 'my_sub') {
      // Show only gyms compatible with the member's active subscription tier
      final subAccess = _subscription?['tier']?.toString();
      final passes = _passes.cast<Map<String, dynamic>>();
      final gymAccess = passes
          .firstWhere((p) => p['id'] == subAccess || p['key'] == subAccess,
              orElse: () => const {})
          .cast<String, dynamic>()['gymAccess']
          ?.toString();
      if (gymAccess != null && gymAccess.isNotEmpty) {
        gyms = gyms.where((g) {
          final tierKey = _gymTierKey(g);
          if (gymAccess == 'luxury_executive') return true;
          if (gymAccess == 'premium') return tierKey != 'luxury_executive';
          if (gymAccess == 'midtier') return tierKey == 'standard' || tierKey == 'midtier';
          return tierKey == 'standard';
        }).toList();
      }
    }

    // Amenity filter
    if (_gymAmenityFilter.isNotEmpty) {
      gyms = gyms.where((g) => _listContainsQuery(g['amenities'], _gymAmenityFilter)).toList();
    }

    // Price filter
    if (_gymPriceFilter == 'under30k') {
      gyms = gyms.where((g) => (g['ratePerMonth'] as num? ?? double.infinity) < 30000).toList();
    } else if (_gymPriceFilter == '30k_60k') {
      gyms = gyms.where((g) {
        final p = (g['ratePerMonth'] as num? ?? 0).toDouble();
        return p >= 30000 && p <= 60000;
      }).toList();
    } else if (_gymPriceFilter == 'over60k') {
      gyms = gyms.where((g) => (g['ratePerMonth'] as num? ?? 0) > 60000).toList();
    }

    // Collect all unique amenities from loaded gyms for amenity chips
    final allAmenities = <String>{};
    for (final g in _gyms.cast<Map<String, dynamic>>()) {
      final ams = g['amenities'];
      if (ams is List) allAmenities.addAll(ams.map((a) => a.toString()));
    }

    final tierFilters = ['all', 'nearest', 'standard', 'midtier', 'premium', 'my_sub'];
    final tierLabels = [
      context.tr('member.all'),
      context.tr('member.nearest'),
      'Standard', 'Mid-Range', 'Premium',
      context.tr('member.mySubFilter'),
    ];
    final priceFilters = ['any', 'under30k', '30k_60k', 'over60k'];
    final priceLabels = [
      context.tr('member.anyPrice'),
      '< 30,000', '30k – 60k', '> 60,000',
    ];

    return _scroll([
      _title(context.tr('member.discoverGyms')),
      TextField(
        controller: _gymSearchCtrl,
        decoration: InputDecoration(
          hintText: context.tr('member.searchGyms'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _gymSearch.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _gymSearchCtrl.clear();
                    setState(() => _gymSearch = '');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          ),
        ),
        onChanged: (v) => setState(() => _gymSearch = v),
      ),
      const SizedBox(height: 10),
      // Tier / sort filter row
      SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: tierFilters.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => setState(() => _gymFilter = tierFilters[i]),
            child: _pill(tierLabels[i], filled: _gymFilter == tierFilters[i]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      // Price filter row
      SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: priceFilters.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => setState(() => _gymPriceFilter = priceFilters[i]),
            child: _pill(priceLabels[i], filled: _gymPriceFilter == priceFilters[i]),
          ),
        ),
      ),
      // Amenity chips (shown only when gyms have amenities)
      if (allAmenities.isNotEmpty) ...[   
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: () => setState(() => _gymAmenityFilter = ''),
                child: _pill(context.tr('member.allAmenities'), filled: _gymAmenityFilter.isEmpty),
              ),
              ...allAmenities.map((am) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  onTap: () => setState(() =>
                    _gymAmenityFilter = _gymAmenityFilter == am ? '' : am),
                  child: _pill(am, filled: _gymAmenityFilter == am),
                ),
              )),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (gyms.isEmpty) _empty() else ...gyms.map(_compactGymCard),
    ]);
  }

  Widget _gymDetail(Map<String, dynamic> gym) {
    final trainers = _trainers
        .cast<Map<String, dynamic>>()
        .where(
          (t) => ((t['gyms'] as List?) ?? []).whereType<Map>().any(
            (g) => g['id'] == gym['id'],
          ),
        )
        .take(2);
    return _scroll([
      // _backTitle(
      //   context.tr('member.gymDetail'),
      //   () => setState(() => _selectedGym = null),
      // ),
      _imageHero(gym),
      _title(gym['name']?.toString() ?? ''),
      _muted(gym['location']?.toString() ?? ''),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        children: [
          _pill(gym['tier']?.toString() ?? ''),
          _pill(
            (gym['accessMode'] == 'free_online')
                ? context.tr('gym.free')
                : context.tr('gym.paid'),
          ),
        ],
      ),
      _section(context.tr('member.pricing')),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((gym['ratePerDay'] as num? ?? 0) > 0)
              _row(context.tr('gym.perDay'), 'TZS ${gym['ratePerDay']}'),
            if ((gym['ratePerWeek'] as num? ?? 0) > 0)
              _row(context.tr('gym.perWeek'), 'TZS ${gym['ratePerWeek']}'),
            if ((gym['ratePerMonth'] as num? ?? 0) > 0)
              _row(context.tr('gym.perMonth'), 'TZS ${gym['ratePerMonth']}'),
            if ((gym['perVisitRate'] as num? ?? 0) > 0)
              _row(context.tr('gym.perVisit'), 'TZS ${gym['perVisitRate']}'),
            if ((gym['ratePerDay'] as num? ?? 0) == 0 &&
                (gym['ratePerWeek'] as num? ?? 0) == 0 &&
                (gym['ratePerMonth'] as num? ?? 0) == 0 &&
                (gym['perVisitRate'] as num? ?? 0) == 0)
              _muted(context.tr('gym.free')),
          ],
        ),
      ),
      _section(context.tr('member.trainersAtGym')),
      if (trainers.isEmpty) _empty() else ...trainers.map(_trainerCard),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: () => setState(() => _showPassSelection = true),
              child: Text(context.tr('member.subscribe')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _openTab(3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(context.tr('member.visitWithPass')),
              ),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _passSelectionScreen() {
    return _scroll([
      // _backTitle(
      //   context.tr('member.choosePlan'),
      //   () => setState(() => _showPassSelection = false),
      // ),
      _muted(context.tr('member.planBody')),
      const SizedBox(height: 14),
      if (!_passesLoaded)
        const Center(child: CircularProgressIndicator())
      else if (_passes.isEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(
                  context.tr('home.passesLoadError'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FFTokens.fgQuaternary),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _passesLoaded = false);
                    _refreshPasses();
                  },
                  child: Text(context.tr('home.retry')),
                ),
              ],
            ),
          ),
        )
      else ...[  
        ..._passes.cast<Map<String, dynamic>>().map((p) => _selectablePass(p)),
        const SizedBox(height: 12),
        _section(context.tr('member.compatibleGyms')),
        _muted(context.tr('member.compatibleGymsBody')),
        const SizedBox(height: 8),
        if (_selectedTier.isNotEmpty)
          ..._passes
              .cast<Map<String, dynamic>>()
              .where((p) => p['id'] == _selectedTier)
              .map((p) {
                final access = p['gymAccess']?.toString() ?? '';
                return _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('member.accessLevel'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(_gymAccessLabel(access, context), style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showPassSelection = false;
                            _showPayment = false;
                            _gymFilter = 'my_sub';
                          });
                          _openTab(1);
                        },
                        icon: const Icon(Icons.fitness_center, size: 16),
                        label: Text(context.tr('member.browseCompatibleGyms')),
                      ),
                    ],
                  ),
                );
              }),
      ],
      const SizedBox(height: 8),
      if (_selectedTier.isNotEmpty &&
          _passes.cast<Map<String, dynamic>>().any(
            (p) => p['id'] == _selectedTier,
          ))
        FilledButton(
          onPressed: () => setState(() => _showPayment = true),
          child: Text(context.tr('member.continuePayment')),
        ),
    ]);
  }

  Widget _paymentScreen() {
    final pass = _passes.cast<Map<String, dynamic>>().firstWhere(
      (p) => p['id'] == _selectedTier,
      orElse: () => {'id': _selectedTier, 'price': 0, 'visitCap': null},
    );
    return _scroll([
      // _backTitle(
      //   context.tr('member.payment'),
      //   () => setState(() => _showPayment = false),
      // ),
      _muted(context.tr('member.paymentBody')),
      const SizedBox(height: 14),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(context.tr('member.orderSummary')),
            _row(
              context.tr('member.choosePlan'),
              context.tr('pass.${pass['id']}'),
            ),
            _row(
              context.tr('home.visits'),
              pass['visitCap'] == null
                  ? context.tr('pass.unlimited')
                  : '${pass['visitCap']}',
            ),
            _row('Total', 'TZS ${pass['price'] ?? 0}'),
          ],
        ),
      ),
      _section(context.tr('member.paymentMethod')),
      _actionTile(icon: Icons.phone_android, title: 'M-Pesa', onTap: () {}),
      _actionTile(
        icon: Icons.account_balance,
        title: 'CRDB Bank Transfer',
        onTap: () {},
      ),
      _actionTile(
        icon: Icons.account_balance,
        title: 'NMB Bank Transfer',
        onTap: () {},
      ),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: _requestSelectedPass,
        child: Text(context.tr('member.requestPayment')),
      ),
    ]);
  }

  Widget _trainersTab() {
    var trainers = _trainers.cast<Map<String, dynamic>>().toList();
    // Apply search
    final trainerQuery = _norm(_trainerSearch);
    if (trainerQuery.isNotEmpty) {
      trainers = trainers
          .where(
            (t) =>
                _containsQuery(t['displayName'], trainerQuery) ||
                _containsQuery(t['bio'], trainerQuery) ||
                _listContainsQuery(t['specialties'], trainerQuery) ||
                ((t['gyms'] as List? ?? const []).whereType<Map>().any(
                  (g) =>
                      _containsQuery(g['name'], trainerQuery) ||
                      _containsQuery(g['location'], trainerQuery),
                )),
          )
          .toList();
    }
    // Apply specialty filter
    if (_trainerFilter != 'all') {
      final filter = _norm(_trainerFilter);
      trainers = trainers
          .where(
            (t) => (t['specialties'] as List? ?? []).any(
              (s) => _norm(
                s,
              ).replaceAll(' ', '').contains(filter.replaceAll(' ', '')),
            ),
          )
          .toList();
    }
    final filters = ['all', 'Weights', 'Cardio', 'Yoga', 'Boxing'];
    return _scroll([
      _title(context.tr('member.findTrainerTitle')),
      TextField(
        controller: _trainerSearchCtrl,
        decoration: InputDecoration(
          hintText: context.tr('member.searchTrainers'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _trainerSearch.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _trainerSearchCtrl.clear();
                    setState(() => _trainerSearch = '');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          ),
        ),
        onChanged: (v) => setState(() => _trainerSearch = v),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: filters.length,
          separatorBuilder: (_, separatorIndex) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => setState(() => _trainerFilter = filters[i]),
            child: _pill(
              filters[i] == 'all' ? context.tr('member.all') : filters[i],
              filled: _trainerFilter == filters[i],
            ),
          ),
        ),
      ),
      _section(context.tr('member.topRated')),
      if (trainers.isEmpty) _empty() else ...trainers.map(_trainerCard),
    ]);
  }

  Widget _trainerDetail(Map<String, dynamic> trainer) {
    final gyms = (trainer['gyms'] as List?)?.whereType<Map>().toList() ?? [];
    final availability =
        (trainer['availability'] as List?)?.whereType<Map>().toList() ?? [];
    return _scroll([
      // _backTitle(
      //   context.tr('member.findTrainerTitle'),
      //   () => setState(() => _selectedTrainer = null),
      // ),
      _title(trainer['displayName']?.toString() ?? ''),
      _muted((trainer['specialties'] as List? ?? []).join(' / ')),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        children: [_pill('${trainer['sessionRateCurrency'] ?? 'TZS'} ${trainer['hourlyRateTzs'] ?? 0}/hr')],
      ),
      _section(context.tr('member.about')),
      _card(
        Text(
          trainer['bio']?.toString() ?? '',
          style: const TextStyle(color: FFTokens.textMuted, height: 1.35),
        ),
      ),
      _section(context.tr('member.availableGyms')),
      if (gyms.isEmpty)
        _empty()
      else
        ...gyms.map(
          (g) => _actionTile(
            icon: Icons.fitness_center,
            title: g['name']?.toString() ?? '',
            subtitle: g['location']?.toString(),
            onTap: () {},
          ),
        ),
      _section(context.tr('member.availability')),
      if (availability.isEmpty)
        _muted(context.tr('member.noAvailability'))
      else
        ...availability.map(
          (a) => _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a['date']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: (a['slots'] as List? ?? [])
                      .map<Widget>((s) => _pill(s.toString()))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _qrTab() {
    return _scroll([
      if (_pendingPayment != null) _pendingPaymentCard(_pendingPayment!),
      if (_hasActivePass) _qrCard() else _qrLockedCard(),
      _section(context.tr('member.recentCheckins')),
      _checkinList(limit: 5),
    ]);
  }

  Widget _profileTab() {
    final visitsUsed = (_me?['visitsUsed'] as num?)?.toInt() ?? 0;
    final visitCap = (_me?['visitCap'] as num?)?.toInt();
    return _scroll([
      _card(
        Row(
          children: [
            const CircleAvatar(radius: 30, child: Icon(Icons.person)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _muted(
                    _subscription?['tier']?.toString() ??
                        context.tr('pass.pending'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _metric('$visitsUsed', context.tr('home.visits'))),
          const SizedBox(width: 8),
          Expanded(
            child: _metric(
              visitCap == null ? '-' : '$visitCap',
              context.tr('pass.visits'),
            ),
          ),
        ],
      ),
      _section(context.tr('member.mySubscription')),
      _passSummary(),
      if (_hasActivePass) ...[  
        _actionTile(
          icon: Icons.qr_code_2,
          title: context.tr('member.showQr'),
          onTap: () => _openTab(3),
        ),
      ],
      _section(context.tr('member.visitHistory')),
      _checkinList(limit: 8),
      _section(context.tr('member.accountSettings')),
      _actionTile(
        icon: Icons.edit,
        title: context.tr('member.editDetails'),
        onTap: _showEditProfileDialog,
      ),
      _actionTile(
        icon: Icons.help_outline,
        title: context.tr('member.help'),
        onTap: _openWhatsAppSupport,
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout, color: FFTokens.fgTertiary),
        label: Text(
          context.tr('home.signout'),
          style: const TextStyle(color: FFTokens.fgTertiary),
        ),
      ),
    ]);
  }

  Widget _passSummary() {
    final sub = _subscription;
    final pending = _pendingPayment;
    final visitsUsed = (_me?['visitsUsed'] as num?)?.toInt() ?? 0;
    final visitCap = (_me?['visitCap'] as num?)?.toInt();
    final progress = visitCap == null || visitCap <= 0
        ? null
        : (visitsUsed / visitCap).clamp(0, 1).toDouble();
    final title = sub == null
        ? context.tr('home.subscribe')
        : context.tr('pass.${sub['tier']}');
    final status = pending != null
        ? context.tr('pass.pending')
        : sub?['status']?.toString() ?? context.tr('home.subscribe');
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('member.yourPass'),
            style: const TextStyle(color: FFTokens.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(status, style: const TextStyle(color: FFTokens.textMuted)),
          if (sub != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('home.visits'),
                    style: const TextStyle(
                      color: FFTokens.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  visitCap == null
                      ? '$visitsUsed / ${context.tr('pass.unlimited')}'
                      : '$visitsUsed / $visitCap',
                  style: const TextStyle(
                    color: FFTokens.fgSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress, color: FFTokens.brand),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _hasActivePass
                      ? () => _openTab(3)
                      : () => setState(() => _showPassSelection = true),
                  child: Text(
                    _hasActivePass
                        ? context.tr('member.showQr')
                        : context.tr('member.subscribe'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _showPassSelection = true),
                  child: Text(context.tr('member.upgradePlan')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qrCard() {
    return _card(
      Column(
        children: [
          Text(
            context.tr('home.qr'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_qrToken != null)
            QrImageView(
              data: _qrToken!,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: FFTokens.brandDark,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: FFTokens.brandDark,
              ),
            )
          else
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 8),
          Text(
            context.tr('home.qr.refreshes'),
            style: const TextStyle(color: FFTokens.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _qrLockedCard() {
    final title = _pendingPayment != null
        ? context.tr('home.qr.pendingTitle')
        : context.tr('home.qr.lockedTitle');
    final body = _pendingPayment != null
        ? context.tr('home.qr.pendingBody')
        : context.tr('home.qr.lockedBody');
    return _card(
      Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.qr_code_2, color: FFTokens.brandDark, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        color: FFTokens.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _showPassSelection = true),
              child: Text(context.tr('member.subscribe')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingPaymentCard(Map pending) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('pass.pending'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${pending['tier']?.toString().toUpperCase()} - TZS ${pending['amountTzs']}',
            style: const TextStyle(color: FFTokens.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _compactGymCard(Map<String, dynamic> gym) {
    return _card(
      InkWell(
        onTap: () => setState(() => _selectedGym = gym),
        child: Row(
          children: [
            SizedBox(width: 72, height: 72, child: _gymThumb(gym)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gym['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gym['location']?.toString() ?? '',
                    style: const TextStyle(
                      color: FFTokens.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      _pill(gym['tier']?.toString() ?? ''),
                      _pill(
                        gym['accessMode'] == 'free_online'
                            ? context.tr('gym.free')
                            : context.tr('gym.paid'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _trainerCard(Map<String, dynamic> trainer) {
    final specialties = (trainer['specialties'] as List? ?? []).join(' / ');
    return _card(
      InkWell(
        onTap: () => setState(() => _selectedTrainer = trainer),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 28,
              child: Icon(Icons.sports_gymnastics),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trainer['displayName']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    specialties,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FFTokens.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${trainer['sessionRateCurrency'] ?? 'TZS'} ${trainer['hourlyRateTzs'] ?? 0}/hr',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ownerGymCard(Map<String, dynamic> gym) {
    return _card(
      InkWell(
        onTap: () => setState(() {
          _ownerView = 'checkins';
          _selectedOwnerGym = gym;
        }),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 86, height: 86, child: _gymThumb(gym)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gym['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gym['location']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FFTokens.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _pill(gym['tier']?.toString() ?? ''),
                      _pill(
                        gym['status']?.toString() ??
                            context.tr('ownerReg.status_active'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: context.tr('owner.editGym'),
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showEditGymDialog(gym),
                ),
                IconButton(
                  tooltip: context.tr('owner.deleteGym'),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  onPressed: () => _confirmDeleteGym(gym),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectablePass(Map<String, dynamic> pass) {
    final id = pass['id'] as String;
    final selected = id == _selectedTier;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => setState(() => _selectedTier = id),
        child: Container(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          decoration: BoxDecoration(
            color: selected ? FFTokens.brandLight : FFTokens.surface,
            border: Border.all(
              color: selected ? FFTokens.brand : FFTokens.border,
            ),
            borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('pass.$id'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pass['visitCap'] == null
                          ? context.tr('pass.unlimited')
                          : '${pass['visitCap']} ${context.tr('pass.visits')}',
                      style: const TextStyle(
                        color: FFTokens.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'TZS ${pass['price'] ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkinList({required int limit}) {
    final items = _checkins.take(limit).cast<Map<String, dynamic>>().toList();
    if (items.isEmpty) return _empty();
    return Column(
      children: items.map((c) {
        final gym = c['gym'] as Map?;
        return _actionTile(
          icon: Icons.check_circle_outline,
          title: gym?['name']?.toString() ?? c['gymId']?.toString() ?? '',
          subtitle: c['timestamp']?.toString() ?? '',
          onTap: () {},
        );
      }).toList(),
    );
  }

  Widget _gymThumb(Map<String, dynamic> gym) {
    final images = (gym['images'] as List?)?.whereType<String>().toList() ?? [];
    if (images.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: FFTokens.brandLight,
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        child: const Icon(Icons.fitness_center, color: FFTokens.brandDark),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      child: FFRemoteImage(
        src: images.first,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        fallback: Container(
          color: FFTokens.brandLight,
          child: const Icon(Icons.fitness_center, color: FFTokens.brandDark),
        ),
      ),
    );
  }

  Widget _imageHero(Map<String, dynamic> gym) {
    return Container(
      height: 180,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: _gymThumb(gym),
    );
  }

  Widget _card(Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      decoration: BoxDecoration(
        color: FFTokens.surface,
        border: Border.all(color: FFTokens.border),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: child,
    );
  }

  Widget _metric(String value, String label) {
    return _card(
      Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: FFTokens.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return _card(
      InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: FFTokens.brandDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: FFTokens.textMuted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _choice(
    String value,
    String label,
    String selected,
    ValueChanged<String> onTap,
  ) {
    final active = value == selected;
    return InkWell(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? FFTokens.brandLight : FFTokens.surface,
          border: Border.all(color: active ? FFTokens.brand : FFTokens.border),
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _multiChoice(String value, String label, List<String> selectedList) {
    final active = selectedList.contains(value);
    return InkWell(
      onTap: () {
        setState(() {
          if (active) {
            selectedList.remove(value);
          } else {
            selectedList.add(value);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? FFTokens.brandLight : FFTokens.surface,
          border: Border.all(color: active ? FFTokens.brand : FFTokens.border),
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.check, size: 16, color: FFTokens.brand),
              ),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _readonlyInput(String label, String value) {
    return TextField(
      controller: TextEditingController(text: value),
      decoration: InputDecoration(labelText: label),
      readOnly: true,
    );
  }

  Widget _pill(String label, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? FFTokens.brand : FFTokens.brandLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: TextStyle(
          color: filled ? Colors.white : FFTokens.brandDark,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _title(String text) => Text(
    text,
    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );

  Widget _sectionRow(String text, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Row(
      children: [
        Expanded(child: _section(text)),
        TextButton(onPressed: onTap, child: Text(context.tr('home.seeAll'))),
      ],
    ),
  );

  // Widget _backTitle(String text, VoidCallback onBack) {
  //   return Row(
  //     children: [
  //       IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
  //       Expanded(child: _title(text)),
  //     ],
  //   );
  // }

  Widget _stepText(String text) => Text(
    text,
    style: const TextStyle(
      color: FFTokens.textMuted,
      fontWeight: FontWeight.w800,
      fontSize: 11,
    ),
  );

  Widget _muted(String text) => Text(
    text,
    style: const TextStyle(color: FFTokens.textMuted, height: 1.35),
  );

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: FFTokens.textMuted),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _empty() => _card(
    Text(
      context.tr('member.noData'),
      style: const TextStyle(color: FFTokens.textMuted),
    ),
  );
}

// ── Add Member Bottom Sheet ──────────────────────────────────────────────────

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({required this.ownerGymIds, required this.onSaved});
  final List<String> ownerGymIds;
  final Future<void> Function(Map<String, dynamic> payload) onSaved;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _durationUnit = 'M';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final payload = <String, dynamic>{
      'displayName': _nameCtrl.text.trim(),
      if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
      if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
      if (widget.ownerGymIds.isNotEmpty) 'gymId': widget.ownerGymIds.first,
      'durationUnit': _durationUnit,
      'startDate': _startDate.toIso8601String().split('T').first,
      'endDate': _endDate.toIso8601String().split('T').first,
      if (_amountCtrl.text.isNotEmpty)
        'paidAmount': num.tryParse(_amountCtrl.text) ?? 0,
    };
    try {
      await widget.onSaved(payload);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) _endDate = _startDate.add(const Duration(days: 30));
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('owner.addMember'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('member.fullName'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? context.tr('onboarding.required') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: context.tr('auth.email'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.tr('auth.phone'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('owner.paidAmount'),
                  suffixText: 'TZS',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _durationUnit,
                decoration: InputDecoration(
                  labelText: context.tr('owner.durationUnit'),
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'D', child: Text('Daily')),
                  DropdownMenuItem(value: 'W', child: Text('Weekly')),
                  DropdownMenuItem(value: 'M', child: Text('Monthly')),
                ],
                onChanged: (v) => setState(() => _durationUnit = v ?? 'M'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isStart: true),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        '${context.tr('owner.startDate')}: ${_startDate.toIso8601String().split('T').first}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isStart: false),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        '${context.tr('owner.endDate')}: ${_endDate.toIso8601String().split('T').first}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(context.tr('owner.registerMember')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.tr('member.cancel')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
