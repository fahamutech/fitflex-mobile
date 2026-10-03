import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';

/// Shown to a trainer or gym owner whose own verification is not approved
/// yet. Their profile is active; this says what waits for verification and
/// where to submit their details. Hidden once verified, and for other roles.
class PartnerNotVerifiedNotice extends StatelessWidget {
  const PartnerNotVerifiedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.partnerVerified != false) return const SizedBox.shrink();
        final isTrainer = auth.user?['userType'] == 'trainer';
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: FFCard(
            key: const Key('partner-not-verified'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.gpp_maybe_outlined,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('unverified.title'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr(
                    isTrainer
                        ? 'unverified.trainerBody'
                        : 'unverified.ownerBody',
                  ),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FilledButton(
                  key: const Key('partner-not-verified-cta'),
                  onPressed: () => context.push(AppRoutes.verification),
                  child: Text(context.tr('kyc.pending.cta')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Small "Not verified" label for a trainer or gym in a list.
class NotVerifiedLabel extends StatelessWidget {
  const NotVerifiedLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      context.tr('gym.unverified'),
      maxLines: 1,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.textTheme.bodySmall?.color,
      ),
    );
  }
}
