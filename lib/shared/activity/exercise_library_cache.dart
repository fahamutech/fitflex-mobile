import 'package:flutter/foundation.dart';

import '../api_client.dart';
import 'trainer_connection.dart';

/// The FitFlex exercise library, kept once per app run for the workout page
/// (Programmes P1, M2): a workout's exercises carry only their library id,
/// so rest between sets and the picture/clip links are read from here.
///
/// Loaded quietly: when it can't be (offline, sample mode), the workout
/// page simply shows no rest timer and no media, as before.
class ExerciseLibraryCache {
  ExerciseLibraryCache._();

  static Map<String, LibraryExercise>? _byId;
  static String? _lang;
  static Future<void>? _loading;

  /// The library exercise for [id], once loaded.
  static LibraryExercise? of(String? id) => id == null ? null : _byId?[id];

  static bool get loaded => _byId != null;

  /// Loads the library in [lang] unless it already is.
  static Future<void> ensure(ApiClient api, {String? lang}) {
    if (_byId != null && _lang == lang) return Future.value();
    return _loading ??= _load(api, lang).whenComplete(() => _loading = null);
  }

  static Future<void> _load(ApiClient api, String? lang) async {
    try {
      final rows = await api.trainingExercises(lang: lang);
      final parsed = [for (final raw in rows) ?LibraryExercise.tryParse(raw)];
      _byId = {for (final e in parsed) e.id: e};
      _lang = lang;
    } catch (_) {
      // Left unloaded; asked again the next time a workout opens.
    }
  }

  @visibleForTesting
  static void seed(List<LibraryExercise> exercises, {String? lang}) {
    _byId = {for (final e in exercises) e.id: e};
    _lang = lang;
  }

  @visibleForTesting
  static void reset() {
    _byId = null;
    _lang = null;
    _loading = null;
  }
}
