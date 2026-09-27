import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import 'trainer_passes_page.dart';

/// Friendly text for trainer pass / plan API errors.
String trainerPassErrorText(BuildContext context, Object error) {
  final code = (error is ApiException && error.body is Map)
      ? (error.body as Map)['error']?.toString()
      : null;
  const known = {
    'period_required',
    'trainer_pass_period_not_offered',
    'trainer_pass_pending',
    'trainer_pass_already_active',
    'trainer_pass_not_offered',
    'home_gym_free',
    'use_trainer_pass',
    'plan_already_held',
    'invalid_plan',
    'not_cancellable',
  };
  return known.contains(code)
      ? context.tr('trainerPass.error.$code')
      : context.tr('owner.errorGeneric');
}

/// Trainer › Gyms: every active gym with how this trainer can train there —
/// free (linked gym), a trainer pass the owner sells, or the gym's member
/// plans — plus gym join requests and the trainer's passes.
class TrainerGymsTab extends StatefulWidget {
  const TrainerGymsTab({super.key, this.onProfileChanged});

  /// Called after a join request is sent or withdrawn.
  final VoidCallback? onProfileChanged;

  @override
  State<TrainerGymsTab> createState() => TrainerGymsTabState();
}

class TrainerGymsTabState extends State<TrainerGymsTab> {
  List<Map<String, dynamic>> _gyms = [];
  Set<String> _pendingGymIds = {};
  bool _loading = true;
  bool _started = false;
  String? _error;
  String _filter = 'all';
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    refresh();
  }

  Future<void> refresh() async {
    final api = AppScope.of(context).api;
    try {
      final results = await Future.wait([api.trainerGyms(), api.trainerMe()]);
      if (!mounted) return;
      final me = results[1] as Map<String, dynamic>;
      setState(() {
        _gyms = (results[0] as List).whereType<Map<String, dynamic>>().toList();
        _pendingGymIds = ((me['pendingGymIds'] as List?) ?? const [])
            .map((id) => id.toString())
            .toSet();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('owner.errorGeneric');
      });
    }
  }

  static String accessOf(Map<String, dynamic> gym) =>
      (gym['trainerAccess'] as Map?)?['access']?.toString() ?? 'unavailable';

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _gyms.where((g) {
      final access = accessOf(g);
      final matchesFilter = switch (_filter) {
        'free' => access == 'home',
        'pass' => access == 'trainer_pass',
        'plan' => access == 'member_plan',
        _ => true,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return '${g['name']} ${g['location']}'.toLowerCase().contains(q);
    }).toList()..sort((a, b) {
      // Home gyms first, then gyms the trainer can get into.
      int rank(Map<String, dynamic> g) => switch (accessOf(g)) {
        'home' => 0,
        'trainer_pass' => 1,
        'member_plan' => 2,
        _ => 3,
      };
      return rank(a).compareTo(rank(b));
    });
  }

  int get _openPassCount => _gyms.where((g) => g['currentPass'] is Map).length;

  Future<void> _openPasses() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TrainerPassesPage()));
    if (mounted) refresh();
  }

  Future<void> _openGym(Map<String, dynamic> gym) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TrainerGymSheet(
        gym: gym,
        joinPending: _pendingGymIds.contains(gym['id']?.toString()),
      ),
    );
    if (changed == true && mounted) {
      await refresh();
      widget.onProfileChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('trainer.gyms'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Badge(
              isLabelVisible: _openPassCount > 0,
              label: Text('$_openPassCount'),
              child: OutlinedButton.icon(
                key: const Key('trainer-my-passes'),
                onPressed: _openPasses,
                icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                label: Text(context.tr('trainerPass.myPasses')),
              ),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FFTextField(
          key: const Key('trainer-gym-search'),
          hint: context.tr('member.searchGyms'),
          prefixIcon: const Icon(Icons.search),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: FFSegmented(
            key: const Key('trainer-gym-filter'),
            value: _filter,
            options: [
              ('all', context.tr('trainerPass.filterAll')),
              ('free', context.tr('trainerPass.filterFree')),
              ('pass', context.tr('trainerPass.filterPass')),
              ('plan', context.tr('trainerPass.filterPlan')),
            ],
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: FFSpinner(size: 28)),
          )
        else if (_error != null)
          FFAlert(message: _error!, tone: FFAlertTone.error)
        else if (visible.isEmpty)
          FFEmptyState(title: context.tr('member.noData'))
        else
          ...visible.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: _GymCard(
                gym: g,
                joinPending: _pendingGymIds.contains(g['id']?.toString()),
                onTap: () => _openGym(g),
              ),
            ),
          ),
      ],
    );
  }
}

/// The badge text + tone for how a trainer gets into a gym.
(String, FFBadgeTone) trainerAccessBadge(
  BuildContext context,
  Map<String, dynamic> gym,
) {
  final access = TrainerGymsTabState.accessOf(gym);
  final options = ((gym['trainerAccess'] as Map?)?['options'] as List? ?? [])
      .whereType<Map>()
      .toList();
  final cheapest = options.isEmpty
      ? null
      : options
            .map((o) => (o['feeTzs'] as num?) ?? 0)
            .reduce((a, b) => a < b ? a : b);
  final from = cheapest == null ? '' : formatCurrency(cheapest);
  return switch (access) {
    'home' => (context.tr('trainerPass.badgeHome'), FFBadgeTone.success),
    'trainer_pass' => (
      context.tr('trainerPass.badgePass').replaceAll('{price}', from),
      FFBadgeTone.brand,
    ),
    'member_plan' => (
      context.tr('trainerPass.badgePlan').replaceAll('{price}', from),
      FFBadgeTone.warning,
    ),
    _ => (context.tr('trainerPass.badgeUnavailable'), FFBadgeTone.gray),
  };
}

class _GymCard extends StatelessWidget {
  const _GymCard({
    required this.gym,
    required this.joinPending,
    required this.onTap,
  });

  final Map<String, dynamic> gym;
  final bool joinPending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = trainerAccessBadge(context, gym);
    final current = gym['currentPass'] as Map?;
    final thumb =
        (gym['thumbnails'] as List?)?.whereType<String>().firstOrNull ??
        (gym['images'] as List?)?.whereType<String>().firstOrNull;
    return InkWell(
      key: Key('trainer-gym-${gym['id']}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: FFCard(
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: thumb == null
                    ? const ColoredBox(
                        color: FFTokens.brand50,
                        child: Icon(
                          Icons.fitness_center,
                          color: FFTokens.brand500,
                        ),
                      )
                    : FFRemoteImage(src: thumb, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gym['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if ((gym['location']?.toString() ?? '').isNotEmpty)
                    Text(
                      gym['location'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      FFBadge(label: label, tone: tone),
                      if (current != null)
                        FFBadge(
                          label: context.tr(
                            current['status'] == 'active'
                                ? 'trainerPass.statusActive'
                                : 'trainerPass.statusPending',
                          ),
                          tone: current['status'] == 'active'
                              ? FFBadgeTone.success
                              : FFBadgeTone.warning,
                        ),
                      if (joinPending)
                        FFBadge(
                          label: context.tr('trainer.pendingApprovalAtGym'),
                          tone: FFBadgeTone.gray,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// Gym detail for a trainer: how they can train here, and the pass / plan
/// options to buy. Pops `true` when something changed.
class TrainerGymSheet extends StatefulWidget {
  const TrainerGymSheet({
    super.key,
    required this.gym,
    this.joinPending = false,
  });

  final Map<String, dynamic> gym;
  final bool joinPending;

  @override
  State<TrainerGymSheet> createState() => _TrainerGymSheetState();
}

class _TrainerGymSheetState extends State<TrainerGymSheet> {
  String? _period;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get gym => widget.gym;
  String get _access => TrainerGymsTabState.accessOf(gym);
  List<Map> get _options =>
      ((gym['trainerAccess'] as Map?)?['options'] as List? ?? [])
          .whereType<Map>()
          .toList();

  @override
  void initState() {
    super.initState();
    _period = _options.firstOrNull?['period']?.toString();
  }

  Future<void> _run(Future<void> Function() action, String doneKey) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr(doneKey))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = trainerPassErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy() async {
    final option = _options.firstWhere((o) => o['period'] == _period);
    final isPass = _access == 'trainer_pass';
    final price = formatCurrency((option['feeTzs'] as num?) ?? 0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          ctx.tr(
            isPass
                ? 'trainerPass.confirmPassTitle'
                : 'trainerPass.confirmPlanTitle',
          ),
        ),
        content: Text(
          ctx
              .tr('trainerPass.confirmBody')
              .replaceAll('{period}', ctx.tr('trainerPass.period.$_period'))
              .replaceAll('{gym}', gym['name']?.toString() ?? '')
              .replaceAll('{price}', price),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('member.cancel')),
          ),
          FilledButton(
            key: const Key('trainer-pass-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('trainerPass.request')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = AppScope.of(context).api;
    final gymId = gym['id'].toString();
    await _run(
      () => isPass
          ? api.trainerBuyPass(gymId, period: _period)
          : api.trainerBuyMemberPlan(gymId, _period!),
      'trainer.passRequested',
    );
  }

  Future<void> _cancelPending(String subscriptionId) => _run(
    () => AppScope.of(context).api.trainerCancelPass(subscriptionId),
    'trainerPass.cancelled',
  );

  Future<void> _applyToJoin() => _run(
    () => AppScope.of(context).api.trainerApplyToGym(gym['id'].toString()),
    'trainer.applicationSent',
  );

  Future<void> _cancelJoin() => _run(
    () => AppScope.of(
      context,
    ).api.trainerCancelGymApplication(gym['id'].toString()),
    'trainer.applicationCancelled',
  );

  @override
  Widget build(BuildContext context) {
    final current = gym['currentPass'] as Map?;
    final (label, tone) = trainerAccessBadge(context, gym);
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          FFTokens.spacingLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gym['name']?.toString() ?? '',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if ((gym['location']?.toString() ?? '').isNotEmpty)
              Text(gym['location'].toString(), style: textTheme.bodySmall),
            const SizedBox(height: 8),
            FFBadge(label: label, tone: tone),
            const SizedBox(height: 12),
            Text(
              context.tr('trainerPass.explain.$_access'),
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (current != null)
              _currentPassCard(context, current)
            else if (_options.isNotEmpty)
              ..._optionPicker(context),
            if (_error != null) ...[
              const SizedBox(height: 8),
              FFAlert(message: _error!, tone: FFAlertTone.error),
            ],
            if (_access != 'home') ...[
              const Divider(height: 32),
              Text(
                context.tr('trainerPass.joinTitle'),
                style: textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('trainerPass.joinBody'),
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (widget.joinPending)
                OutlinedButton(
                  key: const Key('trainer-gym-cancel-join'),
                  onPressed: _busy ? null : _cancelJoin,
                  child: Text(context.tr('trainerPass.cancelJoin')),
                )
              else
                OutlinedButton.icon(
                  key: const Key('trainer-gym-apply'),
                  onPressed: _busy ? null : _applyToJoin,
                  icon: const Icon(Icons.handshake_outlined, size: 18),
                  label: Text(context.tr('trainer.apply')),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _currentPassCard(BuildContext context, Map current) {
    final active = current['status'] == 'active';
    final until = current['expiresAt']?.toString().split('T').first ?? '';
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              active ? 'trainerPass.statusActive' : 'trainerPass.statusPending',
            ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            active
                ? context
                      .tr('trainerPass.activeUntil')
                      .replaceAll('{date}', until)
                : context.tr('trainerPass.pendingBody'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (active)
            FilledButton.icon(
              key: const Key('trainer-gym-show-qr'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TrainerQrPage()),
              ),
              icon: const Icon(Icons.qr_code_2),
              label: Text(context.tr('trainerPass.showQr')),
            )
          else
            OutlinedButton(
              key: const Key('trainer-gym-cancel-pass'),
              onPressed: _busy
                  ? null
                  : () => _cancelPending(current['id'].toString()),
              child: Text(context.tr('trainerPass.cancelRequest')),
            ),
        ],
      ),
    );
  }

  List<Widget> _optionPicker(BuildContext context) {
    final isPass = _access == 'trainer_pass';
    return [
      ..._options.map((o) {
        final period = o['period']?.toString() ?? '';
        final selected = period == _period;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            key: Key('trainer-pass-option-$period'),
            onTap: () => setState(() => _period = period),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? FFTokens.brand500
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? FFTokens.brand500 : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('trainerPass.period.$period')),
                  ),
                  Text(
                    formatCurrency((o['feeTzs'] as num?) ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
      const SizedBox(height: 4),
      Text(
        context.tr('trainerPass.paymentNote'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('trainer-pass-buy'),
          onPressed: _busy || _period == null ? null : _buy,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  context.tr(
                    isPass ? 'trainerPass.getPass' : 'trainerPass.getPlan',
                  ),
                ),
        ),
      ),
    ];
  }
}
