// "Payout owner" marker on a gym of a gym owner (fitflex-functions#247).
//
// GET /owner/gyms adds `isPayoutOwner: boolean` per gym while the server
// flag GYM_PAYOUT_OWNER is on. The marker shows only when it is `true`;
// `false` or absent (flag off, older server) shows nothing. The owner view
// never carries a co-owner's id, so the app cannot (and does not) name who
// else is paid.

import 'package:flutter/material.dart';

import '../components/components.dart';
import '../i18n.dart';

/// Whether the signed-in owner is the one FitFlex pays for [gym].
bool isPayoutOwnerGym(Map<String, dynamic>? gym) =>
    gym?['isPayoutOwner'] == true;

/// A small badge saying the signed-in owner receives this gym's payouts.
class PayoutOwnerMarker extends StatelessWidget {
  const PayoutOwnerMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.tr('owner.payoutOwner.a11y'),
      excludeSemantics: true,
      child: FFBadge(
        label: context.tr('owner.payoutOwner'),
        tone: FFBadgeTone.brand,
      ),
    );
  }
}
