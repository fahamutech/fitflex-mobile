// Unit tests for the owner member management typed models.
// Pure Dart — no widget tree / Flutter framework needed.

import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/owner/members/data/member_models.dart';

void main() {
  group('OwnerMemberStatus.fromJson', () {
    test('maps known wire values', () {
      expect(OwnerMemberStatus.fromJson('active'), OwnerMemberStatus.active);
      expect(
        OwnerMemberStatus.fromJson('checked_in'),
        OwnerMemberStatus.checkedIn,
      );
      expect(
        OwnerMemberStatus.fromJson('expiring_soon'),
        OwnerMemberStatus.expiringSoon,
      );
      expect(OwnerMemberStatus.fromJson('expired'), OwnerMemberStatus.expired);
      expect(
        OwnerMemberStatus.fromJson('suspended'),
        OwnerMemberStatus.suspended,
      );
    });

    test('defaults to active for unknown / null', () {
      expect(OwnerMemberStatus.fromJson(null), OwnerMemberStatus.active);
      expect(OwnerMemberStatus.fromJson(''), OwnerMemberStatus.active);
      expect(OwnerMemberStatus.fromJson('unknown'), OwnerMemberStatus.active);
    });

    test('wire round-trips correctly', () {
      for (final s in OwnerMemberStatus.values) {
        expect(OwnerMemberStatus.fromJson(s.wire), s);
      }
    });
  });

  group('OwnerMemberType.fromJson', () {
    test('maps fitflex and defaults to direct', () {
      expect(OwnerMemberType.fromJson('fitflex'), OwnerMemberType.fitflex);
      expect(OwnerMemberType.fromJson('direct'), OwnerMemberType.direct);
      expect(OwnerMemberType.fromJson(null), OwnerMemberType.direct);
    });
  });

  group('OwnerMember.fromJson', () {
    test('parses complete member JSON', () {
      final json = <String, dynamic>{
        'id': 'usr_1',
        'publicId': 'FM100',
        'displayName': 'Amina Juma',
        'phone': '+255712345678',
        'memberType': 'direct',
        'tier': 'premium',
        'status': 'active',
        'lastCheckinAt': '2025-01-15T08:30:00Z',
        'startDate': '2025-01-01T00:00:00Z',
        'expiresAt': '2025-02-01T00:00:00Z',
        'daysLeft': 17,
      };
      final m = OwnerMember.fromJson(json);
      expect(m.id, 'usr_1');
      expect(m.publicId, 'FM100');
      expect(m.displayName, 'Amina Juma');
      expect(m.memberType, OwnerMemberType.direct);
      expect(m.tier, 'premium');
      expect(m.status, OwnerMemberStatus.active);
      expect(m.daysLeft, 17);
      expect(m.lastCheckinAt, isNotNull);
    });

    test('resolvedName falls back to publicId when displayName is empty', () {
      final m = OwnerMember.fromJson(<String, dynamic>{
        'id': 'usr_2',
        'publicId': 'FM200',
        'displayName': '',
        'memberType': 'direct',
        'status': 'active',
      });
      expect(m.resolvedName, 'FM200');
    });

    test('handles missing optional fields gracefully', () {
      final m = OwnerMember.fromJson(<String, dynamic>{
        'id': 'x',
        'publicId': 'FM999',
      });
      expect(m.memberType, OwnerMemberType.direct);
      expect(m.status, OwnerMemberStatus.active);
      expect(m.daysLeft, isNull);
      expect(m.lastCheckinAt, isNull);
    });
  });

  group('MemberStats.fromJson', () {
    test('parses numeric fields', () {
      final stats = MemberStats.fromJson(<String, dynamic>{
        'totalMembers': 128,
        'activeToday': 24,
        'expiringSoon': 8,
      });
      expect(stats.totalMembers, 128);
      expect(stats.activeToday, 24);
      expect(stats.expiringSoon, 8);
    });

    test('defaults to zero on missing fields', () {
      final stats = MemberStats.fromJson(<String, dynamic>{});
      expect(stats.totalMembers, 0);
      expect(stats.activeToday, 0);
      expect(stats.expiringSoon, 0);
    });
  });

  group('MembersResult.fromJson', () {
    test('parses members list + stats', () {
      final result = MembersResult.fromJson(<String, dynamic>{
        'members': [
          {
            'id': 'u1',
            'publicId': 'FM1',
            'memberType': 'direct',
            'status': 'active',
          },
          {
            'id': 'u2',
            'publicId': 'FM2',
            'memberType': 'fitflex',
            'status': 'checked_in',
          },
        ],
        'stats': {'totalMembers': 2, 'activeToday': 1, 'expiringSoon': 0},
      });
      expect(result.members.length, 2);
      expect(result.members[0].memberType, OwnerMemberType.direct);
      expect(result.members[1].status, OwnerMemberStatus.checkedIn);
      expect(result.stats.totalMembers, 2);
    });

    test('empty members list when key missing', () {
      final result = MembersResult.fromJson(<String, dynamic>{});
      expect(result.members, isEmpty);
    });
  });

  group('MemberDetail', () {
    test('isSuspended when accountStatus is suspended', () {
      final d = MemberDetail(
        id: 'x',
        publicId: 'FM1',
        memberType: OwnerMemberType.direct,
        status: OwnerMemberStatus.active,
        accountStatus: 'suspended',
      );
      expect(d.isSuspended, isTrue);
    });

    test('isSuspended when status is suspended', () {
      final d = MemberDetail(
        id: 'x',
        publicId: 'FM1',
        memberType: OwnerMemberType.direct,
        status: OwnerMemberStatus.suspended,
        accountStatus: 'active',
      );
      expect(d.isSuspended, isTrue);
    });

    test('not suspended when active', () {
      final d = MemberDetail(
        id: 'x',
        publicId: 'FM1',
        memberType: OwnerMemberType.direct,
        status: OwnerMemberStatus.active,
        accountStatus: 'active',
      );
      expect(d.isSuspended, isFalse);
    });

    test('fromJson parses full detail payload', () {
      final json = <String, dynamic>{
        'id': 'usr_1',
        'publicId': 'FM100',
        'displayName': 'Baraka Ali',
        'email': 'baraka@test.com',
        'phone': '+255712000001',
        'memberType': 'direct',
        'status': 'active',
        'accountStatus': 'active',
        'joinedAt': '2024-12-01T00:00:00Z',
        'checkInSummary': {
          'visits': 5,
          'lastCheckinAt': '2025-01-15T08:00:00Z',
          'streakDays': 3,
        },
        'plan': {
          'tier': 'premium',
          'startDate': '2025-01-01T00:00:00Z',
          'expiresAt': '2025-02-01T00:00:00Z',
          'daysLeft': 17,
          'status': 'active',
        },
        'recentCheckins': [
          {
            'id': 'ci_1',
            'timestamp': '2025-01-15T08:00:00Z',
            'gymName': 'Vik100',
          },
        ],
        'paymentHistory': [
          {
            'id': 'pay_1',
            'amountTzs': 50000,
            'tier': 'premium',
            'status': 'approved',
            'requestedAt': '2025-01-01T00:00:00Z',
          },
        ],
      };
      final detail = MemberDetail.fromJson(json);
      expect(detail.resolvedName, 'Baraka Ali');
      expect(detail.checkInSummary.visits, 5);
      expect(detail.checkInSummary.streakDays, 3);
      expect(detail.plan!.tier, 'premium');
      expect(detail.plan!.daysLeft, 17);
      expect(detail.recentCheckins.length, 1);
      expect(detail.recentCheckins.first.gymName, 'Vik100');
      expect(detail.paymentHistory.length, 1);
      expect(detail.paymentHistory.first.amountTzs, 50000);
    });
  });
}
