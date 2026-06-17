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
}
