import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';

class CheckinList extends StatelessWidget {
  const CheckinList({super.key, required this.checkins, this.limit = 5});

  final List<CheckIn> checkins;
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
        return FFActionTile(
          icon: Icons.check_circle_outline,
          title: gymName,
          subtitle: c.timestamp,
          onTap: () {},
        );
      }).toList(),
    );
  }
}
