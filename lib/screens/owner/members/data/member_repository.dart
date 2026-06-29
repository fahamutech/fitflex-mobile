// Repository — the only place that talks to the REST ApiClient for member
// management. Maps raw JSON to typed models so the controller + UI never see
// transport details. This isolates the API/transport concern (clean architecture).

import '../../../../shared/api_client.dart';
import 'member_models.dart';

class MemberRepository {
  MemberRepository(this._api);

  final ApiClient _api;

  Future<MembersResult> fetchMembers({
    String? gymId,
    String? memberType,
    String? status,
    String? search,
  }) async {
    final res = await _api.ownerMembers(
      gymId: gymId,
      memberType: memberType,
      status: status,
      search: search,
    );
    return MembersResult.fromJson(res);
  }

  Future<MemberDetail> fetchMemberDetail(String memberId) async {
    final res = await _api.ownerMemberDetail(memberId);
    return MemberDetail.fromJson(res);
  }

  Future<CheckInSummary> fetchCheckInSummary(
    String memberId, {
    required CheckInPeriod period,
    DateTime? from,
    DateTime? to,
  }) async {
    final res = await _api.ownerMemberCheckInSummary(
      memberId,
      period: period.wire,
      from: from == null ? null : _dateOnly(from),
      to: to == null ? null : _dateOnly(to),
    );
    return CheckInSummary.fromJson(res);
  }

  Future<PagedResult<MemberCheckin>> fetchCheckins(
    String memberId, {
    int? cursor,
    int limit = 20,
    DateTime? from,
    DateTime? to,
    String? search,
  }) async {
    final res = await _api.ownerMemberCheckins(
      memberId,
      cursor: cursor,
      limit: limit,
      from: from == null ? null : _dateOnly(from),
      to: to == null ? null : _dateOnly(to),
      search: search,
    );
    return PagedResult.fromJson(res, MemberCheckin.fromJson);
  }

  Future<PagedResult<MemberPayment>> fetchPayments(
    String memberId, {
    int? cursor,
    int limit = 20,
    DateTime? from,
    DateTime? to,
    String? search,
  }) async {
    final res = await _api.ownerMemberPayments(
      memberId,
      cursor: cursor,
      limit: limit,
      from: from == null ? null : _dateOnly(from),
      to: to == null ? null : _dateOnly(to),
      search: search,
    );
    return PagedResult.fromJson(res, MemberPayment.fromJson);
  }

  static String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> createMember(Map<String, dynamic> data) async {
    await _api.ownerCreateMember(data);
  }

  Future<void> updateMember(String memberId, Map<String, dynamic> data) async {
    await _api.ownerUpdateMember(memberId, data);
  }

  Future<void> checkInMember(String memberId, {String? gymId}) async {
    await _api.ownerCheckInMember(memberId, gymId: gymId);
  }

  Future<void> renewMember(String memberId, Map<String, dynamic> data) async {
    await _api.ownerRenewMember(memberId, data);
  }

  Future<void> setSuspended(String memberId, {required bool suspend}) async {
    await _api.ownerSuspendMember(memberId, suspend: suspend);
  }
}
