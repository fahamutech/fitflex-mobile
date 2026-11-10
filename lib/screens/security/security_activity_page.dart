// Security activity: the list of check-ins made from a web browser with the
// signed-in account (fitflex-functions docs/web-checkin-alerts-api.md), and,
// while the server allows it (`reportEnabled`), the "This wasn't me" report
// (docs/security-incident-report-api.md).
// Nothing here is kept on the device, and payloads are never logged.

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../pin_flows.dart' show changePinAndReport;
import 'security_report_sheet.dart';

/// The member's report of an event. Only its progress is known here, never
/// what staff decided.
class SecurityReport {
  const SecurityReport({required this.incidentId, required this.status});

  final String incidentId;

  /// `open`, `acknowledged` or `resolved`.
  final String status;

  /// The i18n key of the report chip. An unknown status reads as reported.
  String get statusKey => switch (status) {
    'acknowledged' => 'secAct.report.status.acknowledged',
    'resolved' => 'secAct.report.status.resolved',
    _ => 'secAct.report.status.open',
  };

  static SecurityReport? fromJson(Object? j) => j is Map
      ? SecurityReport(
          incidentId: j['incidentId']?.toString() ?? '',
          status: j['status']?.toString() ?? 'open',
        )
      : null;
}

/// One event of the list. Unknown kinds are kept and shown generically.
class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.kind,
    required this.occurredAt,
    required this.gymName,
    required this.status,
    this.report,
  });

  final String id;
  final String kind;
  final DateTime? occurredAt;
  final String? gymName;
  final String status;

  /// Null until the member reports the event.
  final SecurityReport? report;

  SecurityEvent withReport(SecurityReport r) => SecurityEvent(
    id: id,
    kind: kind,
    occurredAt: occurredAt,
    gymName: gymName,
    status: status,
    report: r,
  );

  bool get isWebCheckin => kind == 'web_checkin';

  /// The i18n key of the status chip, or null for a status we don't know.
  /// `notified` is the legacy name of `inbox`.
  String? get statusKey => securityStatusKey(status);

  factory SecurityEvent.fromJson(Map<String, dynamic> j) {
    final gym = j['gym'];
    final name = gym is Map ? gym['name']?.toString().trim() : null;
    return SecurityEvent(
      id: j['id']?.toString() ?? '',
      kind: j['kind']?.toString() ?? '',
      occurredAt: DateTime.tryParse(j['occurredAt']?.toString() ?? '')?.toUtc(),
      gymName: name == null || name.isEmpty ? null : name,
      status: j['status']?.toString() ?? '',
      report: SecurityReport.fromJson(j['report']),
    );
  }
}

String? securityStatusKey(String status) => switch (status) {
  'inbox' || 'notified' => 'secAct.status.inbox',
  'recorded' => 'secAct.status.recorded',
  _ => null,
};

/// "9 Nov 2026, 14:30 EAT": the time in Africa/Dar_es_Salaam (UTC+3, no
/// daylight saving), whatever the phone's own zone.
String securityEventTime(DateTime? at, {String locale = 'en'}) {
  if (at == null) return '-';
  final u = at.toUtc().add(const Duration(hours: 3));
  final eat = DateTime(u.year, u.month, u.day, u.hour, u.minute);
  return '${formatDate(eat, locale: locale)}, '
      '${formatTimeOfDay(eat, locale: locale)} EAT';
}

class SecurityActivityPage extends StatefulWidget {
  const SecurityActivityPage({super.key});

  @override
  State<SecurityActivityPage> createState() => _SecurityActivityPageState();
}

class _SecurityActivityPageState extends State<SecurityActivityPage> {
  static const _pageSize = 20;

  final _events = <SecurityEvent>[];
  String? _next;
  bool _started = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _off = false;
  bool _failed = false;
  bool _moreFailed = false;

  /// The server's `reportEnabled`: false (or absent) hides every report
  /// action, and the screen is the read-only list.
  bool _reportEnabled = false;

  /// The event whose report is being sent. One at a time.
  String? _reporting;

  /// What to say under an event after a report, until the page is left.
  final _notices = <String, _ReportNotice>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  static List<SecurityEvent> _parse(Map<String, dynamic> body) => [
    for (final e in (body['events'] as List?) ?? const [])
      if (e is Map) SecurityEvent.fromJson(e.cast<String, dynamic>()),
  ];

  static String? _cursor(Map<String, dynamic> body) {
    final n = body['next']?.toString();
    return n == null || n.isEmpty ? null : n;
  }

  Future<void> _load({bool refresh = false}) async {
    final api = AppScope.of(context).api;
    if (!refresh) {
      setState(() {
        _loading = true;
        _failed = false;
        _off = false;
      });
    }
    try {
      final body = await api.securityActivity(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _events
          ..clear()
          ..addAll(_parse(body));
        _next = _cursor(body);
        _reportEnabled = body['reportEnabled'] == true;
        _off = false;
        _failed = false;
        _moreFailed = false;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _off = e.status == 404;
        _failed = !_off;
        _loading = false;
        if (_off) {
          _events.clear();
          _reportEnabled = false;
          _notices.clear();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = _events.isEmpty;
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    final cursor = _next;
    if (cursor == null || _loadingMore) return;
    final api = AppScope.of(context).api;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final body = await api.securityActivity(limit: _pageSize, before: cursor);
      if (!mounted) return;
      setState(() {
        _events.addAll(_parse(body));
        _next = _cursor(body);
        _reportEnabled = body['reportEnabled'] == true;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  Future<void> _askReport(SecurityEvent event) async {
    if (_reporting != null) return;
    final secure = await showSecurityReportSheet(context);
    if (secure == null || !mounted) return;
    await _report(event, secure);
  }

  /// Sends the report. Also the retry: the server answers a repeat with the
  /// same incident, and applies a protection that failed the first time.
  Future<void> _report(SecurityEvent event, bool secure) async {
    if (_reporting != null) return;
    final scope = AppScope.of(context);
    final snack = FFSnack.of(context);
    final done = context.tr('secAct.report.done');
    final unavailable = context.tr('secAct.report.err.unavailable');
    setState(() {
      _reporting = event.id;
      _notices.remove(event.id);
    });
    final SecurityReportResult result;
    try {
      result = SecurityReportResult.fromJson(
        await scope.api.reportSecurityActivity(event.id, secureAccount: secure),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // 401: the session is over and ApiClient has already signed out.
      if (e.status == 401) return setState(() => _reporting = null);
      if (e.status == 404) {
        // Switched off, or no longer this member's event.
        setState(() => _reporting = null);
        snack.error(unavailable);
        return _load(refresh: true);
      }
      final body = e.body;
      final limit = e.status == 429;
      setState(() {
        _reporting = null;
        _notices[event.id] = limit
            ? _ReportNotice(
                securityReportLimitText(
                  context,
                  body is Map ? body['retryAfterSeconds'] : null,
                ),
              )
            : _ReportNotice(
                context.tr('secAct.report.err.failed'),
                retry: secure,
              );
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reporting = null;
        _notices[event.id] = _ReportNotice(
          context.tr('secAct.report.err.network'),
          retry: secure,
        );
      });
      return;
    }
    if (!mounted) {
      // The page was left meanwhile; a session the server ended still has
      // to end here.
      if (result.signedOut) await scope.auth.signOut();
      return;
    }
    setState(() {
      _reporting = null;
      final at = _events.indexWhere((e) => e.id == event.id);
      if (at >= 0) {
        _events[at] = _events[at].withReport(
          SecurityReport(incidentId: result.incidentId, status: result.status),
        );
      }
      if (result.signedOut) return;
      if (result.failed) {
        _notices[event.id] = _ReportNotice(
          context.tr('secAct.report.failed'),
          tone: FFAlertTone.warning,
          retry: true,
          retryKey: 'secAct.report.failedRetry',
          changePin: true,
        );
      } else if (result.limited) {
        _notices[event.id] = _ReportNotice(
          context.tr('secAct.report.limited'),
          tone: FFAlertTone.info,
        );
      }
    });
    if (result.signedOut) {
      await showSecurityReportSignedOutDialog(
        context,
        pinResetRequired: result.pinResetRequired,
      );
      // The app's own sign-out: clears the session and the router shows
      // sign-in.
      return scope.auth.signOut();
    }
    if (!result.failed && !result.limited) snack.success(done);
    await _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('secAct.title'))),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: FFSpinner());
    final Widget content;
    if (_off) {
      content = FFEmptyState(
        icon: Icons.shield_outlined,
        title: context.tr('secAct.off.title'),
        body: context.tr('secAct.off.body'),
      );
    } else if (_failed) {
      content = FFErrorState(
        title: context.tr('inbox.loadFailed'),
        retryLabel: context.tr('comms.retry'),
        onRetry: _load,
      );
    } else if (_events.isEmpty) {
      content = FFEmptyState(
        icon: Icons.shield_outlined,
        title: context.tr('secAct.empty.title'),
        body: context.tr('secAct.empty.body'),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in _events)
            SecurityActivityRow(
              event: e,
              onReport: _reportEnabled && e.isWebCheckin && e.report == null
                  ? () => _askReport(e)
                  : null,
              reporting: _reporting == e.id,
              busy: _reporting != null,
              notice: _noticeFor(e),
            ),
          if (_moreFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: Text(
                context.tr('inbox.loadFailed'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_next != null)
            _loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(FFTokens.spacingMd),
                    child: Center(child: FFSpinner()),
                  )
                : FFButton(
                    key: const Key('security-activity-more'),
                    label: context.tr(
                      _moreFailed ? 'comms.retry' : 'secAct.loadMore',
                    ),
                    variant: FFButtonVariant.secondary,
                    onPressed: _more,
                  ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        key: const Key('security-activity-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          if (!_off)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
              child: Text(
                context.tr('secAct.intro'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          content,
        ],
      ),
    );
  }

  /// The message under an event after a report, with its retry and (when
  /// the account could not be secured) the way to change the PIN.
  Widget? _noticeFor(SecurityEvent event) {
    final n = _notices[event.id];
    if (n == null || !_reportEnabled) return null;
    final retry = n.retry;
    final busy = _reporting != null;
    return Column(
      key: Key('security-report-notice-${event.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: FFAlert(message: n.message, tone: n.tone),
        ),
        if (n.changePin && AppScope.of(context).auth.pinLoginEnabled) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: Key('security-report-change-pin-${event.id}'),
            label: context.tr('member.changePin'),
            icon: Icons.lock_outline,
            maxLines: 3,
            fullWidth: true,
            onPressed: busy ? null : () => changePinAndReport(context),
          ),
        ],
        if (retry != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: Key('security-report-retry-${event.id}'),
            label: context.tr(n.retryKey),
            maxLines: 3,
            fullWidth: true,
            variant: FFButtonVariant.secondary,
            loading: _reporting == event.id,
            onPressed: busy ? null : () => _report(event, retry),
          ),
        ],
      ],
    );
  }
}

class _ReportNotice {
  const _ReportNotice(
    this.message, {
    this.tone = FFAlertTone.error,
    this.retry,
    this.retryKey = 'comms.retry',
    this.changePin = false,
  });

  final String message;
  final FFAlertTone tone;

  /// The choice to send again (`secureAccount`), or null for no retry.
  final bool? retry;
  final String retryKey;
  final bool changePin;
}

/// One event: icon, what happened, where, when (EAT), a status chip, the
/// report chip once reported, and the "This wasn't me" action while
/// [onReport] is set.
class SecurityActivityRow extends StatelessWidget {
  const SecurityActivityRow({
    super.key,
    required this.event,
    this.onReport,
    this.reporting = false,
    this.busy = false,
    this.notice,
  });

  final SecurityEvent event;

  /// Opens the report sheet. Null: no action (reporting off, already
  /// reported, or not a web check-in).
  final VoidCallback? onReport;

  /// This event's report is being sent.
  final bool reporting;

  /// Some report is being sent: the action does nothing meanwhile.
  final bool busy;

  /// Shown under the event (the outcome of a report, or its error).
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final title = context.tr(
      event.isWebCheckin ? 'secAct.row.title' : 'secAct.kind.other',
    );
    final gym = event.gymName ?? context.tr('secAct.row.gymUnknown');
    final time = securityEventTime(event.occurredAt, locale: lang);
    final statusKey = event.statusKey;
    final status = statusKey == null ? null : context.tr(statusKey);
    final report = event.report;
    final reported = report == null ? null : context.tr(report.statusKey);
    final details = Semantics(
      container: true,
      label: [title, gym, time, ?status, ?reported].join(', '),
      excludeSemantics: true,
      child: _details(context, title, gym, time, status, reported),
    );
    final onReport = this.onReport;
    if (onReport == null && notice == null) return FFCard(child: details);
    final action = context.tr('secAct.report.action');
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          details,
          if (notice != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            notice!,
          ],
          if (onReport != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            FFButton(
              key: Key('security-report-${event.id}'),
              label: action,
              semanticLabel:
                  '$action. ${context.tr('secAct.report.actionHint')}',
              icon: Icons.flag_outlined,
              maxLines: 3,
              fullWidth: true,
              variant: FFButtonVariant.secondary,
              loading: reporting,
              onPressed: busy && !reporting ? null : onReport,
            ),
          ],
        ],
      ),
    );
  }

  Widget _details(
    BuildContext context,
    String title,
    String gym,
    String time,
    String? status,
    String? reported,
  ) {
    final theme = Theme.of(context);
    final statusKey = event.statusKey;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            event.isWebCheckin ? Icons.language : Icons.shield_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: FFTokens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: FFTokens.spacingXs),
                Text(gym, style: theme.textTheme.bodyMedium),
                Text(time, style: theme.textTheme.bodySmall),
                if (status != null) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  FFBadge(
                    label: status,
                    tone: statusKey == 'secAct.status.inbox'
                        ? FFBadgeTone.info
                        : FFBadgeTone.gray,
                    wrap: true,
                  ),
                ],
                if (reported != null) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  FFBadge(
                    key: Key('security-report-status-${event.id}'),
                    label: reported,
                    tone: event.report?.status == 'resolved'
                        ? FFBadgeTone.gray
                        : FFBadgeTone.warning,
                    wrap: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
