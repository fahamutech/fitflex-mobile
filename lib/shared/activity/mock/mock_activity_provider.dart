import '../activity.dart';
import '../activity_provider.dart';
import 'mock_activity_data.dart';

/// Demo/test [ActivityProvider] serving generated history. It is not wired
/// to any device and must never be presented to members as real tracking.
class MockActivityProvider implements ActivityProvider {
  MockActivityProvider({DateTime Function()? clock, this.days = 42})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// How many days of history to generate, ending today.
  final int days;

  @override
  String get id => 'mock';

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
    final all = generateMockActivities(
      userId: userId,
      today: _clock(),
      days: days,
    );
    return all
        .where((a) => !a.startedAt.isBefore(from) && a.startedAt.isBefore(to))
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }
}
