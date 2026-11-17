import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../../../shared/formatters.dart';
import '../../../shared/gym_passes/gym_pass.dart';
import '../../../shared/gym_passes/gym_passes_flag.dart';

class CheckinList extends StatelessWidget {
  const CheckinList({
    super.key,
    required this.checkins,
    this.limit = 5,
    this.passNames = const {},
  });

  final List<CheckIn> checkins;

  /// Gym pass names by purchase id; labels visits made with a pass.
  final Map<String, String> passNames;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final items = checkins.take(limit).toList();
    if (items.isEmpty) {
      return FFEmptyState(title: context.tr('member.noData'));
    }
    return Column(
      children: items.map((c) {
        final gymName = c.gym?.name ?? c.gymId ?? '';
        final when = context.localDateTimeText(c.timestamp, fallback: '');
        final pass = gymPassVisitLabel(
          FFLocaleScope.of(context),
          passPurchaseId: c.passPurchaseId,
          names: passNames,
          enabled: gymCustomPassesEnabled,
        );
        return FFActionTile(
          icon: Icons.check_circle_outline,
          title: gymName,
          subtitle: pass == null ? when : '$when · $pass',
          onTap: () {},
        );
      }).toList(),
    );
  }
}
