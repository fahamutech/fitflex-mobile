// Results (M10): how a campaign or automation did, in three groups —
// Delivery, Engagement, Business — with attributed revenue. "—" means no
// data (push can't confirm delivery; a message whose button only opens it
// has no action to complete), never zero.

import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../data/analytics_models.dart';
import '../data/communication_repository.dart';
import 'comms_format.dart';

String _pct(int n, int of) => of == 0 ? '' : ' · ${(n * 100 / of).round()}%';

/// The three groups for one set of results.
class ResultsView extends StatelessWidget {
  const ResultsView({
    super.key,
    required this.results,
    this.showConversions = true,
  });

  final CommsResults results;
  final bool showConversions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = results.counts;
    final of = c.recipients;
    Widget row(String key, int? value, {bool pct = false}) => Padding(
      key: Key('result-$key'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.tr('comms.results.$key'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            value == null ? '—' : '$value${pct ? _pct(value, of) : ''}',
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
    Widget group(String key, List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('comms.results.group.$key'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          ...rows,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('delivery', [
          row('recipients', c.recipients),
          row('sent', c.sent),
          row('delivered', c.delivered),
          row('failed', c.failed),
        ]),
        group('engagement', [
          row('opened', c.opened, pct: true),
          row('clicked', c.clicked, pct: true),
          row('ctaCompleted', c.ctaCompleted, pct: true),
        ]),
        group('business', [
          row('renewed', c.renewed),
          row('paid', c.paid),
          Padding(
            key: const Key('result-revenue'),
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('comms.results.revenue'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  formatCurrency(results.revenueTzs),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ]),
        Text(
          context
              .tr('comms.results.attribution')
              .replaceFirst('{click}', '${results.clickWindowDays}')
              .replaceFirst('{open}', '${results.openWindowDays}'),
          style: theme.textTheme.bodySmall,
        ),
        if (showConversions && results.conversions.isNotEmpty) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('comms.results.whoPaid'),
            style: theme.textTheme.titleSmall,
          ),
          for (final cv in results.conversions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                [
                  cv.memberName ?? context.tr('comms.history.unknownMember'),
                  formatCurrency(cv.amountTzs),
                  context.tr(
                    cv.renewal
                        ? 'comms.results.renewal'
                        : 'comms.results.firstPayment',
                  ),
                  context.tr('comms.results.via.${cv.via}'),
                  if (cv.paidAt != null) formatWhen(context, cv.paidAt!),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

/// Loads results with [load] and shows them in a card with a title.
class ResultsCard extends StatefulWidget {
  const ResultsCard({
    super.key,
    required this.titleKey,
    required this.load,
    this.showConversions = true,
    this.repository,
    this.builder,
  });

  final String titleKey;
  final Future<CommsResults> Function(CommunicationRepository repo) load;
  final bool showConversions;
  final CommunicationRepository? repository;

  /// How to show the results; [ResultsView] by default.
  final Widget Function(BuildContext context, CommsResults results)? builder;

  @override
  State<ResultsCard> createState() => _ResultsCardState();
}

class _ResultsCardState extends State<ResultsCard> {
  CommsResults? _r;
  bool _failed = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final repo =
        widget.repository ?? CommunicationRepository(AppScope.of(context).api);
    widget
        .load(repo)
        .then((r) {
          if (mounted) setState(() => _r = r);
        })
        .catchError((Object _) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  Widget build(BuildContext context) => FFCard(
    key: Key('results-${widget.titleKey}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(widget.titleKey),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        if (_failed)
          Text(
            context.tr('comms.loadFailed'),
            style: Theme.of(context).textTheme.bodySmall,
          )
        else if (_r == null)
          const Center(child: FFSpinner())
        else if (widget.builder != null)
          widget.builder!(context, _r!)
        else
          ResultsView(results: _r!, showConversions: widget.showConversions),
      ],
    ),
  );
}

/// The Overview's last-30-days results, with each campaign and automation.
class OverviewResults extends StatelessWidget {
  const OverviewResults({
    super.key,
    required this.results,
    required this.sourceName,
  });

  final CommsResults results;

  /// The display name of an automation (by trigger) or campaign.
  final String Function(ResultSource s) sourceName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResultsView(results: results, showConversions: false),
        if (results.sources.isNotEmpty) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('comms.results.bySource'),
            style: theme.textTheme.titleSmall,
          ),
          for (final s in results.sources.take(8))
            Padding(
              key: Key('result-source-${s.id}'),
              padding: const EdgeInsets.symmetric(
                vertical: FFTokens.spacing2xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sourceName(s), style: theme.textTheme.bodyMedium),
                        Text(
                          context
                              .tr('comms.results.sourceLine')
                              .replaceFirst('{n}', '${s.recipients}')
                              .replaceFirst('{opened}', '${s.opened}')
                              .replaceFirst('{paid}', '${s.paid}'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatCurrency(s.revenueTzs),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
