import '../api_client.dart';
import 'activity.dart';
import 'sample_activity_log.dart';

/// Activity types a member can log by hand, in picker order. Group classes
/// and personal training come from gyms and trainers, not from here.
const manualActivityTypes = [
  ActivityType.walking,
  ActivityType.running,
  ActivityType.jogging,
  ActivityType.cycling,
  ActivityType.hiking,
  ActivityType.strength,
  ActivityType.hiit,
  ActivityType.functional,
  ActivityType.swimming,
  ActivityType.sports,
  ActivityType.mobility,
  ActivityType.stretching,
  ActivityType.other,
];

/// Which optional fields make sense for a type. Date, start time and
/// duration always apply; duration is the one required measurement.
typedef ManualFields = ({bool distance, bool steps, bool name, bool intensity});

ManualFields manualFieldsFor(ActivityType type) => switch (type) {
  ActivityType.walking ||
  ActivityType.running ||
  ActivityType.jogging ||
  ActivityType.hiking => (
    distance: true,
    steps: true,
    name: false,
    intensity: false,
  ),
  ActivityType.cycling || ActivityType.swimming => (
    distance: true,
    steps: false,
    name: false,
    intensity: false,
  ),
  ActivityType.strength ||
  ActivityType.hiit ||
  ActivityType.functional ||
  ActivityType.sports => (
    distance: false,
    steps: false,
    name: true,
    intensity: true,
  ),
  ActivityType.other => (
    distance: false,
    steps: false,
    name: true,
    intensity: false,
  ),
  _ => (distance: false, steps: false, name: false, intensity: false),
};

/// Limits match the backend's (`activity-service.mjs`), so a draft that
/// passes here is accepted there.
const manualMaxDurationMinutes = 24 * 60;
const manualMaxDistanceKm = 500.0;
const manualMaxSteps = 200000;
const manualMaxNameLength = 80;
const manualMaxNotesLength = 500;

/// How far back a member can log. The Activity screens look back 91 days,
/// so anything older wouldn't show up anywhere.
const manualMaxDaysBack = 90;

/// Server clock-skew allowance for "not in the future".
const _futureSlack = Duration(minutes: 5);

/// A hand-logged session, before it's saved.
class ManualActivityDraft {
  final ActivityType type;
  final DateTime startedAt;
  final int? durationMinutes;
  final double? distanceKm;
  final int? steps;
  final ActivityIntensity? intensity;

  /// e.g. "Upper body". The backend has no name field, so it's stored as
  /// the first line of `notes` (see [notesForBackend]).
  final String? name;
  final String? notes;

  const ManualActivityDraft({
    required this.type,
    required this.startedAt,
    this.durationMinutes,
    this.distanceKm,
    this.steps,
    this.intensity,
    this.name,
    this.notes,
  });

  String? get _name {
    final n = name?.trim();
    return n == null || n.isEmpty ? null : n;
  }

  String? get _notes {
    final n = notes?.trim();
    return n == null || n.isEmpty ? null : n;
  }

  /// "Name" or "Name\nnotes" or "notes": what goes in the `notes` column.
  String? get notesForBackend {
    final parts = [?_name, ?_notes];
    return parts.isEmpty ? null : parts.join('\n');
  }

  /// Body for `POST /me/activities`. No `source`: the server stamps
  /// `manual`, the only source a member may log.
  Map<String, dynamic> toJson() {
    final f = manualFieldsFor(type);
    return {
      'type': type.wire,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'durationMinutes': ?durationMinutes,
      if (f.distance) 'distanceKm': ?distanceKm,
      if (f.steps) 'steps': ?steps,
      if (f.intensity) 'intensity': ?intensity?.wire,
      'notes': ?notesForBackend,
    };
  }
}

/// Field → i18n key of what's wrong with it. Empty when the draft is valid.
Map<String, String> validateManualActivity(
  ManualActivityDraft d,
  DateTime now,
) {
  final errors = <String, String>{};
  final f = manualFieldsFor(d.type);
  final minutes = d.durationMinutes;
  if (minutes == null) {
    errors['duration'] = 'logActivity.error.durationRequired';
  } else if (minutes < 1 || minutes > manualMaxDurationMinutes) {
    errors['duration'] = 'logActivity.error.durationRange';
  }
  if (d.startedAt.isAfter(now.add(_futureSlack))) {
    errors['startedAt'] = 'logActivity.error.future';
  } else if (d.startedAt.isBefore(
    DateTime(now.year, now.month, now.day - manualMaxDaysBack),
  )) {
    errors['startedAt'] = 'logActivity.error.tooOld';
  }
  final km = d.distanceKm;
  if (f.distance && km != null && (km <= 0 || km > manualMaxDistanceKm)) {
    errors['distance'] = 'logActivity.error.distanceRange';
  }
  final steps = d.steps;
  if (f.steps && steps != null && (steps < 1 || steps > manualMaxSteps)) {
    errors['steps'] = 'logActivity.error.stepsRange';
  }
  if ((d._name?.length ?? 0) > manualMaxNameLength) {
    errors['name'] = 'logActivity.error.nameLength';
  }
  if ((d.notesForBackend?.length ?? 0) > manualMaxNotesLength) {
    errors['notes'] = 'logActivity.error.notesLength';
  }
  return errors;
}

/// The name a logged session was given: the first line of its notes, for
/// types that take a name.
String? manualActivityName(Activity a) {
  if (a.origin != DataOrigin.manual || !manualFieldsFor(a.type).name) {
    return null;
  }
  final first = (a.notes ?? '').split('\n').first.trim();
  return first.isEmpty ? null : first;
}

/// Saves hand-logged activity. Separate from [ActivityProvider], which only
/// reads (a device provider can never write).
abstract interface class ManualActivityLog {
  Future<Activity> log(ManualActivityDraft draft);
}

/// `POST /me/activities`: the existing backend contract.
class ApiManualActivityLog implements ManualActivityLog {
  ApiManualActivityLog(this.api);

  final ApiClient api;

  @override
  Future<Activity> log(ManualActivityDraft draft) async {
    final res = await api.logActivity(draft.toJson());
    final row = res['activity'];
    if (row is! Map) throw const FormatException('No activity in response');
    return Activity.fromJson(Map<String, dynamic>.from(row));
  }
}

/// Sample-data mode: keeps the entry in this session's [SampleActivityLog],
/// which the sample provider serves, so the screens behave the same.
class LocalManualActivityLog implements ManualActivityLog {
  LocalManualActivityLog({required this.sampleLog, this.userId = ''});

  final SampleActivityLog sampleLog;
  final String userId;
  var _seq = 0;

  @override
  Future<Activity> log(ManualActivityDraft draft) async {
    final a = Activity(
      id: 'sample_manual_${DateTime.now().microsecondsSinceEpoch}_${_seq++}',
      userId: userId,
      type: draft.type,
      source: ActivitySource.manual,
      startedAt: draft.startedAt,
      durationMinutes: draft.durationMinutes,
      distanceKm: manualFieldsFor(draft.type).distance
          ? draft.distanceKm
          : null,
      steps: manualFieldsFor(draft.type).steps ? draft.steps : null,
      intensity: manualFieldsFor(draft.type).intensity ? draft.intensity : null,
      notes: draft.notesForBackend,
      isSample: true,
    );
    sampleLog.add(a);
    return a;
  }
}
