// "This wasn't me": the member's report of a web check-in they do not
// recognise (fitflex-functions docs/security-incident-report-api.md).
// The sheet only asks; the page sends. A report never removes the visit.

import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

/// What the server said about a report (`POST
/// /me/security-activity/:eventId/report`).
class SecurityReportResult {
  const SecurityReportResult({
    required this.incidentId,
    required this.status,
    required this.reportedAt,
    required this.signedOut,
    required this.pinResetRequired,
    required this.limited,
    required this.failed,
  });

  final String incidentId;
  final String status;
  final String? reportedAt;

  /// Every session of the account, this one included, has been ended.
  final bool signedOut;

  /// FitFlex holds a PIN and it must be replaced with Forgot PIN. False for
  /// `false` and for `"not_applicable"` (no PIN held by FitFlex).
  final bool pinResetRequired;

  /// Recorded, but the account was already secured twice in 24 hours, so
  /// nothing was locked again.
  final bool limited;

  /// Securing was asked for but not applied.
  final bool failed;

  factory SecurityReportResult.fromJson(Map<String, dynamic> j) {
    final incident = j['incident'];
    final protection = j['protection'];
    final i = incident is Map ? incident : const {};
    final p = protection is Map ? protection : const {};
    return SecurityReportResult(
      incidentId: i['id']?.toString() ?? '',
      status: i['status']?.toString() ?? 'open',
      reportedAt: i['reportedAt']?.toString(),
      signedOut: j['signedOut'] == true,
      pinResetRequired: p['pinResetRequired'] == true,
      limited: p['limited'] == true,
      failed: p['failed'] == true,
    );
  }
}

/// The words for a 429 `report_limit_reached`, with the wait when the server
/// gave one (`retryAfterSeconds`).
String securityReportLimitText(BuildContext context, Object? retryAfter) {
  final seconds = retryAfter is num
      ? retryAfter.toInt()
      : int.tryParse(retryAfter?.toString() ?? '');
  if (seconds == null || seconds <= 0) {
    return context.tr('secAct.report.err.limit');
  }
  // Up to an hour and a half in minutes, longer in whole hours (2 or more).
  final (key, n) = seconds <= 5400
      ? ('secAct.report.err.limitMinutes', (seconds / 60).ceil())
      : ('secAct.report.err.limitHours', (seconds / 3600).ceil());
  return context.tr(key).replaceAll('{n}', '$n');
}

/// Asks how to report. Resolves `true` for "Report and secure my account",
/// `false` for "Report only" and null when cancelled or dismissed.
Future<bool?> showSecurityReportSheet(BuildContext context) =>
    showFFSheet<bool>(
      context,
      title: context.tr('secAct.report.sheet.title'),
      focusTitle: true,
      child: const _ReportSheetBody(),
    );

class _ReportSheetBody extends StatelessWidget {
  const _ReportSheetBody();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secure = context.tr('secAct.report.sheet.secure');
    final secureHint = context.tr('secAct.report.sheet.secureHint');
    final only = context.tr('secAct.report.sheet.only');
    final onlyHint = context.tr('secAct.report.sheet.onlyHint');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('secAct.report.sheet.body'), style: text.bodyMedium),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr('secAct.report.sheet.notRemoved'),
          style: text.bodyMedium,
        ),
        const SizedBox(height: FFTokens.spacingLg),
        FFButton(
          key: const Key('security-report-secure'),
          label: secure,
          semanticLabel: '$secure. $secureHint',
          maxLines: 4,
          fullWidth: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        ExcludeSemantics(child: Text(secureHint, style: text.bodySmall)),
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('security-report-only'),
          label: only,
          semanticLabel: '$only. $onlyHint',
          maxLines: 4,
          fullWidth: true,
          variant: FFButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        ExcludeSemantics(child: Text(onlyHint, style: text.bodySmall)),
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('security-report-cancel'),
          label: context.tr('member.cancel'),
          fullWidth: true,
          variant: FFButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Tells the member the account was secured and this device is signed out.
/// Closes only with its button; the caller then ends the session.
Future<void> showSecurityReportSignedOutDialog(
  BuildContext context, {
  required bool pinResetRequired,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (ctx) => PopScope(
    canPop: false,
    child: AlertDialog(
      key: const Key('security-report-signed-out'),
      scrollable: true,
      title: Text(ctx.tr('secAct.report.signedOut.title')),
      content: Text(
        ctx.tr(
          pinResetRequired
              ? 'secAct.report.signedOut.pin'
              : 'secAct.report.signedOut.again',
        ),
      ),
      actions: [
        FFButton(
          key: const Key('security-report-signed-out-ok'),
          label: ctx.tr('secAct.report.signedOut.action'),
          maxLines: 2,
          onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
        ),
      ],
    ),
  ),
);
