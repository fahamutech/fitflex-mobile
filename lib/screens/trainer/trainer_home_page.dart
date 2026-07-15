import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/profile_form_page.dart';
import '../language_screen.dart';

/// Standalone trainer dashboard shown after trainer is onboarded.
class TrainerHomePage extends StatefulWidget {
  const TrainerHomePage({super.key});

  @override
  State<TrainerHomePage> createState() => _TrainerHomePageState();
}

class _TrainerHomePageState extends State<TrainerHomePage> {
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _trainers = [];
  List<Map<String, dynamic>> _gyms = [];
  bool _started = false;
  bool _applyBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_refreshMe(), _refreshTrainers(), _refreshGyms()]);
  }

  Future<void> _refreshMe() async {
    try {
      final res = await AppScope.of(context).api.me();
      if (mounted) setState(() => _me = res);
    } on ApiException {
      // ignore
    }
  }

  Future<void> _refreshTrainers() async {
    try {
      final res = await AppScope.of(context).api.listTrainers();
      if (mounted) {
        setState(() => _trainers = res.cast<Map<String, dynamic>>());
      }
    } on ApiException {
      // ignore
    }
  }

  Future<void> _refreshGyms() async {
    try {
      final res = await AppScope.of(context).api.listGyms();
      if (mounted) setState(() => _gyms = res.cast<Map<String, dynamic>>());
    } on ApiException {
      // ignore
    }
  }

  List<Map<String, dynamic>> get _pendingGyms =>
      (_myProfile?['pendingGyms'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      const [];

  List<Map<String, dynamic>> get _availableGymsToApply {
    final trainer = _myProfile;
    final linkedIds = (trainer?['gyms'] as List? ?? [])
        .whereType<Map>()
        .map((g) => g['id']?.toString())
        .toSet();
    final pendingIds = _pendingGyms.map((g) => g['id']?.toString()).toSet();
    return _gyms
        .where(
          (g) =>
              !linkedIds.contains(g['id']?.toString()) &&
              !pendingIds.contains(g['id']?.toString()),
        )
        .toList();
  }

  Future<void> _applyToGym(String gymId) async {
    setState(() => _applyBusy = true);
    try {
      await AppScope.of(context).api.trainerApplyToGym(gymId);
      if (!mounted) return;
      await _refreshTrainers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('trainer.applicationSent'))),
      );
    } on ApiException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('owner.errorGeneric'))));
    } finally {
      if (mounted) setState(() => _applyBusy = false);
    }
  }

  Future<void> _cancelApplication(String gymId) async {
    setState(() => _applyBusy = true);
    try {
      await AppScope.of(context).api.trainerCancelGymApplication(gymId);
      if (!mounted) return;
      await _refreshTrainers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('trainer.applicationCancelled'))),
      );
    } on ApiException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('owner.errorGeneric'))));
    } finally {
      if (mounted) setState(() => _applyBusy = false);
    }
  }

  Future<void> _showApplyGymSheet() async {
    final available = _availableGymsToApply;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('trainer.applyToGym'),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              if (available.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(context.tr('trainer.noGymsToApply')),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: available.length,
                    itemBuilder: (context, i) {
                      final gym = available[i];
                      return ListTile(
                        title: Text(gym['name']?.toString() ?? ''),
                        subtitle: Text(gym['location']?.toString() ?? ''),
                        trailing: FilledButton(
                          onPressed: _applyBusy
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  _applyToGym(gym['id'].toString());
                                },
                          child: Text(context.tr('trainer.apply')),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _displayName {
    final user = (_me?['user'] as Map?) ?? AppScope.of(context).auth.user;
    return (user?['displayName'] ??
            user?['email'] ??
            user?['phone'] ??
            'Trainer')
        .toString();
  }

  Map<String, dynamic>? get _myProfile {
    final email = AppScope.of(context).auth.user?['email']?.toString();
    return _trainers.where((t) => t['email']?.toString() == email).firstOrNull;
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
      await _refreshMe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.profileUpdated'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trainer = _myProfile;
    final gyms = (trainer?['gyms'] as List?)?.whereType<Map>().toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('trainer.dashboard')),
        actions: const [ThemeToggleButton()],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            Text(
              context.tr('trainer.dashboardBody'),
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            FFCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(context.tr('trainer.profile')),
                  Text(
                    trainer?['displayName']?.toString() ?? _displayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (trainer?['specialties'] as List? ?? []).join(' / '),
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      FFPill(
                        label:
                            '${formatCurrency(trainer?['hourlyRateTzs'] as num? ?? 0, currency: trainer?['sessionRateCurrency'] as String? ?? 'TZS')}/hr',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FFMetricCard(
                    value: '${gyms.length}',
                    label: context.tr('trainer.gyms'),
                  ),
                ),
              ],
            ),
            _section(context.tr('trainer.sessions')),
            FFActionTile(
              icon: Icons.event_available,
              title: context.tr('trainer.todaySessions'),
              onTap: () {},
            ),
            FFActionTile(
              icon: Icons.payments,
              title: context.tr('trainer.earnings'),
              onTap: () {},
            ),
            FFActionTile(
              icon: Icons.edit,
              title: context.tr('trainer.editProfile'),
              onTap: _showEditProfileDialog,
            ),
            _section(context.tr('trainer.gyms')),
            if (gyms.isEmpty && _pendingGyms.isEmpty)
              FFEmptyState(title: context.tr('member.noData'))
            else ...[
              ...gyms.map(
                (g) => FFActionTile(
                  icon: Icons.fitness_center,
                  title: g['name']?.toString() ?? '',
                  subtitle: g['location']?.toString(),
                  onTap: () {},
                ),
              ),
              ..._pendingGyms.map(
                (g) => FFActionTile(
                  icon: Icons.hourglass_top,
                  title: g['name']?.toString() ?? '',
                  subtitle: context.tr('trainer.pendingApprovalAtGym'),
                  trailing: TextButton(
                    onPressed: _applyBusy
                        ? null
                        : () => _cancelApplication(g['id'].toString()),
                    child: Text(context.tr('trainer.cancel')),
                  ),
                  onTap: () {},
                ),
              ),
            ],
            const SizedBox(height: FFTokens.spacingSm),
            OutlinedButton.icon(
              onPressed: _applyBusy ? null : _showApplyGymSheet,
              icon: const Icon(Icons.add),
              label: Text(context.tr('trainer.applyToGym')),
            ),
            _section(context.tr('member.accountSettings')),
            FFActionTile(
              icon: Icons.help_outline,
              title: context.tr('member.help'),
              onTap: _openWhatsAppSupport,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: Icon(
                Icons.logout,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              label: Text(
                context.tr('home.signout'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );
}
