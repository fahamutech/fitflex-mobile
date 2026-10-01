// My wellness benefits: what an employer, insurer or other sponsor gives the
// member through FitFlex, how much is used and what is left. Read-only: the
// server works out every number, and a benefit is used automatically at
// check-in or when a trainer session is completed.

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';

class MemberBenefitsPage extends StatefulWidget {
  const MemberBenefitsPage({super.key});

  @override
  State<MemberBenefitsPage> createState() => _MemberBenefitsPageState();
}

class _MemberBenefitsPageState extends State<MemberBenefitsPage> {
  List<Map<String, dynamic>>? _benefits;
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
      final res = await AppScope.of(context).api.myWellnessBenefits();
      if (!mounted) return;
      setState(() {
        _benefits = ((res['benefits'] as List?) ?? const [])
            .map((b) => (b as Map).cast<String, dynamic>())
            .toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _benefits;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('benefits.title'))),
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
          : rows.isEmpty
          ? FFEmptyState(
              title: context.tr('benefits.empty.title'),
              body: context.tr('benefits.empty.body'),
            )
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Text(
                  context.tr('benefits.intro'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                for (final row in rows) ...[
                  _BenefitCard(row: row),
                  const SizedBox(height: FFTokens.spacingMd),
                ],
              ],
            ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = (row['organization'] as Map).cast<String, dynamic>();
    final program = (row['program'] as Map).cast<String, dynamic>();
    final benefit = (row['benefit'] as Map).cast<String, dynamic>();
    final validity = (benefit['validity'] as Map?)?.cast<String, dynamic>();
    final limit = benefit['usageLimit'] as num?;
    final used = (row['used'] as num?) ?? 0;
    final remaining = row['remaining'] as num?;
    final period = '${benefit['usagePeriod']}';
    final endDate = validity?['endDate'] as String?;

    return FFCard(
      key: Key('benefit-${benefit['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${org['name']} · ${program['name']}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text('${benefit['name']}', style: theme.textTheme.titleMedium),
          Text(
            context.tr('benefits.type.${benefit['benefitType']}'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (limit != null) ...[
            LinearProgressIndicator(
              value: limit == 0 ? 0 : (used / limit).clamp(0, 1).toDouble(),
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              context
                  .tr('benefits.used')
                  .replaceAll('{used}', '$used')
                  .replaceAll('{limit}', '$limit')
                  .replaceAll(
                    '{period}',
                    context.tr('benefits.period.$period'),
                  ),
            ),
            Text(
              context
                  .tr('benefits.remaining')
                  .replaceAll('{n}', '${remaining ?? 0}'),
              style: theme.textTheme.titleSmall,
            ),
          ] else
            Text(context.tr('benefits.unlimited')),
          const SizedBox(height: FFTokens.spacingSm),
          Text(_funding(context, benefit)),
          Text(
            endDate == null
                ? context.tr('benefits.noEnd')
                : context
                      .tr('benefits.validUntil')
                      .replaceAll('{date}', endDate),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _funding(BuildContext context, Map<String, dynamic> b) {
    final type = '${b['fundingType']}';
    final text = context.tr('benefits.funding.$type');
    switch (type) {
      case 'sponsor_fixed':
        return text.replaceAll(
          '{amount}',
          formatCurrency((b['sponsorAmountTzs'] as num?) ?? 0),
        );
      case 'sponsor_percentage':
        final pct = ((b['sponsorShareBps'] as num?) ?? 0) / 100;
        return text.replaceAll(
          '{pct}',
          pct == pct.roundToDouble() ? '${pct.round()}' : '$pct',
        );
      case 'beneficiary_fixed':
        return text.replaceAll(
          '{amount}',
          formatCurrency((b['beneficiaryAmountTzs'] as num?) ?? 0),
        );
      default:
        return text;
    }
  }
}
