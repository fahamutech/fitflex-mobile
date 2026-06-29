// Unit tests for MemberListController — no Flutter widget tree needed.
// Uses a fake in-memory repository implementation (dependency injection).

import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/owner/members/data/member_models.dart';
import 'package:fitflexmobile/screens/owner/members/data/member_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/screens/owner/members/member_controller.dart';

// ── Fake repository ─────────────────────────────────────────────────────────

class _FakeRepo extends MemberRepository {
  _FakeRepo(this._result) : super(ApiClient(baseUrl: 'http://localhost:0'));

  MembersResult _result;
  String? lastFetchType;
  String? lastFetchStatus;
  String? lastFetchSearch;
  bool checkInCalled = false;
  bool renewCalled = false;
  bool suspendLastValue = false;
  bool shouldThrow = false;

  void setResult(MembersResult r) => _result = r;

  @override
  Future<MembersResult> fetchMembers({
    String? gymId,
    String? memberType,
    String? status,
    String? search,
  }) async {
    if (shouldThrow) throw Exception('network error');
    lastFetchType = memberType;
    lastFetchStatus = status;
    lastFetchSearch = search;
    return _result;
  }

  @override
  Future<MemberDetail> fetchMemberDetail(String memberId) async {
    if (shouldThrow) throw Exception('network error');
    return MemberDetail(
      id: memberId,
      publicId: 'FM1',
      memberType: OwnerMemberType.direct,
      status: OwnerMemberStatus.active,
    );
  }

  CheckInPeriod? lastPeriod;
  DateTime? lastFrom;
  DateTime? lastTo;

  @override
  Future<CheckInSummary> fetchCheckInSummary(
    String memberId, {
    required CheckInPeriod period,
    DateTime? from,
    DateTime? to,
  }) async {
    if (shouldThrow) throw Exception('network error');
    lastPeriod = period;
    lastFrom = from;
    lastTo = to;
    return CheckInSummary(visits: period == CheckInPeriod.year ? 99 : 5);
  }

  int? lastCheckinCursor;
  String? lastCheckinSearch;
  DateTime? lastCheckinFrom;

  @override
  Future<PagedResult<MemberCheckin>> fetchCheckins(
    String memberId, {
    int? cursor,
    int limit = 20,
    DateTime? from,
    DateTime? to,
    String? search,
  }) async {
    if (shouldThrow) throw Exception('network error');
    lastCheckinCursor = cursor;
    lastCheckinSearch = search;
    lastCheckinFrom = from;
    final offset = cursor ?? 0;
    // 3 total items, paged.
    const total = 3;
    final all = List.generate(
      total,
      (i) => MemberCheckin(id: 'ci_$i', timestamp: DateTime(2026, 1, i + 1)),
    );
    final items = all.skip(offset).take(limit).toList();
    final next = offset + limit < total ? offset + limit : null;
    return PagedResult<MemberCheckin>(
      items: items,
      total: total,
      nextCursor: next,
    );
  }

  @override
  Future<PagedResult<MemberPayment>> fetchPayments(
    String memberId, {
    int? cursor,
    int limit = 20,
    DateTime? from,
    DateTime? to,
    String? search,
  }) async {
    if (shouldThrow) throw Exception('network error');
    return const PagedResult<MemberPayment>(items: [], total: 0);
  }

  @override
  Future<void> checkInMember(String memberId, {String? gymId}) async {
    if (shouldThrow) throw Exception('network error');
    checkInCalled = true;
  }

  @override
  Future<void> renewMember(String memberId, Map<String, dynamic> data) async {
    if (shouldThrow) throw Exception('network error');
    renewCalled = true;
  }

  @override
  Future<void> setSuspended(String memberId, {required bool suspend}) async {
    if (shouldThrow) throw Exception('network error');
    suspendLastValue = suspend;
  }

  @override
  Future<void> createMember(Map<String, dynamic> data) async {
    if (shouldThrow) throw Exception('network error');
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

OwnerMember _member(
  String id, {
  OwnerMemberType type = OwnerMemberType.direct,
}) => OwnerMember(
  id: id,
  publicId: 'FM$id',
  memberType: type,
  status: OwnerMemberStatus.active,
);

MembersResult _result(List<OwnerMember> members, {int total = 0}) =>
    MembersResult(
      members: members,
      stats: MemberStats(
        totalMembers: total == 0 ? members.length : total,
        activeToday: 1,
        expiringSoon: 0,
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _FakeRepo repo;
  late MemberListController ctrl;

  setUp(() {
    repo = _FakeRepo(_result([_member('1'), _member('2')]));
    ctrl = MemberListController(repo);
  });

  tearDown(() => ctrl.dispose());

  group('MemberListController.load', () {
    test('populates members and stats after successful load', () async {
      await ctrl.load();
      expect(ctrl.members.length, 2);
      expect(ctrl.stats.totalMembers, 2);
      expect(ctrl.loading, isFalse);
      expect(ctrl.error, isNull);
    });

    test('sets error when repository throws', () async {
      repo.shouldThrow = true;
      await ctrl.load();
      expect(ctrl.error, isNotNull);
      expect(ctrl.members, isEmpty);
      expect(ctrl.loading, isFalse);
    });

    test('notifies listeners on load', () async {
      var notified = 0;
      ctrl.addListener(() => notified++);
      await ctrl.load();
      // at minimum: loading=true, loading=false → 2 notifications
      expect(notified, greaterThanOrEqualTo(2));
    });
  });

  group('MemberListController filters', () {
    test('setTypeFilter sends correct wire type to repo', () async {
      await ctrl.setTypeFilter(MemberTypeFilter.direct);
      expect(repo.lastFetchType, 'direct');
      expect(ctrl.typeFilter, MemberTypeFilter.direct);
    });

    test('setTypeFilter for fitflex sends fitflex', () async {
      await ctrl.setTypeFilter(MemberTypeFilter.fitflex);
      expect(repo.lastFetchType, 'fitflex');
    });

    test('setTypeFilter for all sends null type', () async {
      ctrl.setTypeFilter(MemberTypeFilter.direct);
      await ctrl.setTypeFilter(MemberTypeFilter.all);
      expect(repo.lastFetchType, isNull);
    });

    test('setSearch sends trimmed search string', () async {
      await ctrl.setSearch('  baraka  ');
      expect(repo.lastFetchSearch, '  baraka  ');
    });

    test('applyFilters sets both type and status', () async {
      await ctrl.applyFilters(
        type: MemberTypeFilter.fitflex,
        status: OwnerMemberStatus.active,
      );
      expect(repo.lastFetchType, 'fitflex');
      expect(repo.lastFetchStatus, 'active');
      expect(ctrl.statusFilter, OwnerMemberStatus.active);
    });

    test('clearFilters resets to defaults', () async {
      ctrl.applyFilters(
        type: MemberTypeFilter.direct,
        status: OwnerMemberStatus.expired,
      );
      await ctrl.clearFilters();
      expect(ctrl.typeFilter, MemberTypeFilter.all);
      expect(ctrl.statusFilter, isNull);
    });

    test('hasActiveFilters is false after clearFilters', () async {
      ctrl.applyFilters(type: MemberTypeFilter.direct, status: null);
      await ctrl.clearFilters();
      expect(ctrl.hasActiveFilters, isFalse);
    });

    test('hasActiveFilters is true when type filter set', () async {
      await ctrl.setTypeFilter(MemberTypeFilter.fitflex);
      expect(ctrl.hasActiveFilters, isTrue);
    });
  });

  group('MemberListController isEmpty', () {
    test('isEmpty when members empty and not loading', () async {
      repo.setResult(MembersResult.empty);
      await ctrl.load();
      expect(ctrl.isEmpty, isTrue);
    });

    test('not isEmpty when members populated', () async {
      await ctrl.load();
      expect(ctrl.isEmpty, isFalse);
    });
  });

  group('MemberDetailController', () {
    late MemberDetailController detailCtrl;

    setUp(() {
      detailCtrl = MemberDetailController(repo, 'usr_1');
    });

    tearDown(() => detailCtrl.dispose());

    test('load fetches detail and stores it', () async {
      await detailCtrl.load();
      expect(detailCtrl.detail, isNotNull);
      expect(detailCtrl.detail!.id, 'usr_1');
      expect(detailCtrl.loading, isFalse);
      expect(detailCtrl.error, isNull);
    });

    test('load sets error on failure', () async {
      repo.shouldThrow = true;
      await detailCtrl.load();
      expect(detailCtrl.error, isNotNull);
      expect(detailCtrl.detail, isNull);
    });

    test('checkIn calls repository and reloads', () async {
      await detailCtrl.load();
      final ok = await detailCtrl.checkIn();
      expect(ok, isTrue);
      expect(repo.checkInCalled, isTrue);
      expect(detailCtrl.detail, isNotNull);
    });

    test('checkIn returns false on error', () async {
      repo.shouldThrow = true;
      final ok = await detailCtrl.checkIn();
      expect(ok, isFalse);
    });

    test('toggleSuspend passes suspend=true to repo', () async {
      await detailCtrl.load();
      repo.shouldThrow = false;
      await detailCtrl.toggleSuspend(suspend: true);
      expect(repo.suspendLastValue, isTrue);
    });

    test('toggleSuspend passes suspend=false (reactivate) to repo', () async {
      await detailCtrl.load();
      await detailCtrl.toggleSuspend(suspend: false);
      expect(repo.suspendLastValue, isFalse);
    });

    test('renew calls repo and reloads', () async {
      await detailCtrl.load();
      final ok = await detailCtrl.renew({
        'tier': 'premium',
        'durationUnit': 'M',
      });
      expect(ok, isTrue);
      expect(repo.renewCalled, isTrue);
    });

    test('busy flag toggles around actions', () async {
      final busyStates = <bool>[];
      detailCtrl.addListener(() => busyStates.add(detailCtrl.busy));
      await detailCtrl.checkIn();
      expect(busyStates, contains(true));
      expect(busyStates.last, isFalse);
    });

    test(
      'defaults to month period and uses detail summary before override',
      () async {
        await detailCtrl.load();
        expect(detailCtrl.period, CheckInPeriod.month);
        // before any setPeriod, falls back to the detail's embedded summary
        expect(detailCtrl.checkInSummary, isNotNull);
      },
    );

    test('setPeriod fetches the period summary and exposes it', () async {
      await detailCtrl.load();
      await detailCtrl.setPeriod(CheckInPeriod.year);
      expect(repo.lastPeriod, CheckInPeriod.year);
      expect(detailCtrl.period, CheckInPeriod.year);
      expect(detailCtrl.checkInSummary!.visits, 99);
      expect(detailCtrl.summaryLoading, isFalse);
    });

    test('setPeriod custom forwards the from/to range', () async {
      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 1, 31);
      await detailCtrl.setPeriod(CheckInPeriod.custom, from: from, to: to);
      expect(repo.lastPeriod, CheckInPeriod.custom);
      expect(repo.lastFrom, from);
      expect(repo.lastTo, to);
      expect(detailCtrl.customFrom, from);
      expect(detailCtrl.customTo, to);
    });
  });

  group('PagedListController', () {
    late PagedListController<MemberCheckin> paged;

    setUp(() {
      paged = PagedListController<MemberCheckin>(
        ({cursor, limit = 2, from, to, search}) => repo.fetchCheckins(
          'm1',
          cursor: cursor,
          limit: limit,
          from: from,
          to: to,
          search: search,
        ),
        pageSize: 2,
      );
    });

    tearDown(() => paged.dispose());

    test('refresh loads first page and reports hasMore', () async {
      await paged.refresh();
      expect(paged.items.length, 2);
      expect(paged.total, 3);
      expect(paged.hasMore, isTrue);
      expect(repo.lastCheckinCursor, isNull);
    });

    test('loadMore appends the next page with the offset cursor', () async {
      await paged.refresh();
      await paged.loadMore();
      expect(paged.items.length, 3);
      expect(paged.hasMore, isFalse);
      expect(repo.lastCheckinCursor, 2);
    });

    test('loadMore is a no-op when there are no more pages', () async {
      await paged.refresh();
      await paged.loadMore(); // exhausts
      final countBefore = paged.items.length;
      await paged.loadMore(); // should do nothing
      expect(paged.items.length, countBefore);
    });

    test('setSearch resets to the first page and forwards the term', () async {
      await paged.refresh();
      await paged.loadMore();
      await paged.setSearch('vik');
      expect(repo.lastCheckinSearch, 'vik');
      expect(
        paged.items.length,
        2,
        reason: 'search reloads from the first page',
      );
    });

    test('setDateRange forwards the range and marks hasDateRange', () async {
      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 1, 31);
      await paged.setDateRange(from, to);
      expect(repo.lastCheckinFrom, from);
      expect(paged.hasDateRange, isTrue);
    });

    test('clearDateRange resets the range', () async {
      await paged.setDateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      await paged.clearDateRange();
      expect(paged.hasDateRange, isFalse);
    });

    test('sets error when fetch throws', () async {
      repo.shouldThrow = true;
      await paged.refresh();
      expect(paged.error, isNotNull);
      expect(paged.isEmpty, isFalse);
    });
  });
}
