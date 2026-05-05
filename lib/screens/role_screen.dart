import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router.dart';
import '../shared/i18n.dart';
import '../shared/design_tokens.dart';
import '../shared/auth_state.dart';
import '../app_scope.dart';

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
            ],
          ),
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
