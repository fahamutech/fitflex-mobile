import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/discovery_loader.dart';
import '../../shared/promotion_events.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/promotion.dart';
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

  /// The server's ranked answer for the current search and specialty: a
  /// Featured section and the results below it. Null until it arrives, or if
  /// the server cannot be reached, in which case the plain list is filtered on
  /// the phone as before.
  DiscoverResult<TrainerProfile>? _discovery;
  bool _discoveryLoading = false;
  late final DiscoveryLoader<TrainerProfile> _loader =
      DiscoveryLoader<TrainerProfile>(
        fetch: (q) async => DiscoverResult.fromJson<TrainerProfile>(
          await AppScope.of(
            context,
          ).api.discover('trainers', q.withSession(discoverSessionId())),
          TrainerProfile.fromJson,
        ),
        onResult: (r) {
          if (mounted) setState(() => _discovery = r);
        },
        onLoading: (v) {
          if (mounted) setState(() => _discoveryLoading = v);
        },
      );

  void _requestDiscovery({bool immediate = false}) => _loader.request(
    DiscoverQuery(
      q: _search,
      filters: {if (_filter != 'all') 'specialty': _norm(_filter)},
      limit: 50,
    ),
    immediate: immediate,
  );

  static const _specialtyFilters = [
    'all',
    'Weights',
    'Cardio',
    'Yoga',
    'Boxing',
  ];

  @override
  void initState() {
    super.initState();
    // The trainer catalogue can be populated just after an authenticated
    // session is established. Refresh it whenever the directory opens so a
    // stale initial request never leaves it empty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.findAncestorStateOfType<MemberShellState>()?.refreshTrainers();
      _requestDiscovery(immediate: true);
    });
  }

  @override
  void dispose() {
    _loader.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _norm(Object? v) => v?.toString().trim().toLowerCase() ?? '';

  /// The server's ranked list when there is one (search and specialty already
  /// applied), otherwise the full list filtered here.
  List<TrainerProfile> _filtered(List<TrainerProfile> trainers) =>
      _discovery?.items ?? _plainFiltered(trainers);

  List<TrainerProfile> _plainFiltered(List<TrainerProfile> trainers) {
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
    final featured = _discovery?.featured ?? const <TrainerProfile>[];
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
                                  _requestDiscovery(immediate: true);
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusLg,
                          ),
                        ),
                      ),
                      onChanged: (v) {
                        setState(() => _search = v);
                        _requestDiscovery();
                      },
                    ),
                    if (_discoveryLoading)
                      const LinearProgressIndicator(minHeight: 2),
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
                              : _specialtyFilters[i];
                          return GestureDetector(
                            onTap: () {
                              setState(() => _filter = _specialtyFilters[i]);
                              _requestDiscovery(immediate: true);
                            },
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

            // ── Featured (labelled; only trainers that match this search) ──
            SliverToBoxAdapter(
              child: FFFeaturedStrip(
                title: context.tr('member.featuredTrainers'),
                count: featured.length,
                height: 270,
                itemBuilder: (context, i) => TrainerGridCard(
                  key: Key('trainer-featured-${featured[i].id}'),
                  trainer: featured[i],
                  placement: _discovery?.placement,
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
            if (trainers.isEmpty && featured.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: FFEmptyState(title: context.tr('member.noData')),
                ),
              )
            else if (trainers.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => TrainerGridCard(
                      key: Key('trainer-card-${trainers[i].id}'),
                      trainer: trainers[i],
                      placement: _discovery?.placement,
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
