import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/components/theme_toggle_button.dart';
import '../shared/i18n.dart';
import '../shared/design_tokens.dart';
import '../app_scope.dart';

/// Compile-time flag: enables a dev-only mock-login panel for blackbox testing.
/// Build with `--dart-define=MOCK_AUTH=true`. Never enabled in store builds.
const bool kMockAuth = bool.fromEnvironment('MOCK_AUTH');

class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key});

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedRole;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: FFTokens.motionSlow,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _select(String role) {
    setState(() => _selectedRole = role);
  }

  Future<void> _continue() async {
    if (_selectedRole == null) return;
    final auth = AppScope.of(context).auth;
    await auth.setRole(_selectedRole!);
    if (!mounted) return;
    context.go(AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.language),
        ),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FFTokens.spacingLg,
                      vertical: FFTokens.spacingMd,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.tr('role.welcomeTitle'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        Text(
                          context.tr('role.welcomeSubtitle'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: FFTokens.spacingXl),
                        _RoleRadioTile(
                          icon: Icons.person_outline_rounded,
                          iconColor: FFTokens.iconAccentGreen,
                          label: context.tr('role.member'),
                          description: context.tr('role.memberBody'),
                          selected: _selectedRole == 'member',
                          onTap: () => _select('member'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _RoleRadioTile(
                          icon: Icons.fitness_center_rounded,
                          iconColor: FFTokens.accentOrange,
                          label: context.tr('role.owner'),
                          description: context.tr('role.ownerBody'),
                          selected: _selectedRole == 'gym_owner',
                          onTap: () => _select('gym_owner'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _RoleRadioTile(
                          icon: Icons.people_outline_rounded,
                          iconColor: FFTokens.iconAccentGreen,
                          label: context.tr('role.trainer'),
                          description: context.tr('role.trainerBody'),
                          selected: _selectedRole == 'trainer',
                          onTap: () => _select('trainer'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _RoleRadioTile(
                          icon: Icons.storefront_outlined,
                          iconColor: FFTokens.accentIndigo,
                          label: context.tr('role.vendor'),
                          description: context.tr('role.vendorBody'),
                          selected: _selectedRole == 'vendor',
                          onTap: () => _select('vendor'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _RoleRadioTile(
                          icon: Icons.badge_outlined,
                          iconColor: FFTokens.accentOrange,
                          label: context.tr('role.staff'),
                          description: context.tr('role.staffBody'),
                          selected: _selectedRole == 'gym_staff',
                          onTap: () => _select('gym_staff'),
                        ),
                        if (kMockAuth) ...[
                          const SizedBox(height: FFTokens.spacingXl),
                          const _DevLoginPanel(),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selectedRole != null ? _continue : null,
                      child: Text(context.tr('lang.continue')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleRadioTile extends StatelessWidget {
  const _RoleRadioTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: FFTokens.motionMedium,
        curve: FFTokens.motionCurve,
        padding: const EdgeInsets.symmetric(
          horizontal: FFTokens.spacingLg,
          vertical: FFTokens.spacingMd,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 28,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : iconColor,
            ),
            const SizedBox(width: FFTokens.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: FFTokens.spacingXs),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: FFTokens.spacingMd),
            _RadioDot(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).colorScheme.outline;
    return Container(
      width: FFTokens.spacingLg,
      height: FFTokens.spacingLg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? primary : null,
        border: Border.all(color: selected ? primary : muted, width: 2),
      ),
      child: selected
          ? Center(
              child: CircleAvatar(
                radius: 5,
                backgroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : null,
    );
  }
}

/// Dev-only panel that mints a mock session via the backend's /auth/dev/login.
class _DevLoginPanel extends StatefulWidget {
  const _DevLoginPanel();

  @override
  State<_DevLoginPanel> createState() => _DevLoginPanelState();
}

class _DevLoginPanelState extends State<_DevLoginPanel> {
  bool _busy = false;
  String? _error;

  Future<void> _login(String role) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = AppScope.of(context).auth;
    try {
      final res = await AppScope.of(context).api.devLogin(role);
      final user = Map<String, dynamic>.from(res['user'] as Map);
      await auth.setRole(user['userType']?.toString() ?? role);
      await auth.signIn(res['token'] as String, user);
      if (!mounted) return;
      context.go(routeForSignedInUser(auth));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = 'Dev login failed (${e.status})');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.bug_report,
                size: FFTokens.iconSm,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Text(
                'DEV: Mock login',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('devLoginMember'),
                  onPressed: () => _login('member'),
                  child: const Text('Member'),
                ),
                OutlinedButton(
                  key: const Key('devLoginOwner'),
                  onPressed: () => _login('owner'),
                  child: const Text('Gym Owner'),
                ),
                OutlinedButton(
                  key: const Key('devLoginTrainer'),
                  onPressed: () => _login('trainer'),
                  child: const Text('Trainer'),
                ),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              _error!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
