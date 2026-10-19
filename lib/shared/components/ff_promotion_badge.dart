import 'package:flutter/material.dart';

import '../i18n.dart';
import '../promotion.dart';
import 'ff_badge.dart';

/// The label on a promoted listing: Featured, Promoted, Sponsored or
/// "Recommended by FitFlex". Shown on every promoted card so a paid placement
/// is never mistaken for an organic result. A custom label chosen by FitFlex
/// is shown as it is; the standard ones are translated.
class FFPromotionBadge extends StatelessWidget {
  const FFPromotionBadge({super.key, required this.tag});

  final PromotionTag tag;

  static const _standard = {
    'featured': 'Featured',
    'promoted': 'Promoted',
    'sponsored': 'Sponsored',
    'recommended': 'Recommended by FitFlex',
    'campaign': 'Campaign',
  };

  FFBadgeTone get tone => switch (tag.type) {
    'sponsored' => FFBadgeTone.warning,
    'recommended' => FFBadgeTone.success,
    'featured' => FFBadgeTone.brand,
    _ => FFBadgeTone.defaultTone,
  };

  String text(BuildContext context) {
    final standard = _standard[tag.type];
    if (tag.label.isNotEmpty && tag.label != standard) return tag.label;
    return context.tr('promo.${tag.type}');
  }

  @override
  Widget build(BuildContext context) => FFBadge(
    key: Key('promo-badge-${tag.type}'),
    label: text(context),
    tone: tone,
  );
}
