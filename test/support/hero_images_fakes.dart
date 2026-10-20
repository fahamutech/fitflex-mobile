// Fakes for the admin-published app photos store (HERO_IMAGES_REMOTE):
// a mock server for GET /app/hero-images and /storage files, an in-memory
// photo folder and a device probe.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitflexmobile/shared/hero_images/device_data.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_files.dart';
import 'package:fitflexmobile/shared/hero_images/hero_image_store.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  /// File bodies by entry id; default: decodable bytes of the declared size.
  final Map<String, List<int>> fileBody = {};
  bool sendLength = true;
  final Map<String, int> bytesStreamed = {};

  final List<http.BaseRequest> requests = [];
  final FakeFiles files = FakeFiles();
  final FakeDevice device = FakeDevice();

  /// Web: entry ids whose image fails to load, and every URL tried.
  final Set<String> precacheFails = {};
  final List<String> precached = [];

  List<http.BaseRequest> get manifestRequests =>
      requests.where((r) => r.url.path == '/app/hero-images').toList();
  List<http.BaseRequest> get fileRequests =>
      requests.where((r) => r.url.path.startsWith('/storage/')).toList();

  HeroImageStore store({bool footer = false}) => HeroImageStore(
    apiBase: fakeApiBase,
    client: MockClient.streaming(_handle),
    files: web ? FakeFiles(persistent: false) : files,
    device: device,
    clock: () => clock,
    decodeTest: (b) async => _decodes(b),
    precache: (p) async {
      final url = (p as NetworkImage).url;
      precached.add(url);
      return !precacheFails.any((id) => url.contains('/$id-'));
    },
    web: web,
    footerOn: () => footer,
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

  Future<http.StreamedResponse> _handle(
    http.BaseRequest req,
    http.ByteStream _,
  ) async {
    requests.add(req);
    if (req.url.path == '/app/hero-images') {
      if (hangManifest) await Completer<void>().future;
      final m = manifest ?? {'version': 0, 'slots': {}};
      final etag = '"hp_${m['version']}"';
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
        final end = i + step < body.length ? i + step : body.length;
        bytesStreamed[id] = bytesStreamed[id]! + (end - i);
        yield body.sublist(i, end);
      }
    }

    return http.StreamedResponse(
      chunks(),
      200,
      contentLength: sendLength ? body.length : null,
    );
  }
}
