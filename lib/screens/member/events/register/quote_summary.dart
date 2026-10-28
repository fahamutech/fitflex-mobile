import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_detail.dart';
import '../../../../shared/events/event_order.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../event_status.dart';

/// The itemised server quote (events S3 spec §5.6), reused on the order
/// page: tickets, discount and fee lines only when they are non-zero (D21),
/// and the bold total.
class QuoteLinesTable extends StatelessWidget {
  const QuoteLinesTable({
    super.key,
    required this.lines,
    required this.currency,
    required this.discountTzs,
    required this.feesTzs,
    required this.totalTzs,
    this.feeLabel,
  });

  final List<QuoteLine> lines;
  final String currency;
  final int discountTzs;
  final int feesTzs;
  final int totalTzs;
  final EventText? feeLabel;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    Widget row(String label, String amount, {bool bold = false, Key? key}) =>
        Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: bold
                      ? tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)
                      : tt.bodyMedium,
                ),
              ),
              Text(
                amount,
                style:
                    (bold
                            ? tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              )
                            : tt.bodyMedium)
                        ?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
              ),
            ],
          ),
        );
    String money(int v) => formatCurrency(v, currency: currency);
    final fee = feeLabel == null || feeLabel!.isEmpty
        ? context.tr('events.review.fee')
        : feeLabel!.of(lang);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in lines)
          row(
            '${l.ticketTypeName} × ${l.quantity}',
            money(l.lineTotalTzs),
            key: Key('quote-line-${l.ticketTypeId}'),
          ),
        if (discountTzs > 0)
          row(
            context.tr('events.review.discount'),
            '− ${money(discountTzs)}',
            key: const Key('quote-discount'),
          ),
        if (feesTzs > 0) row(fee, money(feesTzs), key: const Key('quote-fee')),
        Divider(color: cs.outline),
        row(
          context.tr('events.review.total'),
          totalTzs == 0 ? context.tr('events.card.free') : money(totalTzs),
          bold: true,
          key: const Key('quote-total'),
        ),
      ],
    );
  }
}

/// Step 4: quote table, participants, team, refund policy, terms, the
/// terms checkbox and the hold notice.
class QuoteSummary extends StatelessWidget {
  const QuoteSummary({
    super.key,
    required this.quote,
    required this.detail,
    required this.participants,
    required this.accepted,
    required this.onAccepted,
    required this.holdTtlMinutes,
    this.teamLabel,
    this.consentLine,
  });

  final EventQuote quote;
  final EventDetail detail;

  /// (name, category, isSelf) per participant.
  final List<({String name, String category, bool isSelf})> participants;
  final bool accepted;
  final ValueChanged<bool> onAccepted;
  final int holdTtlMinutes;
  final String? teamLabel;

  /// The `purchaser_authorised` consent copy, shown read-only under the
  /// participants when any place is for someone else.
  final String? consentLine;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final refund = quote.refundPolicy.preset.isEmpty
        ? detail.refundPolicy
        : quote.refundPolicy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFSectionTitle(context.tr('events.review.tickets')),
        FFCard(
          key: const Key('review-quote'),
          child: QuoteLinesTable(
            lines: quote.lines,
            currency: quote.currency,
            discountTzs: quote.discountTzs,
            feesTzs: quote.feesTzs,
            totalTzs: quote.totalTzs,
            feeLabel: quote.feeLabel,
          ),
        ),
        FFSectionTitle(context.tr('events.review.participants')),
        FFCard(
          key: const Key('review-participants'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in participants)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: FFTokens.spacingXs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: tt.bodyMedium),
                            Text(
                              p.category,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: FFBadge(
                          label: p.isSelf
                              ? context.tr('events.participant.you')
                              : context.tr('events.participant.willInvite'),
                          tone: p.isSelf
                              ? FFBadgeTone.brand
                              : FFBadgeTone.defaultTone,
                          wrap: true,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              if (consentLine != null && consentLine!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                  child: Text(
                    consentLine!,
                    key: const Key('review-consent-line'),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        if (teamLabel != null) ...[
          FFSectionTitle(context.tr('events.review.team')),
          FFCard(
            key: const Key('review-team'),
            child: Text(teamLabel!, style: tt.bodyMedium),
          ),
        ],
        FFSectionTitle(context.tr('events.review.refund')),
        FFCard(
          key: const Key('review-refund'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (refundPolicyLine(context, refund) case final line?)
                Text(line, style: tt.titleSmall),
              if (refund.text.isNotEmpty)
                Text(refund.text.of(lang), style: tt.bodySmall),
            ],
          ),
        ),
        if (detail.terms.isNotEmpty) ...[
          FFSectionTitle(context.tr('events.review.terms')),
          FFCard(
            key: const Key('review-terms'),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                context.tr('events.detail.showAll'),
                style: tt.bodyMedium,
              ),
              children: [Text(detail.terms.of(lang), style: tt.bodySmall)],
            ),
          ),
        ],
        const SizedBox(height: FFTokens.spacingSm),
        Semantics(
          container: true,
          child: CheckboxListTile(
            key: const Key('review-accept'),
            value: accepted,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              context.tr('events.review.accept'),
              style: tt.bodyMedium,
            ),
            onChanged: (v) => onAccepted(v ?? false),
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFAlert(
          key: const Key('review-hold-notice'),
          tone: FFAlertTone.info,
          message: context
              .tr('events.review.hold')
              .replaceFirst('{n}', '$holdTtlMinutes'),
        ),
      ],
    );
  }
}
