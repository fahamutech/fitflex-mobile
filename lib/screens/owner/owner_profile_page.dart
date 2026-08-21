import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/profile_form_page.dart';
import '../language_screen.dart';
import 'owner_shell.dart';

/// Owner — profile view with account settings and sign-out.
/// B9: this route lives OUTSIDE the owner shell, so [OwnerDataScope] is
/// usually unavailable — the page loads its own gym/trainer counts.
class OwnerProfilePage extends StatefulWidget {
  const OwnerProfilePage({super.key});

  @override
  State<OwnerProfilePage> createState() => _OwnerProfilePageState();
}

class _OwnerProfilePageState extends State<OwnerProfilePage> {
  int? _gymCount;
  int? _trainerCount;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final api = AppScope.of(context).api;
    try {
      final gyms = await api.ownerGyms();
      if (mounted) setState(() => _gymCount = gyms.length);
    } catch (_) {}
    if (!mounted) return;
    try {
      final trainers = await api.ownerTrainers();
      if (mounted) setState(() => _trainerCount = trainers.length);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ownerData = context
        .dependOnInheritedWidgetOfExactType<OwnerDataScope>()
        ?.notifier;
    final appAuth = AppScope.of(context).auth;
    final user = (ownerData?.me?['user'] as Map?) ?? appAuth.user ?? {};
    final displayName =
        ownerData?.displayName ??
        (user['displayName'] ?? user['email'] ?? user['phone'] ?? 'Owner')
            .toString();
    final email = user['email']?.toString() ?? '';
    final phone = user['phone']?.toString() ?? '';
    // Prefer live scope data when inside the shell; fall back to the counts
    // this page fetched itself (B9 — profile showed 0 gyms / 0 trainers).
    final gymCount = ownerData?.ownerGyms.isNotEmpty == true
        ? ownerData!.ownerGyms.length
        : (_gymCount ?? ownerData?.ownerGyms.length ?? 0);
    final trainerCount = ownerData?.ownerTrainers.isNotEmpty == true
        ? ownerData!.ownerTrainers.length
        : (_trainerCount ?? ownerData?.ownerTrainers.length ?? 0);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/owner/home');
            }
          },
        ),
        title: Text(context.tr('member.profile')),
        actions: const [ThemeToggleButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFCard(
            child: Row(
              children: [
                const CircleAvatar(radius: 30, child: Icon(Icons.person)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email.isNotEmpty ? email : phone,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          height: 1.35,
                        ),
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
              Expanded(
                child: FFMetricCard(
                  label: context.tr('owner.myGyms'),
                  value: '$gymCount',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FFMetricCard(
                  label: context.tr('owner.trainers'),
                  value: '$trainerCount',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              context.tr('member.accountSettings'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          FFActionTile(
            icon: Icons.edit,
            title: context.tr('member.editDetails'),
            onTap: () => _showEditProfileDialog(context),
          ),
          if (ownerData?.isStaff != true)
            FFActionTile(
              icon: Icons.badge_outlined,
              title: context.tr('staff.title'),
              onTap: () => context.push('/owner/staff'),
            ),
          FFActionTile(
            icon: Icons.help_outline,
            title: context.tr('member.help'),
            onTap: _openWhatsAppSupport,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('owner-sign-out'),
            onPressed: () => _signOut(context),
            icon: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            label: Text(
              context.tr('home.signout'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  void _openWhatsAppSupport() {
    final uri = Uri.parse('https://wa.me/255786670499');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showEditProfileDialog(BuildContext context) async {
    final ownerData = context
        .dependOnInheritedWidgetOfExactType<OwnerDataScope>()
        ?.notifier;
    final user = Map<String, dynamic>.from(
      (ownerData?.me?['user'] as Map?) ??
          AppScope.of(context).auth.user ??
          const {},
    );
    final saved = await openProfileForm(
      context,
      title: context.tr('member.editDetails'),
      initialUser: user,
      onSignOut: () => _signOut(context),
    );
    if (saved == true) {
      if (!context.mounted) return;
      final message = context.tr('member.profileUpdated');
      final shell = context.findAncestorStateOfType<OwnerShellState>();
      await shell?.refreshAll();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _signOut(BuildContext context) async {
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
            key: const Key('owner-confirm-sign-out'),
            style: FilledButton.styleFrom(backgroundColor: FFTokens.error500),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('home.signout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await AppScope.of(context).auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LanguageScreen()),
      (_) => false,
    );
  }
}
