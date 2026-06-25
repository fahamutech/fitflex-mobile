import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

class MemberShopTab extends StatelessWidget {
  const MemberShopTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(FFTokens.radiusXl),
            ),
            child: Icon(
              Icons.storefront_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          context.tr('member.shopTitle'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('member.shopBody'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodySmall?.color,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: FFBadge(
            label: context.tr('member.marketplaceSoon'),
            tone: FFBadgeTone.brand,
          ),
        ),
        const SizedBox(height: 32),
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('member.shopUpcoming'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: Icons.shopping_bag_outlined,
                text: context.tr('member.shopFeature1'),
              ),
              const SizedBox(height: 10),
              _FeatureRow(
                icon: Icons.local_offer_outlined,
                text: context.tr('member.shopFeature2'),
              ),
              const SizedBox(height: 10),
              _FeatureRow(
                icon: Icons.card_giftcard_outlined,
                text: context.tr('member.shopFeature3'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
