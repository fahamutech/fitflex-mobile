// Patrol E2E: vendor login, product inventory, and order management shell.

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Issues 41 and 56: vendor marketplace lifecycle',
    config: patrolConfig,
    vendorMarketplaceJourney,
  );
}
