// The owner's entrance QR holds the web link when the server sends one, so a
// phone camera opens the gym's page; otherwise the signed app code as before.

import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/owner/owner_manage_gyms_page.dart';

void main() {
  const payload = 'fitflex:gym:g1:sig';
  const webUrl = 'https://portal.example/g/?q=fitflex%3Agym%3Ag1%3Asig';

  test('the web link is drawn when the server sends one', () {
    expect(gymEntranceQrData({'payload': payload, 'webUrl': webUrl}), webUrl);
  });

  test('the app code is drawn when there is no web link', () {
    expect(gymEntranceQrData({'payload': payload}), payload);
    expect(gymEntranceQrData({'payload': payload, 'webUrl': ''}), payload);
    expect(gymEntranceQrData({'payload': payload, 'webUrl': null}), payload);
  });

  test('a web link that is not https is ignored', () {
    expect(
      gymEntranceQrData({'payload': payload, 'webUrl': 'http://x/g/?q=1'}),
      payload,
    );
  });

  test('nothing to draw while the answer is still loading', () {
    expect(gymEntranceQrData(null), isNull);
    expect(gymEntranceQrData({}), isNull);
  });
}
