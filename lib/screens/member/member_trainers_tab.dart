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

  // The filter value matches trainers' specialties; the label is translated.
  static const _specialtyLabels = {
    'Weights': 'trainer.specialty.weights',
    'Cardio': 'trainerReg.specialty_cardio',
    'Yoga': 'trainerReg.specialty_yoga',
    'Boxing': 'trainerReg.specialty_boxing',
  };

  @override
  void initState() {
    super.initState();
    // The trainer catalogue can be populated just after an authenticated
    // session is established. Refresh it whenever the directory opens so a
    // stale initial request never leaves it empty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.findAncestorStateOfType<MemberShellState>()?.refreshTrainers();
    });
  }

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

  /// Returns the responsive column count based on available width.
  int _crossAxisCount(double width) {
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final trainers = _filtered(data.trainers);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _crossAxisCount(constraints.maxWidth);

        return CustomScrollView(
          key: const Key('trainer-page-scroll'),
          slivers: [
            // ── Header + controls ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FFPageHeader(title: context.tr('member.findTrainerTitle')),
                    TextField(
                      key: const Key('trainer-search'),
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
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusLg,
                          ),
                        ),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 12),
                    // ── Specialty filter chips ─────────────────────────
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _specialtyFilters.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final selected = _filter == _specialtyFilters[i];
                          final label = _specialtyFilters[i] == 'all'
                              ? context.tr('member.all')
                              : context.tr(
                                  _specialtyLabels[_specialtyFilters[i]]!,
                                );
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _filter = _specialtyFilters[i]),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selected ? cs.primary : cs.surface,
                                border: Border.all(
                                  color: selected ? cs.primary : cs.outline,
                                ),
                                borderRadius: BorderRadius.circular(
                                  FFTokens.radiusXl,
                                ),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: selected ? cs.onPrimary : cs.onSurface,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Section header with shade separation ─────────────────────
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.symmetric(
                  horizontal: FFTokens.spacingLg,
                  vertical: 10,
                ),
                color: cs.surfaceContainerLow,
                child: Row(
                  children: [
                    Text(
                      context.tr('member.topRated'),
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (trainers.isNotEmpty)
                      Text(
                        '${trainers.length}',
                        style: tt.bodySmall?.copyWith(color: cs.primary),
                      ),
                  ],
                ),
              ),
            ),

            // ── Grid ──────────────────────────────────────────────────────
            if (trainers.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: FFEmptyState(title: context.tr('member.noData')),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => TrainerGridCard(
                      key: Key('trainer-card-${trainers[i].id}'),
                      trainer: trainers[i],
                    ),
                    childCount: trainers.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: FFTokens.spacingMd,
                    mainAxisSpacing: FFTokens.spacingMd,
                    childAspectRatio: 0.68,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
