// Controller — holds members-list UI state + orchestrates use-cases via the
// repository. This is the "service/logic" layer: it has NO Flutter widget code,
// only ChangeNotifier state, so screens stay thin and the logic is testable.

import 'package:flutter/foundation.dart';

import 'data/member_models.dart';
import 'data/member_repository.dart';

/// Member-type filter options shown as segmented tabs / filter chips.
enum MemberTypeFilter {
  all,
  direct,
  fitflex;

  String? get wire => switch (this) {
    MemberTypeFilter.direct => 'direct',
    MemberTypeFilter.fitflex => 'fitflex',
    MemberTypeFilter.all => null,
  };
}

class MemberListController extends ChangeNotifier {
  MemberListController(this._repo);

  final MemberRepository _repo;

  /// Exposed so list actions (create member) can reuse the same repository.
  MemberRepository get repository => _repo;

  // ── state ──────────────────────────────────────────────────────────────
  bool _loading = false;
  String? _error;
  List<OwnerMember> _members = const [];
  MemberStats _stats = const MemberStats();

  MemberTypeFilter _typeFilter = MemberTypeFilter.all;
  OwnerMemberStatus? _statusFilter; // null == any
  String _search = '';

  bool get loading => _loading;
  String? get error => _error;
  List<OwnerMember> get members => _members;
  MemberStats get stats => _stats;
  MemberTypeFilter get typeFilter => _typeFilter;
  OwnerMemberStatus? get statusFilter => _statusFilter;
  String get search => _search;

  bool get isEmpty => !_loading && _error == null && _members.isEmpty;
  bool get hasActiveFilters =>
      _typeFilter != MemberTypeFilter.all ||
      _statusFilter != null ||
      _search.trim().isNotEmpty;

  // ── intents ────────────────────────────────────────────────────────────
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repo.fetchMembers(
        memberType: _typeFilter.wire,
        status: _statusFilter?.wire,
        search: _search,
      );
      _members = result.members;
      _stats = result.stats;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  Future<void> setTypeFilter(MemberTypeFilter value) async {
    if (_typeFilter == value) return;
    _typeFilter = value;
    await load();
  }

  Future<void> setSearch(String value) async {
    _search = value;
    await load();
  }

  /// Apply both filters at once (used by the filter bottom sheet).
  Future<void> applyFilters({
    required MemberTypeFilter type,
    required OwnerMemberStatus? status,
  }) async {
    _typeFilter = type;
    _statusFilter = status;
    await load();
  }

  Future<void> clearFilters() async {
    _typeFilter = MemberTypeFilter.all;
    _statusFilter = null;
    _search = '';
    await load();
  }
}

/// Controller for the Member Details screen — owns the loaded detail + the
/// member-level actions (check-in, renew, suspend). UI-free logic layer.
class MemberDetailController extends ChangeNotifier {
  MemberDetailController(this._repo, this.memberId);

  final MemberRepository _repo;
  final String memberId;

  bool _loading = false;
  bool _busy = false;
  String? _error;
  MemberDetail? _detail;

  // Check-in summary period selector state.
  CheckInPeriod _period = CheckInPeriod.month;
  DateTime? _customFrom;
  DateTime? _customTo;
  CheckInSummary? _periodSummary;
  bool _summaryLoading = false;

  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;
  MemberDetail? get detail => _detail;

  CheckInPeriod get period => _period;
  DateTime? get customFrom => _customFrom;
  DateTime? get customTo => _customTo;
  bool get summaryLoading => _summaryLoading;

  /// The check-in summary to render: the period-filtered one when available,
  /// otherwise the default (this-month) summary embedded in the detail payload.
  CheckInSummary? get checkInSummary =>
      _periodSummary ?? _detail?.checkInSummary;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _detail = await _repo.fetchMemberDetail(memberId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Switches the check-in summary period and refetches just the summary.
  /// For [CheckInPeriod.custom], [from] and [to] are required.
  Future<void> setPeriod(
    CheckInPeriod period, {
    DateTime? from,
    DateTime? to,
  }) async {
    _period = period;
    _customFrom = from;
    _customTo = to;
    _summaryLoading = true;
    notifyListeners();
    try {
      _periodSummary = await _repo.fetchCheckInSummary(
        memberId,
        period: period,
        from: from,
        to: to,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _summaryLoading = false;
      notifyListeners();
    }
  }

  /// Checks the member in and reloads. Returns true on success.
  Future<bool> checkIn({String? gymId}) async {
    return _run(() => _repo.checkInMember(memberId, gymId: gymId));
  }

  Future<bool> renew(Map<String, dynamic> payload) async {
    return _run(() => _repo.renewMember(memberId, payload));
  }

  Future<bool> editMember(Map<String, dynamic> payload) async {
    return _run(() => _repo.updateMember(memberId, payload));
  }

  Future<bool> toggleSuspend({required bool suspend}) async {
    return _run(() => _repo.setSuspended(memberId, suspend: suspend));
  }

  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    var ok = false;
    try {
      await action();
      await load();
      ok = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
    return ok;
  }
}

/// Signature for a paged fetch (check-ins or payments) with date range + search.
typedef PagedFetcher<T> =
    Future<PagedResult<T>> Function({
      int? cursor,
      int limit,
      DateTime? from,
      DateTime? to,
      String? search,
    });

/// Drives a "View all" data table — first page load, load-more (offset cursor),
/// date-range filtering and search. UI-free, testable logic layer.
class PagedListController<T> extends ChangeNotifier {
  PagedListController(this._fetch, {this.pageSize = 20});

  final PagedFetcher<T> _fetch;
  final int pageSize;

  final List<T> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  int? _nextCursor;

  DateTime? _from;
  DateTime? _to;
  String _search = '';

  List<T> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  int get total => _total;
  bool get hasMore => _nextCursor != null;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;
  DateTime? get from => _from;
  DateTime? get to => _to;
  String get search => _search;
  bool get hasDateRange => _from != null || _to != null;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _fetch(
        cursor: null,
        limit: pageSize,
        from: _from,
        to: _to,
        search: _search,
      );
      _items
        ..clear()
        ..addAll(page.items);
      _total = page.total;
      _nextCursor = page.nextCursor;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _loading || _nextCursor == null) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final page = await _fetch(
        cursor: _nextCursor,
        limit: pageSize,
        from: _from,
        to: _to,
        search: _search,
      );
      _items.addAll(page.items);
      _total = page.total;
      _nextCursor = page.nextCursor;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> setSearch(String value) async {
    _search = value;
    await refresh();
  }

  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    _from = from;
    _to = to;
    await refresh();
  }

  Future<void> clearDateRange() async {
    _from = null;
    _to = null;
    await refresh();
  }
}
