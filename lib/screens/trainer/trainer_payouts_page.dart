// My payouts: a trainer's weekly statements. Each lists the sessions FitFlex
// is paying for that week, what the trainer earns after commission, and where
// it stands (awaiting approval, approved, ready to pay, paid). Read-only: the
// server works out every number. A trainer is paid only once verified with a
// payout account, so the page says when that is still missing.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';

(String, FFBadgeTone) _status(Map<String, dynamic> s) => switch (s['status']) {
  'paid' => ('payouts.status.paid', FFBadgeTone.success),
  'payable' => ('payouts.status.payable', FFBadgeTone.brand),
  'approved' => ('payouts.status.approved', FFBadgeTone.brand),
  _ => ('payouts.status.submitted', FFBadgeTone.warning),
};

String _week(Map<String, dynamic> s) =>
    '${s['periodStartDate']} – ${s['periodEndDate']}';

class TrainerPayoutsPage extends StatefulWidget {
  const TrainerPayoutsPage({super.key});

  @override
  State<TrainerPayoutsPage> createState() => _TrainerPayoutsPageState();
}

class _TrainerPayoutsPageState extends State<TrainerPayoutsPage> {
  List<Map<String, dynamic>>? _statements;
  bool _payoutReady = true;
  Object? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await AppScope.of(context).api.trainerStatements();
      if (!mounted) return;
      setState(() {
        _statements = [
          for (final s in (res['statements'] as List? ?? const []))
            if (s is Map) s.cast<String, dynamic>(),
        ];
        _payoutReady = res['payoutReady'] != false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _statements;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('payouts.title'))),
      body: rows == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('inbox.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                    action: FilledButton(
                      onPressed: _load,
                      child: Text(context.tr('comms.retry')),
                    ),
                  ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  Text(
                    context.tr('payouts.intro'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                  if (!_payoutReady) ...[
                    FFAlert(
                      key: const Key('payouts-not-ready'),
                      tone: FFAlertTone.warning,
                      message: context.tr('payouts.notReady'),
                    ),
                    const SizedBox(height: FFTokens.spacingSm),
                    OutlinedButton(
                      key: const Key('payouts-verify'),
                      onPressed: () => context.push(AppRoutes.verification),
                      child: Text(context.tr('payouts.openVerification')),
                    ),
                    const SizedBox(height: FFTokens.spacingMd),
                  ],
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: FFTokens.spacingLg,
                      ),
                      child: Text(
                        context.tr('payouts.empty'),
                        key: const Key('payouts-empty'),
                      ),
                    )
                  else
                    for (final s in rows) ...[
                      _StatementCard(
                        statement: s,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TrainerPayoutDetailPage(
                              statementId: s['id'].toString(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                    ],
                ],
              ),
            ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.statement, required this.onTap});

  final Map<String, dynamic> statement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (key, tone) = _status(statement);
    final sessions = statement['sessionCount'] as num? ?? 0;
    return InkWell(
      key: Key('payout-${statement['id']}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      child: FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatCurrency(statement['finalNetTzs'] as num? ?? 0),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FFBadge(label: context.tr(key), tone: tone),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_week(statement)} · ${context.tr('payouts.sessions').replaceFirst('{n}', '$sessions')}',
            ),
            if (statement['onHold'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr('payouts.onHold'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One statement with the sessions it pays for.
class TrainerPayoutDetailPage extends StatefulWidget {
  const TrainerPayoutDetailPage({super.key, required this.statementId});

  final String statementId;

  @override
  State<TrainerPayoutDetailPage> createState() =>
      _TrainerPayoutDetailPageState();
}

class _TrainerPayoutDetailPageState extends State<TrainerPayoutDetailPage> {
  Map<String, dynamic>? _data;
  Object? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await AppScope.of(
        context,
      ).api.trainerStatement(widget.statementId);
      if (mounted) setState(() => _data = res);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final s = (data?['statement'] as Map?)?.cast<String, dynamic>();
    final lines = [
      for (final l in (data?['lines'] as List? ?? const []))
        if (l is Map) l.cast<String, dynamic>(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('payouts.statement'))),
      body: s == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('inbox.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                  ))
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatCurrency(s['finalNetTzs'] as num? ?? 0),
                        key: const Key('payout-net'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    FFBadge(
                      label: context.tr(_status(s).$1),
                      tone: _status(s).$2,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_week(s)),
                const SizedBox(height: FFTokens.spacingMd),
                Text(
                  context
                      .tr('payouts.breakdown')
                      .replaceFirst(
                        '{list}',
                        formatCurrency(s['listTzs'] as num? ?? 0),
                      )
                      .replaceFirst(
                        '{commission}',
                        formatCurrency(s['commissionTzs'] as num? ?? 0),
                      ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (s['status'] == 'paid') ...[
                  const SizedBox(height: FFTokens.spacingMd),
                  FFAlert(
                    key: const Key('payout-paid'),
                    tone: FFAlertTone.success,
                    message: context
                        .tr('payouts.paidTo')
                        .replaceFirst(
                          '{account}',
                          [
                            (s['paidTo'] as Map?)?['provider'],
                            if ((s['paidTo'] as Map?)?['accountLast4'] != null)
                              '····${(s['paidTo'] as Map)['accountLast4']}',
                          ].whereType<Object>().join(' '),
                        )
                        .replaceFirst(
                          '{ref}',
                          s['paymentReference']?.toString() ?? '',
                        ),
                  ),
                ],
                const SizedBox(height: FFTokens.spacingLg),
                FFSectionTitle(context.tr('payouts.sessionsTitle')),
                for (final l in lines)
                  ListTile(
                    key: Key('payout-line-${l['bookingId']}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l['memberName']?.toString() ??
                          context.tr('payouts.member'),
                    ),
                    subtitle: Text(
                      [
                        '${l['date']}${l['slot'] != null ? ' · ${l['slot']}' : ''}',
                        context.tr(
                          l['basis'] == 'completed'
                              ? 'payouts.basis.completed'
                              : 'payouts.basis.tookPlace',
                        ),
                      ].join(' · '),
                    ),
                    trailing: Text(
                      formatCurrency(l['payoutTzs'] as num? ?? 0),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
              ],
            ),
    );
  }
}
