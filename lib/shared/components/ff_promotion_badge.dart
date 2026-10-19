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

  /// The disclosure in the customer's language. Order of preference:
  /// the server's disclosure codes as the app's own words (always the right
  /// language); the server's disclosure text for this language; then the
  /// older single label (in Swahili never the English text).
  String text(BuildContext context) {
    final standard = _standard[tag.type];
    final lang = FFLocaleScope.of(context).locale.languageCode;
    if (tag.disclosureCodes.isNotEmpty &&
        tag.disclosureCodes.every(_standard.containsKey)) {
      return tag.disclosureCodes
          .map((code) => context.tr('promo.$code'))
          .join(' · ');
    }
    final server = lang == 'sw' ? tag.disclosureSw : tag.disclosureEn;
    if (server.isNotEmpty) return server;
    // A custom label from the server is English-only today: in Swahili the
    // translated standard label is used instead, never the English text.
    if (lang == 'en' && tag.label.isNotEmpty && tag.label != standard) {
      return tag.label;
    }
    final own = context.tr('promo.${tag.type}');
    final base = own == 'promo.${tag.type}'
        ? context.tr('promo.featured')
        : own;
    // The dropped custom label may have carried the paid disclosure
    // ("Featured · Sponsored"): keep it for commercial placements.
    if (lang != 'en' && tag.commercial && tag.type != 'sponsored') {
      return '$base · ${context.tr('promo.sponsored')}';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) => FFBadge(
    key: Key('promo-badge-${tag.type}'),
    label: text(context),
    tone: tone,
    // A disclosure is never cut off, at any text size (spec §10.8).
    wrap: true,
  );
}
