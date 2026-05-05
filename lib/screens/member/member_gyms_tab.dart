import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/gym_card.dart';

class MemberGymsTab extends StatelessWidget {
  const MemberGymsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final gyms = data.gyms;

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFPageHeader(title: context.tr('member.discoverGyms')),
        _SearchBox(hint: context.tr('member.searchGyms')),
        const SizedBox(height: 12),
        FFSegmented(
          value: 'all',
          options: [
            ('all', context.tr('member.all')),
            ('nearest', context.tr('member.nearest')),
            ('open', context.tr('member.openNow')),
          ],
          onChanged: (_) {},
        ),
        const SizedBox(height: 16),
        if (gyms.isEmpty)
          FFEmptyState(title: context.tr('member.noData'))
        else
          ...gyms.map((g) => GymCard(gym: g)),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
      ),
    );
  }
}
