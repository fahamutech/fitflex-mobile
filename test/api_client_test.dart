import 'dart:convert';
import 'dart:io';

import 'package:fitflexmobile/shared/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

Future<HttpServer> _jsonServer(int status, Map<String, dynamic> body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  });
  return server;
}

String _baseUrl(HttpServer server) =>
    'http://${server.address.host}:${server.port}';

void main() {
  test('any 401 clears the auth session, including a QR failure', () async {
    final server = await _jsonServer(401, {
      'ok': false,
      'failure': 'invalid_or_expired_qr',
    });
    try {
      final api = ApiClient(baseUrl: _baseUrl(server));
      var cleared = false;
      api.onUnauthorized = () => cleared = true;

      await expectLater(
        api.operatorVerifyQr('bad-token'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );

      expect(cleared, true);
    } finally {
      await server.close(force: true);
    }
  });

  test('unauthenticated 401 clears the auth session', () async {
    final server = await _jsonServer(401, {'error': 'unauthenticated'});
    try {
      final api = ApiClient(baseUrl: _baseUrl(server));
      var cleared = false;
      api.onUnauthorized = () => cleared = true;

      await expectLater(
        api.me(),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );

      expect(cleared, true);
    } finally {
      await server.close(force: true);
    }
  });
}
