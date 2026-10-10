// A trainer's weekly payout statements. The page itself is shared with
// vendors (shared/widgets/partner_payouts_page.dart).

import 'package:flutter/material.dart';

import '../../shared/widgets/partner_payouts_page.dart';

class TrainerPayoutsPage extends StatelessWidget {
  const TrainerPayoutsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const PartnerPayoutsPage(kind: PayoutKind.trainer);
}
