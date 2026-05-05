import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_scope.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/design_tokens.dart';
import '../shared/i18n.dart';
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
  List<dynamic> _gyms = const [];
  List<dynamic> _trainers = const [];
  List<dynamic> _checkins = const [];
  Timer? _qrTimer;
  bool _started = false;
  int _tab = 0;
  int _onboardingStep = 0;
  String _goal = 'gain_muscle';
  String _level = 'beginner';
  String _selectedTier = 'pro';
  Map<String, dynamic>? _selectedGym;
  Map<String, dynamic>? _selectedTrainer;
  bool _showPassSelection = false;
  bool _showPayment = false;

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
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshMe(),
      _refreshPasses(),
      _refreshGyms(),
      _refreshTrainers(),
      _refreshCheckins(),
      _refreshQr(),
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
    try {
      final res = await AppScope.of(context).api.listPasses();
      if (mounted) setState(() => _passes = res);
    } on ApiException {
      /* ignore */
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
    if (AppScope.of(context).auth.role != 'member') return;
    try {
      final res = await AppScope.of(context).api.myQr();
      if (mounted) setState(() => _qrToken = res['token'] as String?);
    } on ApiException {
      if (mounted) setState(() => _qrToken = null);
    }
  }

  Future<void> _saveOnboarding() async {
    try {
      await AppScope.of(context).api.updateProfile({
        'displayName': _displayName,
        'fitnessGoal': _goal,
        'fitnessLevel': _level,
        'preferredWorkoutTimes': ['early_morning', 'evening'],
        'notificationPreferences': {
          'checkinReminders': true,
          'promotionAlerts': true,
          'trainerBookingUpdates': true,
        },
      });
      await _refreshMe();
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

  Future<void> _bookTrainer(Map<String, dynamic> trainer) async {
    final gyms = (trainer['gyms'] as List?)?.whereType<Map>().toList() ?? [];
    final gymId = gyms.isNotEmpty ? gyms.first['id'] as String : 'gym_001';
    final confirmed = context.tr('member.bookingConfirmed');
    try {
      await AppScope.of(context).api.bookTrainer(
        trainerId: trainer['id'] as String,
        gymId: gymId,
        date: '2026-05-05',
        slot: '09:00',
      );
      _toast(confirmed);
    } on ApiException catch (e) {
      _toast('Error ${e.status}');
    }
  }

  Future<void> _signOut() async {
    await AppScope.of(context).auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LanguageScreen()),
      (_) => false,
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
  bool get _needsOnboarding {
    final user = _me?['user'] as Map?;
    return AppScope.of(context).auth.role == 'member' &&
        _me != null &&
        user?['onboardingCompleted'] != true;
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
  }

  @override
  Widget build(BuildContext context) {
    final userType =
        AppScope.of(context).auth.user?['userType']?.toString() ??
        AppScope.of(context).auth.role;
    if (userType == 'gym_operator') {
      return _roleScaffold(context.tr('owner.dashboard'), _ownerDashboard());
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
      appBar: AppBar(
        title: Text(context.tr('app.title')),
        actions: [
          IconButton(
            tooltip: context.tr('home.signout'),
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
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
          IconButton(
            tooltip: context.tr('home.signout'),
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _refreshAll, child: body),
    );
  }

  Widget _ownerDashboard() {
    final user = AppScope.of(context).auth.user;
    final gymId = user?['gymId']?.toString();
    final gym = _gyms
        .cast<Map<String, dynamic>>()
        .where((g) => g['id'] == gymId)
        .firstOrNull;
    return _scroll([
      _title(context.tr('owner.dashboard')),
      _muted(context.tr('owner.dashboardBody')),
      const SizedBox(height: 14),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(context.tr('owner.gymProfile')),
            Text(
              gym?['name']?.toString() ?? context.tr('owner.pendingApproval'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            _muted(
              gym?['location']?.toString() ?? context.tr('owner.gymPending'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _metric('${_checkins.length}', context.tr('owner.checkins')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metric(
              gym?['tier']?.toString() ?? '-',
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
        onTap: () {},
      ),
      _actionTile(
        icon: Icons.payments,
        title: context.tr('owner.payouts'),
        onTap: () {},
      ),
      _actionTile(
        icon: Icons.campaign,
        title: context.tr('owner.promos'),
        onTap: () {},
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
              children: [
                _pill('TZS ${trainer?['hourlyRateTzs'] ?? 0}/hr'),
                _pill('${trainer?['experienceYears'] ?? 0} yrs'),
              ],
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
          const SizedBox(width: 8),
          Expanded(
            child: _metric(
              '${trainer?['rating'] ?? '-'}',
              context.tr('trainer.rating'),
            ),
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
            _choice(
              'gain_muscle',
              context.tr('member.goal.gain_muscle'),
              _goal,
              (v) => setState(() => _goal = v),
            ),
            _choice(
              'lose_weight',
              context.tr('member.goal.lose_weight'),
              _goal,
              (v) => setState(() => _goal = v),
            ),
            _choice(
              'stay_fit',
              context.tr('member.goal.stay_fit'),
              _goal,
              (v) => setState(() => _goal = v),
            ),
            _choice(
              'flexibility',
              context.tr('member.goal.flexibility'),
              _goal,
              (v) => setState(() => _goal = v),
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
    final gyms = _gyms.cast<Map<String, dynamic>>().toList();
    return _scroll([
      _title(context.tr('member.discoverGyms')),
      _searchBox(context.tr('member.searchGyms')),
      const SizedBox(height: 12),
      _chips([
        context.tr('member.all'),
        context.tr('member.nearest'),
        'Standard',
        'Mid-Range',
        'Premium',
        context.tr('member.openNow'),
      ]),
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
      _backTitle(
        context.tr('member.gymDetail'),
        () => setState(() => _selectedGym = null),
      ),
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
      _section(context.tr('member.about')),
      _card(
        Text(
          gym['venueType'] == 'online'
              ? context.tr('member.planBody')
              : '${context.tr('member.openNow')} - QR Check-in - ${gym['perVisitRate'] ?? 0} TZS',
          style: const TextStyle(color: FFTokens.textMuted, height: 1.35),
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
              child: Text(context.tr('member.visitWithPass')),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _passSelectionScreen() {
    return _scroll([
      _backTitle(
        context.tr('member.choosePlan'),
        () => setState(() => _showPassSelection = false),
      ),
      _muted(context.tr('member.planBody')),
      const SizedBox(height: 14),
      ..._passes.cast<Map<String, dynamic>>().map((p) => _selectablePass(p)),
      const SizedBox(height: 8),
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
      _backTitle(
        context.tr('member.payment'),
        () => setState(() => _showPayment = false),
      ),
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
    final trainers = _trainers.cast<Map<String, dynamic>>().toList();
    return _scroll([
      _title(context.tr('member.findTrainerTitle')),
      _searchBox(context.tr('member.searchTrainers')),
      const SizedBox(height: 12),
      _chips([context.tr('member.all'), 'Weights', 'Cardio', 'Yoga', 'Boxing']),
      _section(context.tr('member.topRated')),
      if (trainers.isEmpty) _empty() else ...trainers.map(_trainerCard),
    ]);
  }

  Widget _trainerDetail(Map<String, dynamic> trainer) {
    final gyms = (trainer['gyms'] as List?)?.whereType<Map>().toList() ?? [];
    final availability =
        (trainer['availability'] as List?)?.whereType<Map>().toList() ?? [];
    return _scroll([
      _backTitle(
        context.tr('member.findTrainerTitle'),
        () => setState(() => _selectedTrainer = null),
      ),
      _title(trainer['displayName']?.toString() ?? ''),
      _muted((trainer['specialties'] as List? ?? []).join(' / ')),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        children: [
          _pill('TZS ${trainer['hourlyRateTzs'] ?? 0}/hr'),
          _pill('${trainer['experienceYears'] ?? 0} yrs'),
          _pill('${trainer['rating'] ?? '-'} rating'),
        ],
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
        _empty()
      else
        _chips(
          availability
              .expand(
                (a) =>
                    (a['slots'] as List? ?? []).map((s) => '${a['date']} $s'),
              )
              .cast<String>()
              .take(4)
              .toList(),
        ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: () => _bookTrainer(trainer),
        child: Text(
          '${context.tr('member.bookSession')} - TZS ${trainer['hourlyRateTzs'] ?? 0}',
        ),
      ),
    ]);
  }

  Widget _qrTab() {
    return _scroll([
      if (_pendingPayment != null) _pendingPaymentCard(_pendingPayment!),
      if (_hasActivePass) _qrCard() else _qrLockedCard(),
      const SizedBox(height: 12),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(context.tr('member.scanGymQr')),
            _muted(context.tr('home.qr')),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _toast(context.tr('member.scanGymQr')),
              icon: const Icon(Icons.camera_alt),
              label: Text(context.tr('member.scanGymQr')),
            ),
          ],
        ),
      ),
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
      _section(context.tr('member.visitHistory')),
      _checkinList(limit: 8),
      _section(context.tr('member.accountSettings')),
      _actionTile(
        icon: Icons.edit,
        title: context.tr('member.editDetails'),
        onTap: () {},
      ),
      _actionTile(
        icon: Icons.payment,
        title: context.tr('member.paymentMethods'),
        onTap: () {},
      ),
      _actionTile(
        icon: Icons.notifications,
        title: context.tr('member.notifications'),
        onTap: () {},
      ),
      _actionTile(
        icon: Icons.help_outline,
        title: context.tr('member.help'),
        onTap: () {},
      ),
    ]);
  }

  Widget _passSummary() {
    final sub = _subscription;
    final pending = _pendingPayment;
    final visitsUsed = (_me?['visitsUsed'] as num?)?.toInt() ?? 0;
    final visitCap = (_me?['visitCap'] as num?)?.toInt();
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
            LinearProgressIndicator(
              value: visitCap == null || visitCap == 0
                  ? null
                  : (visitsUsed / visitCap).clamp(0, 1).toDouble(),
              color: FFTokens.brand,
            ),
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
              'TZS ${trainer['hourlyRateTzs'] ?? 0}/hr',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
      child: Image.network(
        images.first,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
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

  Widget _readonlyInput(String label, String value) {
    return TextField(
      controller: TextEditingController(text: value),
      decoration: InputDecoration(labelText: label),
      readOnly: true,
    );
  }

  Widget _searchBox(String hint) {
    return TextField(
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        ),
      ),
    );
  }

  Widget _chips(List<String> labels) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _pill(labels[i], filled: i == 0),
      ),
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

  Widget _backTitle(String text, VoidCallback onBack) {
    return Row(
      children: [
        IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
        Expanded(child: _title(text)),
      ],
    );
  }

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
