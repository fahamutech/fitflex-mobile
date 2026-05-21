import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import 'widgets/trainer_card.dart';

class MemberTrainersTab extends StatefulWidget {
  const MemberTrainersTab({super.key});

  @override
  State<MemberTrainersTab> createState() => _MemberTrainersTabState();
}

class _MemberTrainersTabState extends State<MemberTrainersTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _filter = 'all';

  static const _specialtyFilters = [
    'all',
    'Weights',
    'Cardio',
    'Yoga',
    'Boxing',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _norm(Object? v) => v?.toString().trim().toLowerCase() ?? '';

  List<TrainerProfile> _filtered(List<TrainerProfile> trainers) {
    var result = trainers;
    final q = _norm(_search);
    if (q.isNotEmpty) {
      result = result
          .where(
            (t) =>
                _norm(t.displayName).contains(q) ||
                _norm(t.bio).contains(q) ||
                t.specialties.any((s) => _norm(s).contains(q)) ||
                t.gyms.any(
                  (g) =>
                      _norm(g.name).contains(q) ||
                      _norm(g.location).contains(q),
                ),
          )
          .toList();
    }
    if (_filter != 'all') {
      final f = _norm(_filter).replaceAll(' ', '');
      result = result
          .where(
            (t) => t.specialties.any(
              (s) => _norm(s).replaceAll(' ', '').contains(f),
            ),
          )
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final trainers = _filtered(data.trainers);

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFPageHeader(title: context.tr('member.findTrainerTitle')),
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: context.tr('member.searchTrainers'),
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
            itemCount: _specialtyFilters.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = _filter == _specialtyFilters[i];
              final label = _specialtyFilters[i] == 'all'
                  ? context.tr('member.all')
                  : _specialtyFilters[i];
              return GestureDetector(
                onTap: () => setState(() => _filter = _specialtyFilters[i]),
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
                    label,
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
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 10),
          child: Text(
            context.tr('member.topRated'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
            ),
          ),
        ),
        if (trainers.isEmpty)
          FFEmptyState(title: context.tr('member.noData'))
        else
          ...trainers.map((t) => TrainerCard(trainer: t)),
      ],
    );
  }
}
