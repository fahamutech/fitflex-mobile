import 'package:flutter/material.dart';

import '../i18n.dart';
import '../promotion.dart';
import 'ff_badge.dart';

/// The label on a promoted listing: Featured, Promoted, Sponsored or
/// "Recommended by FitFlex", plus "Sponsored" when the placement was paid
/// for. Shown on every promoted card so a paid placement is never mistaken
/// for an organic result.
///
/// In English a custom label chosen by FitFlex is shown as it is. In Swahili
/// the words always come from the app's `promo.*` strings, because the server
/// label is English free text.
class FFPromotionBadge extends StatelessWidget {
  const FFPromotionBadge({super.key, required this.tag});

  final PromotionTag tag;

  static const _codes = {
    'featured',
    'promoted',
    'sponsored',
    'recommended',
    'campaign',
  };

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

  /// The kinds to name, in order. From the server when it sends them;
  /// otherwise (older servers) the type, then Sponsored if it was paid for.
  List<String> get _kinds {
    final fromServer = tag.disclosure?.codes ?? const <String>[];
    if (fromServer.isNotEmpty) return fromServer;
    return [
      tag.type,
      if (tag.commercial && tag.type != 'sponsored') 'sponsored',
    ];
  }

  String text(BuildContext context) {
    final english = FFLocaleScope.of(context).locale.languageCode != 'sw';
    final d = tag.disclosure;
    if (english) {
      if (d != null && d.en.isNotEmpty) return d.en;
      final standard = _standard[tag.type];
      if (tag.label.isNotEmpty && tag.label != standard) return tag.label;
      return context.tr('promo.${tag.type}');
    }
    final kinds = _kinds;
    if (kinds.every(_codes.contains)) {
      return kinds.map((k) => context.tr('promo.$k')).join(' · ');
    }
    if (d != null && d.sw.isNotEmpty) return d.sw;
    return context.tr('promo.${tag.type}');
  }

  @override
  Widget build(BuildContext context) => FFBadge(
    key: Key('promo-badge-${tag.type}'),
    label: text(context),
    tone: tone,
  );
}
