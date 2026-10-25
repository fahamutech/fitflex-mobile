import 'dart:convert';

import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/rest_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _profile =
    '{"name":"Asha Juma","phone":"+255700000001","email":"asha@example.com",'
    '"idToken":"eyJsecret","order":{"total":45000}}';

Future<List<String>> _pinLoginLines(RestLogLevel level) async {
  final lines = <String>[];
  final api = ApiClient(
    baseUrl: 'http://api.test',
    logger: RestLogger(level: level, sink: lines.add),
  );
  api.setToken('bearer-secret');
  final mock = MockClient((req) async => http.Response(_profile, 200));
  await http.runWithClient(
    () => api.pinLogin({'phone': '+255700000001'}, '4321'),
    () => mock,
  );
  return lines;
}

void main() {
  group('restLogLevelFor', () {
    test('release builds log nothing by default', () {
      expect(
        restLogLevelFor(debugMode: false, define: false),
        RestLogLevel.off,
      );
    });
    test('the dart-define only enables a summary in release', () {
      expect(
        restLogLevelFor(debugMode: false, define: true),
        RestLogLevel.summary,
      );
    });
    test('debug builds log in full', () {
      expect(
        restLogLevelFor(debugMode: true, define: false),
        RestLogLevel.full,
      );
    });
  });

  group('ApiClient logging', () {
    test('off: prints nothing', () async {
      expect(await _pinLoginLines(RestLogLevel.off), isEmpty);
    });

    test('summary: no bodies, headers, tokens or query strings', () async {
      final lines = await _pinLoginLines(RestLogLevel.summary);
      final all = lines.join('\n');
      expect(lines, [
        '[REST] --> POST http://api.test/auth/pin/login',
        '[REST] <-- 200 POST http://api.test/auth/pin/login',
      ]);
      for (final secret in [
        'bearer-secret',
        '4321',
        '+255700000001',
        'Asha',
        'asha@example.com',
        'eyJsecret',
      ]) {
        expect(all, isNot(contains(secret)));
      }

      final query = RestLogger(level: RestLogLevel.summary);
      expect(
        query.describeUri(Uri.parse('http://api.test/x?phone=+2557')),
        'http://api.test/x',
      );
    });

    test('full: bodies printed but secrets redacted', () async {
      final all = (await _pinLoginLines(RestLogLevel.full)).join('\n');
      expect(all, contains('/auth/pin/login'));
      expect(all, contains('asha@example.com'));
      expect(all, isNot(contains('bearer-secret')));
      expect(all, isNot(contains('4321')));
      expect(all, isNot(contains('eyJsecret')));
    });
  });

  group('redactBody', () {
    test('redacts token, PIN, password and code values', () {
      final out = redactBody(
        jsonEncode({
          'setupToken': 'a',
          'refreshToken': 'b',
          'newPin': '1234',
          'pin': 9876,
          'password': 'p"w',
          'code': '555111',
          'name': 'kept',
        }),
      );
      for (final v in ['"a"', '"b"', '1234', '9876', 'p\\"w', '555111']) {
        expect(out, isNot(contains(v)));
      }
      expect(out, contains('"name":"kept"'));
    });

    test('redacts date of birth and gender (fitflex-functions#253)', () {
      final out = redactBody(
        jsonEncode({
          'dateOfBirth': '1994-03-21',
          'gender': 'female',
          'memberProfile': {'dateOfBirth': '1990-05-10', 'gender': 'male'},
          'source': 'person',
        }),
      );
      for (final v in ['1994-03-21', 'female', '1990-05-10', '"male"']) {
        expect(out, isNot(contains(v)));
      }
      expect(out, contains('"source":"person"'));
    });

    test('truncates long bodies', () {
      expect(redactBody('x' * 5000), endsWith('...<truncated>'));
    });
  });
}
