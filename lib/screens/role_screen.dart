import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/api_error_message.dart';
import '../shared/i18n.dart';
import '../shared/design_tokens.dart';
import '../app_scope.dart';
import '../shared/components/components.dart';

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
    context.push(AppRoutes.signUp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.auth),
        ),
        actions: const [AppPrefsButtons()],
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
                        _RoleTile(
                          icon: Icons.person_outline_rounded,
                          iconColor: Theme.of(context).colorScheme.primary,
                          label: context.tr('role.member'),
                          description: context.tr('role.memberBody'),
                          selected: _selectedRole == 'member',
                          onTap: () => _select('member'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _RoleTile(
                          icon: Icons.fitness_center_rounded,
                          iconColor: FFTokens.accentOrange,
                          label: context.tr('role.owner'),
                          description: context.tr('role.ownerBody'),
                          selected: _selectedRole == 'gym_owner',
                          onTap: () => _select('gym_owner'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _RoleTile(
                          icon: Icons.people_outline_rounded,
                          iconColor: Theme.of(context).colorScheme.primary,
                          label: context.tr('role.trainer'),
                          description: context.tr('role.trainerBody'),
                          selected: _selectedRole == 'trainer',
                          onTap: () => _select('trainer'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _RoleTile(
                          icon: Icons.storefront_outlined,
                          iconColor: FFTokens.accentIndigo,
                          label: context.tr('role.vendor'),
                          description: context.tr('role.vendorBody'),
                          selected: _selectedRole == 'vendor',
                          onTap: () => _select('vendor'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _RoleTile(
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
                    child: FFButton(
                      label: context.tr('lang.continue'),
                      onPressed: _selectedRole != null ? _continue : null,
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

/// An account-type option: the shared radio tile with the role's icon.
class _RoleTile extends StatelessWidget {
  const _RoleTile({
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
    return FFChoiceTile(
      title: label,
      subtitle: description,
      selected: selected,
      onSelected: onTap,
      leading: Icon(
        icon,
        size: 28,
        color: selected ? Theme.of(context).colorScheme.primary : iconColor,
      ),
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
      if (mounted) {
        setState(() => _error = apiErrorMessage(FFLocaleScope.of(context), e));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessage(FFLocaleScope.of(context), e));
      }
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
            const Center(child: FFSpinner(size: 32))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FFButton(
                  key: const Key('devLoginMember'),
                  label: 'Member',
                  onPressed: () => _login('member'),
                  variant: FFButtonVariant.secondary,
                ),
                FFButton(
                  key: const Key('devLoginOwner'),
                  label: 'Gym Owner',
                  onPressed: () => _login('owner'),
                  variant: FFButtonVariant.secondary,
                ),
                FFButton(
                  key: const Key('devLoginTrainer'),
                  label: 'Trainer',
                  onPressed: () => _login('trainer'),
                  variant: FFButtonVariant.secondary,
                ),
                FFButton(
                  key: const Key('devLoginVendor'),
                  label: 'Vendor',
                  onPressed: () => _login('vendor'),
                  variant: FFButtonVariant.secondary,
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
