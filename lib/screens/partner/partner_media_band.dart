import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../owner/owner_home_tab.dart' show ownerHomeBandMaxHeight;
import '../trainer/trainer_home_page.dart' show trainerHomeBandMaxHeight;
import '../vendor/vendor_home_page.dart' show vendorHomeBandMaxHeight;

/// The role's real home band (spec §25, §41.2 preview card, §42.2 sheet
/// previews) with [ownPhoto] and [logo], its buttons drawn but inert: left
/// out of semantics and focus, and not tappable. Read as one node, [label].
class PartnerBandPreview extends StatelessWidget {
  const PartnerBandPreview({
    super.key,
    required this.side,
    required this.label,
    this.name,
    this.ownPhoto,
    this.logo,
    this.forceSize,
  });

  /// `gym`, `trainer` or `vendor`.
  final String side;
  final String label;

  /// Owner and trainer: the person's name (greeting); vendor: the business.
  final String? name;
  final FFHeroOwnPhoto? ownPhoto;
  final Widget? logo;

  /// Draws the band as on a screen this size (the sheet's phone preview at
  /// any window width, and its wide preview); null: this window.
  final Size? forceSize;

  @override
  Widget build(BuildContext context) {
    void inert() {}
    final band = switch (side) {
      'gym' => FFHeroBand(
        photo: FFHeroPhoto.owner,
        ownPhoto: ownPhoto,
        logo: logo,
        clearPhoto: FFTokens.heroBandClearPhoto,
        maxHeightAt844: ownerHomeBandMaxHeight,
        eyebrow: heroGreeting(context, DateTime.now(), name),
        headlineLead: context.tr('hero.owner.lead'),
        headlineAccent: context.tr('hero.owner.accent'),
        actions: [
          FFButton(
            icon: Icons.qr_code_scanner,
            label: context.tr('owner.checkin'),
            onPressed: inert,
          ),
        ],
      ),
      'trainer' => FFHeroBand(
        photo: FFHeroPhoto.trainer,
        ownPhoto: ownPhoto,
        logo: logo,
        clearPhoto: FFTokens.heroBandClearPhoto,
        maxHeightAt844: trainerHomeBandMaxHeight,
        eyebrow: heroGreeting(context, DateTime.now(), name),
        headlineLead: context.tr('hero.trainer.lead'),
        headlineAccent: context.tr('hero.trainer.accent'),
        subline: context.tr('checkin.body'),
        actions: [
          FFButton(
            label: context.tr('checkin.scan'),
            icon: Icons.qr_code_scanner,
            onPressed: inert,
          ),
          FFButton(
            label: context.tr('checkin.showQr'),
            icon: Icons.qr_code_2,
            variant: FFButtonVariant.onPhoto,
            onPressed: inert,
          ),
        ],
      ),
      _ => FFHeroBand(
        photo: FFHeroPhoto.vendor,
        ownPhoto: ownPhoto,
        logo: logo,
        clearPhoto: FFTokens.heroBandClearPhoto,
        maxHeightAt844: vendorHomeBandMaxHeight,
        eyebrow: (name ?? '').trim().isEmpty
            ? context.tr('vendor.title')
            : name!.trim(),
        headlineLead: context.tr('hero.vendor.lead'),
        headlineAccent: context.tr('hero.vendor.accent'),
        actions: [
          FFButton(
            label: context.tr('vendor.addProduct'),
            icon: Icons.add,
            onPressed: inert,
          ),
        ],
      ),
    };
    Widget out = band;
    final size = forceSize;
    if (size != null) {
      out = MediaQuery(
        data: MediaQuery.of(context).copyWith(size: size),
        child: band,
      );
    }
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: ExcludeFocus(child: IgnorePointer(child: out)),
    );
  }
}
