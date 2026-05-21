import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.memberHome),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('member.choosePlan')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.tr('member.planBody'),
                style: const TextStyle(
                  color: FFTokens.fgQuaternary,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          const SizedBox(height: 4),
          if (data.pendingPayment != null)
            _PendingBlockCard(pending: data.pendingPayment!)
          else if (!data.passesLoaded)
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
      ),
    );
  }
}

class _PendingBlockCard extends StatelessWidget {
  const _PendingBlockCard({required this.pending});

  final PaymentRequest pending;

  void _openSupport() {
    launchUrl(
      Uri.parse('https://wa.me/255786670499'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FFTokens.warning50,
                  border: Border.all(color: FFTokens.warning200),
                  borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: FFTokens.warning700,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('member.paymentPendingTitle'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: FFTokens.fgPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FFBadge(
                      label: context.tr('member.waitingApproval'),
                      tone: FFBadgeTone.warning,
                      dot: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('member.paymentPendingBody'),
            style: const TextStyle(
              color: FFTokens.fgQuaternary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          _DetailRow(
            label: context.tr('member.paymentPendingPlan'),
            value: pending.tier.toUpperCase(),
          ),
          _DetailRow(
            label: context.tr('member.paymentPendingAmount'),
            value: 'TZS ${pending.amountTzs}',
          ),
          _DetailRow(
            label: context.tr('member.paymentPendingStatus'),
            value: context.tr('member.paymentPendingStatusValue'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openSupport,
              icon: const Icon(Icons.support_agent, size: 18),
              label: Text(context.tr('member.contactSupport')),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: FFTokens.fgQuaternary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
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
