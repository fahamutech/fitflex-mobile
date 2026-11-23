import 'package:fitflexmobile/screens/owner/owner_qr_scanner_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server gym selection requirement is shown even before gyms load', () {
    expect(
      ownerScanNeedsGymSelection(
        verifyResult: {'requiresGymSelection': true},
        gyms: const [],
        selectedGymId: null,
      ),
      true,
    );
  });

  test('selected gym satisfies gym selection requirement', () {
    expect(
      ownerScanNeedsGymSelection(
        verifyResult: {'requiresGymSelection': true},
        gyms: const [
          {'id': 'gym-1', 'name': 'Gym 1'},
        ],
        selectedGymId: 'gym-1',
      ),
      false,
    );
  });

  test('multiple owner gyms require selection when no gym is selected', () {
    expect(
      ownerScanNeedsGymSelection(
        verifyResult: {'requiresGymSelection': false},
        gyms: const [
          {'id': 'gym-1', 'name': 'Gym 1'},
          {'id': 'gym-2', 'name': 'Gym 2'},
        ],
        selectedGymId: null,
      ),
      true,
    );
  });

  group('custom pass at the door', () {
    test(
      'the pass comes from the verify answer; absent, null or malformed means no pass',
      () {
        expect(
          ownerScanPass({
            'pass': {'name': 'Pair Pass', 'category': 'couples'},
          })?['name'],
          'Pair Pass',
        );
        expect(ownerScanPass({'pass': null}), isNull);
        expect(ownerScanPass({'eligible': true}), isNull);
        expect(ownerScanPass({'pass': 'x'}), isNull);
        expect(ownerScanPass(null), isNull);
      },
    );

    test('an unnamed pass falls back to the generic label', () {
      expect(ownerScanPassName({'name': 'Pair Pass'}, 'Gym pass'), 'Pair Pass');
      expect(ownerScanPassName({'name': null}, 'Gym pass'), 'Gym pass');
      expect(ownerScanPassName({'name': '  '}, 'Gym pass'), 'Gym pass');
      expect(ownerScanPassName({}, 'Gym pass'), 'Gym pass');
    });
  });
}
