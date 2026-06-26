import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import 'ff_card.dart';

class FFGymUnapprovedCard extends StatelessWidget {
  const FFGymUnapprovedCard({
    super.key,
    required this.onRefresh,
    this.checking = false,
  });

  final VoidCallback onRefresh;
  final bool checking;

  void _openWhatsAppSupport() {
    final uri = Uri.parse('https://wa.me/255786670499');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FFCard(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.pending_actions,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            context.tr('owner.pendingApproval'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('owner.notApprovedYet'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
              height: 1.4,
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('owner.gymPending'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
              height: 1.4,
            ),
          ),
          const SizedBox(height: FFTokens.spacingLg),
          FilledButton(
            onPressed: checking ? null : onRefresh,
            child: checking
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : Text(context.tr('owner.refreshStatus')),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          OutlinedButton(
            onPressed: _openWhatsAppSupport,
            child: Text(context.tr('owner.contactUs')),
          ),
        ],
      ),
    );
  }
}
