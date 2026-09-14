import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Member enquiry appears in trainer inbox',
    config: patrolConfig,
    memberTrainerEnquiryJourney,
  );
}
