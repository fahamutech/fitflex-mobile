import 'package:flutter/painting.dart';

import 'hero_image_files.dart';

/// The web (no `dart:io`): no disk cache. Photos are used from the network
/// after they decode in this session (hero_image_store.dart).
HeroFileStore createHeroFileStore() => const _NoDiskStore();

class _NoDiskStore implements HeroFileStore {
  const _NoDiskStore();

  @override
  bool get persistent => false;

  @override
  Future<bool> write(String name, List<int> bytes) async => false;

  @override
  Future<List<int>?> read(String name) async => null;

  @override
  Future<void> delete(String name) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<List<String>> list() async => const [];

  @override
  ImageProvider provider(String name) =>
      throw UnsupportedError('No saved photos on the web');
}
