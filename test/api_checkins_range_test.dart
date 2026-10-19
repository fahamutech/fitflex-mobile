import 'dart:convert';

import 'package:fitflexmobile/shared/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'myCheckins: no range keeps the old call; a range adds from/to',
    () async {
      final urls = <Uri>[];
      final client = MockClient((req) async {
        urls.add(req.url);
        return http.Response(jsonEncode([]), 200);
      });
      await http.runWithClient(() async {
        final api = ApiClient(baseUrl: 'http://api');
        await api.myCheckins();
        await api.myCheckins(
          from: DateTime.utc(2026, 6, 25),
          to: DateTime.utc(2026, 9, 24),
        );
      }, () => client);
      expect(urls[0].path, '/me/checkins');
      expect(urls[0].query, isEmpty);
      expect(urls[1].path, '/me/checkins');
      expect(urls[1].queryParameters, {
        'from': '2026-06-25T00:00:00.000Z',
        'to': '2026-09-24T00:00:00.000Z',
      });
    },
  );
}
