// Security activity: a read-only list of check-ins made from a web browser
// with the signed-in account (fitflex-functions docs/web-checkin-alerts-api.md).
// Nothing here is kept on the device, and payloads are never logged.

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';

/// One event of the list. Unknown kinds are kept and shown generically.
class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.kind,
    required this.occurredAt,
    required this.gymName,
    required this.status,
  });

  final String id;
  final String kind;
  final DateTime? occurredAt;
  final String? gymName;
  final String status;

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
        if (_off) _events.clear();
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
          for (final e in _events) SecurityActivityRow(event: e),
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
}

/// One event: icon, what happened, where, when (EAT) and a status chip.
class SecurityActivityRow extends StatelessWidget {
  const SecurityActivityRow({super.key, required this.event});

  final SecurityEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final title = context.tr(
      event.isWebCheckin ? 'secAct.row.title' : 'secAct.kind.other',
    );
    final gym = event.gymName ?? context.tr('secAct.row.gymUnknown');
    final time = securityEventTime(event.occurredAt, locale: lang);
    final statusKey = event.statusKey;
    final status = statusKey == null ? null : context.tr(statusKey);
    return Semantics(
      container: true,
      label: [title, gym, time, ?status].join(', '),
      excludeSemantics: true,
      child: FFCard(
        child: ConstrainedBox(
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
