import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_order.dart';
import '../../../shared/events/events_checkout.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/i18n.dart';
import 'events_registration_gate.dart';

/// `/member/events/teams/:teamId` (events S3 spec §3.9, §5): members by
/// first name + initial, the captain, and the join code — shown with a
/// copy button to the captain / creator only (the server sends it to no
/// one else).
class EventTeamPage extends StatefulWidget {
  const EventTeamPage({super.key, required this.teamId, this.options});

  final String teamId;
  final EventsOptions? options;

  @override
  State<EventTeamPage> createState() => _EventTeamPageState();
}

class _EventTeamPageState extends State<EventTeamPage> {
  EventTeam? _team;
  bool _loading = true;
  Object? _error;
  bool _gone = false;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _gone = false;
    });
    try {
      final json = await _api.getEventTeam(widget.teamId);
      if (!mounted) return;
      // `{ team, members, isCaptain, joinCode }` or the team flat with
      // `members` inside: both read the same.
      final merged = json['team'] is Map
          ? <String, dynamic>{
              ...Map<String, dynamic>.from(json['team'] as Map),
              for (final k in const ['members', 'isCaptain', 'joinCode'])
                if (json[k] != null) k: json[k],
            }
          : json;
      setState(() {
        _team = EventTeam.fromJson(merged);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e is ApiException && e.status == 404) {
          _gone = true;
        } else {
          _error = e;
        }
      });
    }
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.memberEventOrders);

  @override
  Widget build(BuildContext context) {
    final t = _team;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.review.team')),
      ),
      body: _gone
          ? Center(
              child: FFEmptyState(
                key: const Key('team-gone'),
                icon: Icons.groups_outlined,
                title: context.tr('error.reason.teamNotFound'),
              ),
            )
          : _loading
          ? FFSkeletonList(
              key: const Key('team-loading'),
              semanticLabel: context.tr('common.loading'),
            )
          : t == null
          ? Center(
              child: FFErrorState(
                key: const Key('team-error'),
                message: _error == null
                    ? null
                    : errorMessage(FFLocaleScope.of(context), _error!),
                retryLabel: context.tr('common.retry'),
                onRetry: _load,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    t.name,
                    key: const Key('team-name'),
                    style: tt.titleLarge,
                  ),
                ),
                Text(
                  [
                    if (context.tr('events.team.type.${t.teamType}') !=
                        'events.team.type.${t.teamType}')
                      context.tr('events.team.type.${t.teamType}'),
                    '${t.memberCount}/${t.maxMembers} '
                        '${context.tr('events.team.members').toLowerCase()}',
                  ].join(' · '),
                  key: const Key('team-subtitle'),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (t.joinCode case final code?) ...[
                  const SizedBox(height: FFTokens.spacingMd),
                  FFCard(
                    key: const Key('team-code-card'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('events.team.yourCode'),
                          style: tt.titleSmall,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatTeamCode(code),
                                key: const Key('team-code'),
                                style: tt.headlineSmall?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              key: const Key('team-code-copy'),
                              tooltip: context.tr('common.copy'),
                              icon: const Icon(Icons.copy_outlined),
                              onPressed: () async {
                                final snack = FFSnack.of(context);
                                final copied = context.tr('common.copied');
                                await Clipboard.setData(
                                  ClipboardData(text: formatTeamCode(code)),
                                );
                                snack.success(copied);
                              },
                            ),
                          ],
                        ),
                        Text(
                          context.tr('events.team.shareCode'),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                FFSectionTitle(context.tr('events.team.members')),
                for (final m in t.members)
                  FFCard(
                    key: Key('team-member-${m.registrationId}'),
                    child: Row(
                      children: [
                        FFAvatar(name: m.name),
                        const SizedBox(width: FFTokens.spacingSm),
                        Expanded(child: Text(m.name, style: tt.bodyMedium)),
                        if (m.role == 'captain')
                          FFBadge(
                            label: context.tr('events.team.captain'),
                            tone: FFBadgeTone.brand,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
