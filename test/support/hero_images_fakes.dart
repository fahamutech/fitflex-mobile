// Fakes for the admin-published app photos store (HERO_IMAGES_REMOTE):
// a mock server for GET /app/hero-images and /storage files (with
// redirects, slow bodies and cancellation tracking), an in-memory photo
// folder and a device probe.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitflexmobile/shared/hero_images/device_data.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_files.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_store.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

const fakeApiBase = 'https://api.fitflex.test';

/// One manifest entry as the server sends it (functions/hero-images.mjs).
Map<String, Object?> entryJson(
  String id, {
  String? sourceId,
  int bytes = 4000,
  Map<String, Object?> focal = const {'x': -0.3, 'y': 0.2},
}) => {
  'id': id,
  'sourceId': sourceId ?? 'hero_$id',
  'url': '/storage/bafy/$id-2x.webp',
  'url1x': '/storage/bafy/$id-1x.webp',
  'urlWide': '/storage/bafy/$id-wide.webp',
  'urlAvif': null,
  'width': 1080,
  'height': 720,
  'bytes': bytes,
  'focal': focal,
};

Map<String, Object?> manifestJson(
  int version,
  Map<String, List<Map<String, Object?>>> slots,
) => {
  'version': version,
  'publishedAt': '2026-10-20T08:00:00.000Z',
  'slots': slots,
};

/// Bytes the fake decoder accepts: "OK" then padding.
List<int> okBytes(int n) => Uint8List(n < 2 ? 2 : n)
  ..[0] = 0x4f
  ..[1] = 0x4b;

bool _decodes(List<int> b) => b.length >= 2 && b[0] == 0x4f && b[1] == 0x4b;

class FakeFiles implements HeroFileStore {
  FakeFiles({this.persistent = true});

  @override
  final bool persistent;
  final Map<String, List<int>> data = {};
  bool failWrites = false;

  List<String> get names => data.keys.toList()..sort();
  int get totalBytes => data.values.fold(0, (a, b) => a + b.length);

  @override
  Future<bool> write(String name, List<int> bytes) async {
    if (failWrites || !persistent) return false;
    data[name] = List.of(bytes);
    return true;
  }

  @override
  Future<List<int>?> read(String name) async => data[name];

  @override
  Future<void> delete(String name) async => data.remove(name);

  @override
  Future<void> deleteAll() async => data.clear();

  @override
  Future<List<String>> list() async => names;

  @override
  ImageProvider provider(String name) =>
      MemoryImage(Uint8List.fromList(data[name] ?? const []));
}

class FakeDevice implements DeviceDataProbe {
  bool reduced = false;
  int? free;

  @override
  Future<bool> reducedData() async => reduced;

  @override
  Future<int?> freeBytes() async => free;
}

class FakeServer {
  FakeServer({this.web = false});

  final bool web;
  DateTime clock = DateTime(2026, 10, 20, 9);
  Map<String, Object?>? manifest;
  String? manifestRaw;
  int manifestStatus = 200;
  bool hangManifest = false;
  int? lastManifestStatus;

  /// Manifest body chunks: when set, the list is sent in these many 16 KB
  /// chunks of padding (an oversize body), and [manifestStreamed] counts
  /// what was actually sent before the app cancelled.
  int? manifestJunkChunks;
  int manifestStreamed = 0;

  /// File bodies by entry id; default: decodable bytes of the declared size.
  final Map<String, List<int>> fileBody = {};
  bool sendLength = true;
  final Map<String, int> bytesStreamed = {};

  /// Bodies the app stopped reading (cancelled), by URL.
  final Set<String> cancelled = {};

  /// When set, every file chunk waits this long first (a slow drip).
  Duration? drip;

  /// `full URL → Location`: that address answers 307 with the Location.
  final Map<String, String> redirects = {};

  /// Status for an address (instead of the file), by full URL.
  final Map<String, int> statusFor = {};

  final List<http.BaseRequest> requests = [];
  final FakeFiles files = FakeFiles();
  final FakeDevice device = FakeDevice();

  List<http.BaseRequest> get manifestRequests =>
      requests.where((r) => r.url.path == '/app/hero-images').toList();
  List<http.BaseRequest> get fileRequests =>
      requests.where((r) => r.url.path.startsWith('/storage/')).toList();

  HeroImageStore store({
    bool footer = false,
    Set<String>? allowedHosts,
    String apiBase = fakeApiBase,
  }) => HeroImageStore(
    apiBase: apiBase,
    client: _FakeClient(this),
    files: web ? FakeFiles(persistent: false) : files,
    device: device,
    clock: () => clock,
    decodeTest: (b) async => _decodes(b),
    web: web,
    footerOn: () => footer,
    allowedHosts: allowedHosts ?? const {},
  );

  int? _declared(String id) {
    final slots = (manifest?['slots'] as Map?) ?? const {};
    for (final list in slots.values) {
      for (final e in list as List) {
        if ((e as Map)['id'] == id) return e['bytes'] as int;
      }
    }
    return null;
  }

  /// One hop, as a server would answer it.
  Future<http.StreamedResponse> _answer(http.BaseRequest req) async {
    requests.add(req);
    final url = req.url.toString();
    if (redirects.containsKey(url)) {
      return http.StreamedResponse(
        _tracked(url, Stream.value(utf8.encode('moved'))),
        307,
        headers: {'location': redirects[url]!},
        contentLength: 5,
      );
    }
    if (statusFor.containsKey(url)) {
      return http.StreamedResponse(
        _tracked(url, Stream.value(utf8.encode('nope'))),
        statusFor[url]!,
        contentLength: 4,
      );
    }
    if (req.url.path == '/app/hero-images') {
      if (hangManifest) await Completer<void>().future;
      final m = manifest ?? {'version': 0, 'slots': {}};
      final etag = '"hp_${m['version']}"';
      if (manifestJunkChunks != null) {
        Stream<List<int>> junk() async* {
          for (var i = 0; i < manifestJunkChunks!; i++) {
            if (drip != null) await Future<void>.delayed(drip!);
            manifestStreamed += 16 * 1024;
            yield List.filled(16 * 1024, 0x20);
          }
        }

        return http.StreamedResponse(_tracked(url, junk()), 200);
      }
      final status =
          manifestRaw == null &&
              manifestStatus == 200 &&
              req.headers['if-none-match'] == etag
          ? 304
          : manifestStatus;
      lastManifestStatus = status;
      final body = status == 304
          ? <int>[]
          : utf8.encode(manifestRaw ?? jsonEncode(m));
      return http.StreamedResponse(
        Stream.value(body),
        status,
        headers: {'etag': etag, 'cache-control': 'public, max-age=300'},
      );
    }
    final file = req.url.pathSegments.last;
    final id = file.substring(0, file.lastIndexOf('-'));
    final body = fileBody[id] ?? okBytes(_declared(id) ?? 4000);
    bytesStreamed[id] = 0;
    Stream<List<int>> chunks() async* {
      const step = 16 * 1024;
      for (var i = 0; i < body.length; i += step) {
        if (drip != null) await Future<void>.delayed(drip!);
        final end = i + step < body.length ? i + step : body.length;
        bytesStreamed[id] = bytesStreamed[id]! + (end - i);
        yield body.sublist(i, end);
      }
    }

    return http.StreamedResponse(
      _tracked(url, chunks()),
      200,
      contentLength: sendLength ? body.length : null,
    );
  }

  /// [source] with cancellation recorded under [url].
  Stream<List<int>> _tracked(String url, Stream<List<int>> source) {
    late final StreamController<List<int>> c;
    StreamSubscription<List<int>>? sub;
    c = StreamController<List<int>>(
      onListen: () {
        sub = source.listen(c.add, onError: c.addError, onDone: c.close);
      },
      onCancel: () {
        if (!c.isClosed) cancelled.add(url);
        return sub?.cancel();
      },
    );
    return c.stream;
  }
}

/// A client over [FakeServer]. With `followRedirects` on (the app sets it
/// only on the web, where the browser follows them) it follows the
/// redirects itself, like a browser, and reports the final address.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.server);

  final FakeServer server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var req = request;
    var res = await server._answer(req);
    if (!request.followRedirects) return res;
    var hops = 0;
    while (res.statusCode == 307 && hops++ < 20) {
      await res.stream.listen(null).cancel();
      final next = req.url.resolve(res.headers['location']!);
      req = http.Request('GET', next)..headers.addAll(request.headers);
      res = await server._answer(req);
    }
    return _LandedResponse(
      res.stream,
      res.statusCode,
      url: req.url,
      contentLength: res.contentLength,
      headers: res.headers,
    );
  }
}

/// A response that says where it landed after redirects (as the browser
/// client's does).
class _LandedResponse extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _LandedResponse(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.headers,
  });

  @override
  final Uri url;
}
