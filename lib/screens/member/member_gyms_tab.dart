import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import 'widgets/gym_card.dart';

class MemberGymsTab extends StatefulWidget {
  const MemberGymsTab({super.key});

  @override
  State<MemberGymsTab> createState() => _MemberGymsTabState();
}

class _MemberGymsTabState extends State<MemberGymsTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _filter = 'all';

  static const _filters = ['all', 'nearest', 'standard', 'midtier', 'premium'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _norm(Object? v) => v?.toString().trim().toLowerCase() ?? '';

  String _gymTierKey(Gym gym) {
    final t = _norm(gym.tier).replaceAll('-', '_').replaceAll(' ', '_');
    if (t == 'mid_tier' || t == 'midrange' || t == 'mid_range') {
      return 'midtier';
    }
    if (t == 'luxury' || t == 'executive') {
      return 'luxury_executive';
    }
    return t;
  }

  List<Gym> _filtered(List<Gym> gyms) {
    var result = gyms;
    final q = _norm(_search);
    if (q.isNotEmpty) {
      result = result
          .where(
            (g) =>
                _norm(g.name).contains(q) ||
                _norm(g.location).contains(q) ||
                _norm(g.tier).contains(q) ||
                g.amenities.any((a) => _norm(a).contains(q)) ||
                g.equipment.any((e) => _norm(e).contains(q)),
          )
          .toList();
    }
    if (_filter == 'standard') {
      result = result.where((g) => _gymTierKey(g) == 'standard').toList();
    } else if (_filter == 'midtier') {
      result = result.where((g) => _gymTierKey(g) == 'midtier').toList();
    } else if (_filter == 'premium') {
      result = result.where((g) {
        final t = _gymTierKey(g);
        return t == 'premium' || t == 'luxury_executive';
      }).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final gyms = _filtered(data.gyms);

    final filterLabels = [
      context.tr('member.all'),
      context.tr('member.nearest'),
      'Standard',
      'Mid-Range',
      'Premium',
    ];

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFPageHeader(title: context.tr('member.discoverGyms')),
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: context.tr('member.searchGyms'),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(FFTokens.radiusLg),
            ),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final selected = _filter == _filters[i];
              return GestureDetector(
                onTap: () => setState(() => _filter = _filters[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? FFTokens.brand700 : FFTokens.bgSecondary,
                    border: Border.all(
                      color: selected
                          ? FFTokens.brand700
                          : FFTokens.borderSecondary,
                    ),
                    borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                  ),
                  child: Text(
                    filterLabels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: selected ? Colors.white : FFTokens.fgSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
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
