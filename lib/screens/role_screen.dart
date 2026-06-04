import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/i18n.dart';
import '../shared/design_tokens.dart';
import '../shared/auth_state.dart';
import '../app_scope.dart';

/// Compile-time flag: enables a dev-only mock-login panel for blackbox testing.
/// Build with `--dart-define=MOCK_AUTH=true`. Never enabled in store builds.
const bool kMockAuth = bool.fromEnvironment('MOCK_AUTH');

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  Future<void> _pick(BuildContext context, AuthState auth, String role) async {
    await auth.setRole(role);
    if (!context.mounted) return;
    context.go(AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('role.choose'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              _RoleTile(
                label: context.tr('role.member'),
                body: context.tr('role.memberBody'),
                icon: Icons.fitness_center,
                onTap: () => _pick(context, auth, 'member'),
              ),
              const SizedBox(height: 12),
              _RoleTile(
                label: context.tr('role.owner'),
                body: context.tr('role.ownerBody'),
                icon: Icons.storefront,
                onTap: () => _pick(context, auth, 'gym_owner'),
              ),
              const SizedBox(height: 12),
              _RoleTile(
                label: context.tr('role.trainer'),
                body: context.tr('role.trainerBody'),
                icon: Icons.sports_gymnastics,
                onTap: () => _pick(context, auth, 'trainer'),
              ),
              if (kMockAuth) const _DevLoginPanel(),
            ],
          ),
        ),
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
      if (mounted) setState(() => _error = 'Dev login failed (${e.status})');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Container(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        decoration: BoxDecoration(
          color: FFTokens.surface,
          border: Border.all(color: FFTokens.border),
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.bug_report, size: 18, color: FFTokens.textMuted),
                SizedBox(width: 8),
                Text(
                  'DEV: Mock login',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: FFTokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: FFTokens.danger, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.label,
    required this.body,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final String body;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        decoration: BoxDecoration(
          color: FFTokens.surface,
          border: Border.all(color: FFTokens.border),
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        ),
        child: Row(
          children: [
            Icon(icon, color: FFTokens.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      color: FFTokens.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: FFTokens.textMuted),
          ],
        ),
      ),
    );
  }
}
