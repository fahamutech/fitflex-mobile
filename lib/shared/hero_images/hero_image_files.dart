import 'package:flutter/painting.dart';

export 'hero_image_files_stub.dart'
    if (dart.library.io) 'hero_image_files_io.dart';

/// Where downloaded app photos are kept. On phones a private app folder;
/// on the web nothing is kept on disk (see the stub).
abstract class HeroFileStore {
  /// False on the web: there is no disk cache there.
  bool get persistent;

  /// Saves [bytes] as [name]: written to a temporary file first, then
  /// renamed, so a half-written file is never read. False on any error
  /// (full disk included).
  Future<bool> write(String name, List<int> bytes);

  /// The saved bytes, or null.
  Future<List<int>?> read(String name);

  Future<void> delete(String name);

  /// Removes every saved photo (and any half-written temporary file).
  Future<void> deleteAll();

  /// Saved file names (temporary files excluded).
  Future<List<String>> list();

  /// An image provider for a saved file.
  ImageProvider provider(String name);
}

/// File names are entry ids (letters, digits, `_`, `-`) plus `.img`.
final RegExp heroFileName = RegExp(r'^[A-Za-z0-9_-]{1,120}\.img$');
