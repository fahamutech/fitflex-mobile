import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Marketplace requirements: buyer browse through paid order history',
    config: patrolConfig,
    marketplaceBuyerJourney,
  );
}
