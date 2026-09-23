import 'activity.dart';

/// Activities recorded in sample-data mode during this app session (e.g. a
/// finished sample workout). The sample activity provider serves them
/// alongside its generated history. Nothing is persisted.
class SampleActivityLog {
  final List<Activity> _items = [];

  List<Activity> get items => List.unmodifiable(_items);

  void add(Activity activity) => _items.add(activity);
}
