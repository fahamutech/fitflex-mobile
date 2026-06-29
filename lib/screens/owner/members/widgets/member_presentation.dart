// Presentation mapping helpers — translate domain enums to design-system
// badge tones, icons and localized labels. Keeps mapping in one place so the
// list + detail screens render statuses identically.

import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/i18n.dart';
import '../data/member_models.dart';

extension OwnerMemberStatusUi on OwnerMemberStatus {
  FFBadgeTone get tone => switch (this) {
    OwnerMemberStatus.active => FFBadgeTone.success,
    OwnerMemberStatus.checkedIn => FFBadgeTone.brand,
    OwnerMemberStatus.expiringSoon => FFBadgeTone.warning,
    OwnerMemberStatus.expired => FFBadgeTone.danger,
    OwnerMemberStatus.suspended => FFBadgeTone.danger,
  };

  String label(BuildContext context) => switch (this) {
    OwnerMemberStatus.active => context.tr('status.active'),
    OwnerMemberStatus.checkedIn => context.tr('status.checkedIn'),
    OwnerMemberStatus.expiringSoon => context.tr('status.expiringSoon'),
    OwnerMemberStatus.expired => context.tr('status.expired'),
    OwnerMemberStatus.suspended => context.tr('status.suspended'),
  };
}

extension OwnerMemberTypeUi on OwnerMemberType {
  IconData get icon => switch (this) {
    OwnerMemberType.direct => Icons.person_outline,
    OwnerMemberType.fitflex => Icons.directions_run,
  };

  String label(BuildContext context) => switch (this) {
    OwnerMemberType.direct => context.tr('memberType.direct'),
    OwnerMemberType.fitflex => context.tr('memberType.fitflex'),
  };
}

/// Badge for a member status using the shared [FFBadge] component.
class MemberStatusBadge extends StatelessWidget {
  const MemberStatusBadge({super.key, required this.status});

  final OwnerMemberStatus status;

  @override
  Widget build(BuildContext context) =>
      FFBadge(label: status.label(context), tone: status.tone, dot: true);
}
