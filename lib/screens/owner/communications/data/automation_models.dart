// Lifecycle automations (M9): a gym's messages that send themselves — the
// welcome, expiry reminders, expired, failed payment and inactivity.

import 'communication_models.dart';

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// What an automation reacts to, in the order owners see them.
const kAutomationTriggers = [
  'payment_failed',
  'membership_expiring',
  'membership_expired',
  'membership_activated',
  'member_inactive',
];

/// Last 30 days of one automation.
class AutomationStats {
  const AutomationStats({
    this.fired = 0,
    this.skipped = 0,
    this.messages = 0,
    this.reached = 0,
    this.failed = 0,
    this.opened = 0,
  });

  /// Members it messaged.
  final int fired;
  final int skipped;
  final int messages;
  final int reached;
  final int failed;
  final int opened;

  factory AutomationStats.fromJson(Map<String, dynamic>? j) => AutomationStats(
    fired: _int(j?['fired']),
    skipped: _int(j?['skipped']),
    messages: _int(j?['messages']),
    reached: _int(j?['reached']),
    failed: _int(j?['failed']),
    opened: _int(j?['opened']),
  );
}

class Automation {
  const Automation({
    required this.id,
    required this.trigger,
    required this.status,
    this.gymId,
    this.name = '',
    this.offsetDays = 0,
    this.channels = const [],
    this.pausedReason,
    this.templateId,
    this.templateKey,
    this.templateName,
    this.templateSystem = false,
    this.stats = const AutomationStats(),
    this.lastRunAt,
  });

  final String id;
  final String? gymId;
  final String name;

  /// membership_activated | membership_expiring | membership_expired |
  /// payment_failed | member_inactive
  final String trigger;

  /// Days before expiry, or days without a visit.
  final int offsetDays;
  final List<CommChannel> channels;

  /// enabled | disabled | paused (paused by the engine, see [pausedReason]).
  final String status;
  final String? pausedReason;
  final String? templateId;
  final String? templateKey;
  final String? templateName;
  final bool templateSystem;
  final AutomationStats stats;
  final DateTime? lastRunAt;

  bool get enabled => status == 'enabled';
  bool get paused => status == 'paused';

  /// Members it would have messaged when it paused itself, if that's why.
  int? get pausedFor {
    final r = pausedReason;
    if (r == null || !r.startsWith('too_many_members:')) return null;
    return int.tryParse(r.split(':').last);
  }

  factory Automation.fromJson(Map<String, dynamic> j) {
    final t = (j['template'] as Map?)?.cast<String, dynamic>();
    return Automation(
      id: j['id'].toString(),
      gymId: j['gymId']?.toString(),
      name: j['name']?.toString() ?? '',
      trigger: j['trigger']?.toString() ?? '',
      offsetDays: _int(j['offsetDays']),
      channels: ((j['channels'] as List?) ?? const [])
          .map((c) => CommChannel.parse(c?.toString()))
          .whereType<CommChannel>()
          .toList(),
      status: j['status']?.toString() ?? 'disabled',
      pausedReason: j['pausedReason']?.toString(),
      templateId: t?['id']?.toString(),
      templateKey: t?['key']?.toString(),
      templateName: t?['name']?.toString(),
      templateSystem: t?['system'] == true,
      stats: AutomationStats.fromJson((j['stats'] as Map?)?.cast()),
      lastRunAt: _date(j['lastRunAt']),
    );
  }
}

/// One time an automation fired for a member.
class AutomationFiring {
  const AutomationFiring({
    required this.id,
    required this.status,
    this.memberId,
    this.memberName,
    this.createdAt,
    this.channels = const [],
  });

  final String id;

  /// queued (messages sent) | skipped (nobody could be reached)
  final String status;
  final String? memberId;
  final String? memberName;
  final DateTime? createdAt;
  final List<
    ({String? id, CommChannel? channel, String status, String? reason})
  >
  channels;

  factory AutomationFiring.fromJson(Map<String, dynamic> j) => AutomationFiring(
    id: j['id'].toString(),
    status: j['status']?.toString() ?? 'queued',
    memberId: j['memberId']?.toString(),
    memberName: j['memberName']?.toString(),
    createdAt: _date(j['createdAt']),
    channels: ((j['channels'] as List?) ?? const []).map((c) {
      final m = (c as Map).cast<String, dynamic>();
      return (
        id: m['id']?.toString(),
        channel: CommChannel.parse(m['channel']?.toString()),
        status: m['status']?.toString() ?? 'queued',
        reason: m['reason']?.toString(),
      );
    }).toList(),
  );
}
