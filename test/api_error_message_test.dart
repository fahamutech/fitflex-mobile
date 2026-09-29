import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '400 response exposes the backend decline reason without raw status',
    () {
      final message = apiErrorMessage(
        FFLocale(),
        ApiException(400, {'error': 'gym_tier_not_covered'}),
      );

      expect(message, 'Request declined: Gym tier not covered');
      expect(message, isNot(contains('400')));
    },
  );

  test('nested validation response uses the first useful reason', () {
    final message = apiErrorMessage(
      FFLocale(),
      ApiException(400, {
        'errors': [
          {'message': 'Choose an available trainer slot'},
          {'message': 'Second error'},
        ],
      }),
    );

    expect(message, 'Request declined: Choose an available trainer slot');
  });

  test('generic decline prefix is localized in Swahili', () {
    final locale = FFLocale()..set(const Locale('sw'));

    expect(
      apiErrorMessage(
        locale,
        ApiException(409, {'reason': 'membership_expired'}),
      ),
      'Ombi limekataliwa: Uanachama umeisha',
    );
  });

  test('a permission taken away explains itself (communications M11)', () {
    expect(
      apiErrorMessage(
        FFLocale(),
        ApiException(403, {
          'error': 'acl_forbidden',
          'requiredScope': 'communications',
        }),
      ),
      "Request declined: Your account doesn't have permission for this. Ask the gym owner.",
    );
    expect(
      apiErrorMessage(
        FFLocale(),
        ApiException(403, {'error': 'account_suspended'}),
      ),
      contains(FFLocale().t('error.reason.accountSuspended')),
    );
  });

  test('manual check-in of a pass member tells the owner to scan the QR', () {
    final error = ApiException(409, {'error': 'direct_membership_required'});
    expect(
      apiErrorMessage(FFLocale(), error),
      'Request declined: This member has a FitFlex pass. Scan their QR code to check them in.',
    );
    expect(
      apiErrorMessage(FFLocale()..set(const Locale('sw')), error),
      'Ombi limekataliwa: Mwanachama huyu ana pasi ya FitFlex. Changanua QR yake ili kumwingiza.',
    );
  });
}
