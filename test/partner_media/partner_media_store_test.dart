// Partner photo and logo saved copies (spec §40.1, AC-P11): fetched signed
// in from the API host only, kept after a decode test, cleared when the item
// is gone or the feature is off, kept offline, never over the size caps, and
// Data Saver respected.
import 'dart:convert';

import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_flag.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_models.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_store.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/hero_images_fakes.dart';
import '../support/recording_api.dart';
import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingApi api;
  late FakeFiles files;
  late FakeDevice device;
  late PartnerMediaStore store;
  final subject = PartnerMediaSubject.trainer('u1');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugPhotoHeroUiOverride = true;
    debugPartnerMediaUiOverride = true;
    api = RecordingApi();
    files = FakeFiles();
    device = FakeDevice();
    final client = ApiClient(baseUrl: fakeApiBase)..setToken('jwt');
    store = PartnerMediaStore(
      api: client,
      files: files,
      device: device,
      decodeTest: (b) async => b.isNotEmpty,
    );
    api.onCall(
      'GET /partner/media/pmd_hero1/file',
      (_) => RawResponse(200, latin1.decode(okBytes(1000))),
    );
    api.onCall(
      'GET /partner/media/pmd_logo1/file',
      (_) => RawResponse(200, latin1.decode(okBytes(500))),
    );
  });
  tearDown(() {
    debugPhotoHeroUiOverride = null;
    debugPartnerMediaUiOverride = null;
  });

  test('flag off: no store, so no request', () {
    debugPartnerMediaUiOverride = false;
    expect(PartnerMediaStore.startIfEnabled(ApiClient()), isNull);
    expect(PartnerMediaStore.instance, isNull);
  });

  test('live photo and logo are saved, with the session header, from the '
      'API host', () async {
    api.on('GET /partner/media', overview(hero: heroItem(), logo: logoItem()));
    await api.run(() async {
      final o = await store.refresh(subject);
      expect(o?.hero?.id, 'pmd_hero1');
    });
    expect(files.names, ['pmd_hero1_x2.img', 'pmd_logo1_logo256.img']);
    final file = api.only('GET', '/partner/media/pmd_hero1/file');
    expect(file.query, 'variant=x2');
    expect(file.headers['authorization'], 'Bearer jwt');
    final m = store.readyFor(subject)!;
    expect(m.photo!.focal.x, 0.5);
    expect(m.logo!.dark, isTrue);
    // Another account on the same phone sees nothing of it.
    expect(store.readyFor(PartnerMediaSubject.trainer('u2')), isNull);
  });

  test('removed or taken down: the saved copy is deleted', () async {
    api.on('GET /partner/media', overview(hero: heroItem(), logo: logoItem()));
    await api.run(() => store.refresh(subject));
    api.on(
      'GET /partner/media',
      overview(
        heroDown: heroItem(
          status: 'taken_down',
          takedown: {'reason': 'rights'},
        ),
      ),
    );
    await api.run(() => store.refresh(subject, force: true));
    expect(files.names, isEmpty);
    expect(store.readyFor(subject), isNull);
  });

  test('feature_disabled: cleared and treated as off', () async {
    api.on('GET /partner/media', overview(hero: heroItem()));
    await api.run(() => store.refresh(subject));
    api.fail('GET /partner/media', 404, {'error': 'feature_disabled'});
    await api.run(() => store.refresh(subject, force: true));
    expect(store.featureOff, isTrue);
    expect(files.names, isEmpty);
  });

  test('offline: the last saved copy stays', () async {
    api.on('GET /partner/media', overview(hero: heroItem()));
    await api.run(() => store.refresh(subject));
    await http.runWithClient(
      () => store.refresh(subject, force: true),
      () => _Offline(),
    );
    expect(store.readyFor(subject)?.photo?.id, 'pmd_hero1');
  });

  test('an oversize or corrupt file is never shown', () async {
    api.on(
      'GET /partner/media',
      overview(
        hero: heroItem(bytes: 300 * 1024),
        logo: logoItem(),
      ),
    );
    api.onCall(
      'GET /partner/media/pmd_logo1/file',
      (_) => RawResponse(200, latin1.decode(okBytes(70 * 1024))),
    );
    await api.run(() => store.refresh(subject));
    expect(api.sent('GET', '/partner/media/pmd_hero1/file'), isFalse);
    expect(files.names, isEmpty);
    expect(store.readyFor(subject), isNull);
  });

  test('a file address on another host is never requested', () async {
    final item = heroItem();
    (item['files'] as Map)['x2'] =
        'https://evil.test/partner/media/pmd_hero1/file?variant=x2';
    api.on('GET /partner/media', overview(hero: item));
    await api.run(() => store.refresh(subject));
    expect(api.requests.where((r) => r.path.contains('/file')), isEmpty);
    expect(store.readyFor(subject), isNull);
  });

  test('Data Saver: nothing new is downloaded', () async {
    device.reduced = true;
    api.on('GET /partner/media', overview(hero: heroItem()));
    await api.run(() => store.refresh(subject));
    expect(api.sent('GET', '/partner/media/pmd_hero1/file'), isFalse);
  });

  test('sign-out clears everything', () async {
    api.on('GET /partner/media', overview(hero: heroItem(), logo: logoItem()));
    await api.run(() => store.refresh(subject));
    await store.clearAll();
    expect(files.names, isEmpty);
    expect(store.readyFor(subject), isNull);
  });

  test('saved copies are decode-tested again after a restart', () async {
    api.on('GET /partner/media', overview(hero: heroItem()));
    await api.run(() => store.refresh(subject));
    final again = PartnerMediaStore(
      api: ApiClient(baseUrl: fakeApiBase),
      files: files,
      device: device,
      decodeTest: (b) async => false, // now corrupt
    );
    await again.load();
    expect(again.readyFor(subject), isNull);
    expect(files.names, isEmpty);
  });
  test(
    'saved files are revalidated: 304 keeps, 404 drops (review M1)',
    () async {
      final seen = <String?>[];
      var fileStatus = 200;
      final client = _Scripted((req) {
        if (req.url.path == '/partner/media') {
          return http.Response(
            jsonEncode(overview(hero: heroItem())),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        seen.add(req.headers['if-none-match']);
        if (fileStatus == 200) {
          return http.Response.bytes(
            okBytes(800),
            200,
            headers: {'etag': '"pmf_1"'},
          );
        }
        return http.Response(
          fileStatus == 404 ? '{"error":"media_not_found"}' : '',
          fileStatus,
        );
      });
      await http.runWithClient(() async {
        await store.refresh(subject);
        fileStatus = 304;
        await store.refresh(subject, force: true);
        expect(store.readyFor(subject)?.photo?.id, 'pmd_hero1');
        fileStatus = 404;
        await store.refresh(subject, force: true);
      }, () => client);
      expect(seen, [null, '"pmf_1"', '"pmf_1"']);
      expect(store.readyFor(subject), isNull);
      expect(files.names, isEmpty);
    },
  );
}

class _Scripted extends http.BaseClient {
  _Scripted(this.answer);
  final http.Response Function(http.BaseRequest req) answer;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = answer(request);
    return http.StreamedResponse(
      Stream.value(r.bodyBytes),
      r.statusCode,
      headers: r.headers,
      contentLength: r.bodyBytes.length,
    );
  }
}

class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw http.ClientException('offline');
}
