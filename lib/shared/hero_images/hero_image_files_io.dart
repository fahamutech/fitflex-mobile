import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'hero_image_files.dart';

/// Phones: `<application support>/hero_images/`, private to the app and
/// not backed up as user documents.
HeroFileStore createHeroFileStore() => IoHeroFileStore(
  () async =>
      Directory('${(await getApplicationSupportDirectory()).path}/hero_images'),
);

/// A saved-photo folder. Tests pass a temporary directory.
class IoHeroFileStore implements HeroFileStore {
  IoHeroFileStore(this._dirFn);

  /// Convenience for tests.
  factory IoHeroFileStore.at(Directory dir) => IoHeroFileStore(() async => dir);

  final Future<Directory> Function() _dirFn;
  Directory? _dir;

  Future<Directory> _folder() async {
    final d = _dir ??= await _dirFn();
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  File _file(Directory d, String name) {
    if (!heroFileName.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'not a hero file name');
    }
    return File('${d.path}/$name');
  }

  @override
  bool get persistent => true;

  @override
  Future<bool> write(String name, List<int> bytes) async {
    File? tmp;
    try {
      final d = await _folder();
      final target = _file(d, name);
      tmp = File('${target.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
      return true;
    } catch (_) {
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return false;
    }
  }

  @override
  Future<List<int>?> read(String name) async {
    try {
      final f = _file(await _folder(), name);
      return await f.exists() ? await f.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String name) async {
    try {
      final f = _file(await _folder(), name);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  Future<void> deleteAll() async {
    try {
      final d = await _folder();
      await for (final e in d.list()) {
        if (e is File) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @override
  Future<List<String>> list() async {
    try {
      final d = await _folder();
      return [
        await for (final e in d.list())
          if (e is File && heroFileName.hasMatch(e.uri.pathSegments.last))
            e.uri.pathSegments.last,
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  ImageProvider provider(String name) => FileImage(_fileSync(name));

  File _fileSync(String name) {
    final d = _dir;
    if (d == null) throw StateError('folder not opened yet');
    return _file(d, name);
  }
}
