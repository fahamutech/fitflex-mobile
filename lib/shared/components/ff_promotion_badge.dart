import 'package:flutter/material.dart';

import '../i18n.dart';
import '../promotion.dart';
import 'ff_badge.dart';

/// The disclosure on a promoted listing (Featured, Promoted, Sponsored,
/// "Recommended by FitFlex", Campaign, or a combination such as
/// "Featured · Sponsored"), shown on every promoted card so a paid placement
/// is never mistaken for an organic result.
///
/// English: the server's `disclosure.en` wording when present (so an
/// admin's own wording, e.g. "Top pick · Sponsored", is kept), else the
/// disclosure codes in the app's words, else the older single label.
/// Swahili: the codes in the app's own words, else `disclosure.sw`, else the
/// standard label for the type; never English text. A paid placement always
/// ends with the Sponsored word ("Sponsored" / "Iliyodhaminiwa").
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

  /// The disclosure in the customer's language (see the class comment).
  String text(BuildContext context) {
    final standard = _standard[tag.type];
    final english = FFLocaleScope.of(context).locale.languageCode == 'en';
    final sponsored = context.tr('promo.sponsored');
    final paid =
        tag.commercial ||
        tag.type == 'sponsored' ||
        tag.disclosureCodes.contains('sponsored');
    final codesKnown =
        tag.disclosureCodes.isNotEmpty &&
        tag.disclosureCodes.every(_standard.containsKey);
    String fromCodes() => [
      // "sponsored" last, so the paid word ends the line.
      for (final code in tag.disclosureCodes)
        if (code != 'sponsored') context.tr('promo.$code'),
      if (tag.disclosureCodes.contains('sponsored')) sponsored,
    ].join(' · ');

    String text;
    if (english && tag.disclosureEn.isNotEmpty) {
      text = tag.disclosureEn;
    } else if (codesKnown) {
      text = fromCodes();
    } else if (!english && tag.disclosureSw.isNotEmpty) {
      text = tag.disclosureSw;
    } else if (english && tag.label.isNotEmpty && tag.label != standard) {
      // An older server's custom label (English only).
      text = tag.label;
    } else {
      final own = context.tr('promo.${tag.type}');
      text = own == 'promo.${tag.type}' ? context.tr('promo.featured') : own;
    }
    if (paid && !text.trimRight().endsWith(sponsored)) {
      text = '$text · $sponsored';
    }
    return text;
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
