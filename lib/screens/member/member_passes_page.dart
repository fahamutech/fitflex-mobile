import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import 'member_shell.dart';

class MemberPassesPage extends StatelessWidget {
  const MemberPassesPage({super.key});

  Future<void> _retry(BuildContext context, MemberData data) async {
    final api = AppScope.of(context).api;
    data.update((d) {
      d.passesLoaded = false;
      d.passes = [];
    });
    try {
      final res = await api.listSubscriptionTiers();
      data.update((d) {
        d.passes = res
            .whereType<Map<String, dynamic>>()
            .map(PassTier.fromJson)
            .toList();
        d.passesLoaded = true;
      });
    } catch (_) {
      try {
        final res = await api.listPasses();
        data.update((d) {
          d.passes = res
              .whereType<Map<String, dynamic>>()
              .map(PassTier.fromJson)
              .toList();
          d.passesLoaded = true;
        });
      } catch (_) {
        data.update((d) => d.passesLoaded = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => context.go(AppRoutes.memberHome),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                context.tr('member.choosePlan'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: FFTokens.fgPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Text(
            context.tr('member.planBody'),
            style: const TextStyle(color: FFTokens.fgQuaternary, fontSize: 14),
          ),
        ),
        const SizedBox(height: 16),
        if (!data.passesLoaded)
          const Center(child: CircularProgressIndicator())
        else if (data.passes.isEmpty)
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
                    onPressed: () => _retry(context, data),
                    child: Text(context.tr('home.retry')),
                  ),
                ],
              ),
            ),
          )
        else ...[
          ...data.passes.map(
            (p) => _SelectablePass(
              pass: p,
              selected: p.id == data.selectedTier,
              onTap: () => data.update((d) => d.selectedTier = p.id),
            ),
          ),
          const SizedBox(height: 12),
          FFAlert(message: context.tr('pass.note'), tone: FFAlertTone.info),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go(AppRoutes.memberPayment),
            child: Text(context.tr('member.continuePayment')),
          ),
        ],
      ],
    );
  }
}

class _SelectablePass extends StatelessWidget {
  const _SelectablePass({
    required this.pass,
    required this.selected,
    required this.onTap,
  });

  final PassTier pass;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          decoration: BoxDecoration(
            color: selected ? FFTokens.brand50 : FFTokens.bgPrimary,
            border: Border.all(
              color: selected ? FFTokens.brand500 : FFTokens.borderSecondary,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(FFTokens.radiusXl),
            boxShadow: selected ? FFTokens.shadowXs : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('pass.${pass.id}'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: FFTokens.fgPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pass.visitCap == null
                          ? context.tr('pass.unlimited')
                          : '${pass.visitCap} ${context.tr('pass.visits')}',
                      style: const TextStyle(
                        color: FFTokens.fgQuaternary,
                        fontSize: 12,
                      ),
                    ),
                    if (pass.gymAccess != null && pass.gymAccess!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          pass.gymAccessLabel,
                          style: const TextStyle(
                            color: FFTokens.brand600,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                'TZS ${pass.price}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: FFTokens.fgPrimary,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle,
                  color: FFTokens.brand500,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
