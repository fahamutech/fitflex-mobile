import 'package:flutter/foundation.dart';

import '../api_client.dart';
import 'activity.dart';
import 'activity_provider.dart';

/// Activities stored on the FitFlex backend (`/me/activities`). The server
/// scopes results to the signed-in member, so [userId] is not sent.
class ApiActivityProvider implements ActivityProvider {
  ApiActivityProvider(this.api);

  final ApiClient api;

  @override
  String get id => 'fitflex_api';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<List<Activity>> activitiesBetween({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await api.myActivities(from: from, to: to);
    final out = <Activity>[];
    for (final r in rows.whereType<Map>()) {
      try {
        out.add(Activity.fromJson(Map<String, dynamic>.from(r)));
      } on FormatException catch (e) {
        // One bad row must not hide the rest of the history.
        debugPrint('[ApiActivityProvider] skipping activity: $e');
      }
    }
    return out..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }
}
