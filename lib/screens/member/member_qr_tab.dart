import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/checkin_list.dart';

class MemberQrTab extends StatelessWidget {
  const MemberQrTab({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        if (data.pendingPayment != null) _PendingPaymentCard(data: data),
        if (data.hasActivePass)
          _QrCard(data: data)
        else
          _QrLockedCard(data: data),
        const SizedBox(height: 12),

        // // Scan gym QR
        // FFCard(
        //   child: Column(
        //     crossAxisAlignment: CrossAxisAlignment.start,
        //     children: [
        //       Text(
        //         context.tr('member.scanGymQr'),
        //         style: const TextStyle(
        //           fontSize: 16,
        //           fontWeight: FontWeight.w600,
        //           color: FFTokens.fgPrimary,
        //         ),
        //       ),
        //       const SizedBox(height: 4),
        //       Text(
        //         context.tr('home.qr'),
        //         style: const TextStyle(
        //           color: FFTokens.fgQuaternary,
        //           fontSize: 14,
        //         ),
        //       ),
        //       const SizedBox(height: 10),
        //       FilledButton.icon(
        //         onPressed: () {
        //           ScaffoldMessenger.of(context).showSnackBar(
        //             SnackBar(content: Text(context.tr('member.scanGymQr'))),
        //           );
        //         },
        //         icon: const Icon(Icons.camera_alt, size: 18),
        //         label: Text(context.tr('member.scanGymQr')),
        //       ),
        //     ],
        //   ),
        // ),

        // Recent checkins
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 10),
          child: Text(
            context.tr('member.recentCheckins'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
            ),
          ),
        ),
        CheckinList(checkins: data.checkins, limit: 5),
      ],
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    return FFCard(
      child: Column(
        children: [
          Text(
            context.tr('home.qr'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (data.qrToken != null)
            QrImageView(
              data: data.qrToken!,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: FFTokens.brand700,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: FFTokens.brand700,
              ),
            )
          else
            const SizedBox(
              height: 220,
              child: Center(child: FFSpinner(size: 32)),
            ),
          const SizedBox(height: 8),
          Text(
            context.tr('home.qr.refreshes'),
            style: const TextStyle(color: FFTokens.fgQuaternary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _QrLockedCard extends StatelessWidget {
  const _QrLockedCard({required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    final isPending = data.pendingPayment != null;
    final title = isPending
        ? context.tr('home.qr.pendingTitle')
        : context.tr('home.qr.lockedTitle');
    final body = isPending
        ? context.tr('home.qr.pendingBody')
        : context.tr('home.qr.lockedBody');

    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FFTokens.bgSecondary,
                  border: Border.all(color: FFTokens.borderSecondary),
                  borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                ),
                child: const Icon(
                  Icons.qr_code_2,
                  color: FFTokens.brand700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: FFTokens.fgPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        color: FFTokens.fgQuaternary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isPending) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.go(AppRoutes.memberPasses),
                icon: const Icon(Icons.card_membership, size: 18),
                label: Text(context.tr('member.subscribe')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingPaymentCard extends StatelessWidget {
  const _PendingPaymentCard({required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    final pending = data.pendingPayment!;
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FFBadge(
            label: context.tr('pass.pending'),
            tone: FFBadgeTone.warning,
            dot: true,
          ),
          const SizedBox(height: 8),
          Text(
            '${pending.tier.toUpperCase()} - TZS ${pending.amountTzs}',
            style: const TextStyle(color: FFTokens.fgQuaternary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
