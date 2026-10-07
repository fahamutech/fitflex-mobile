import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/run_metrics.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import '../../shared/social.dart';
import 'widgets/run_widgets.dart';
import 'widgets/share_picker.dart';

/// A saved run: numbers, splits and the route (which only the member sees).
class MemberRunDetailPage extends StatefulWidget {
  const MemberRunDetailPage({super.key, required this.activityId});

  final String activityId;

  @override
  State<MemberRunDetailPage> createState() => _MemberRunDetailPageState();
}

class _MemberRunDetailPageState extends State<MemberRunDetailPage> {
  List<List<TrackPoint>>? _route;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    try {
      final res = await AppScope.of(context).api.runRoute(widget.activityId);
      final segs = ((res['route'] as Map?)?['segments'] as List?) ?? const [];
      if (!mounted) return;
      setState(
        () => _route = [
          for (final s in segs)
            if (s is List) [for (final p in s) ?TrackPoint.fromWire(p)],
        ],
      );
    } catch (_) {
      if (mounted) setState(() => _route = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = MemberDataScope.of(
      context,
    ).activities.where((x) => x.id == widget.activityId).firstOrNull;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('run.detailTitle')),
        leading: BackButton(
          onPressed: () => context.go(AppRoutes.memberActivity),
        ),
        actions: [
          if (a != null && canDeleteActivity(a))
            PopupMenuButton<String>(
              key: const Key('run-detail-menu'),
              onSelected: (_) async {
                final router = GoRouter.of(context);
                if (await deleteOwnActivity(context, a)) {
                  router.go(AppRoutes.memberActivity);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.tr('run.delete')),
                ),
              ],
            ),
        ],
      ),
      body: a == null
          ? FFEmptyState(title: context.tr('run.notFound'))
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Text(
                  (a.notes ?? '').isNotEmpty
                      ? a.notes!
                      : context.tr('run.defaultName'),
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  DateFormat(
                    'EEE d MMM y · HH:mm',
                  ).format(a.startedAt.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                if (a.hasRoute)
                  _route == null
                      ? const SizedBox(
                          height: 220,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _route!.isEmpty
                      ? const SizedBox.shrink()
                      : RunMap(
                          key: const Key('run-detail-map'),
                          segments: _route!,
                          height: 220,
                        ),
                if (a.hasRoute)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: FFTokens.spacingXs),
                        Text(
                          context.tr('run.routePrivate'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: FFTokens.spacingSm),
                FFActionTile(
                  key: const Key('run-detail-share'),
                  icon: a.shareWith == null
                      ? Icons.lock_outline
                      : Icons.people_outline,
                  title: context.tr('audience.whoCanSee'),
                  subtitle: shareLabel(
                    context,
                    ShareWith.fromJson(a.shareWith),
                  ),
                  onTap: () => editActivitySharing(context, a),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                RunSummaryGrid(
                  distanceKm: a.distanceKm ?? 0,
                  seconds: a.movingSeconds ?? (a.durationMinutes ?? 0) * 60,
                  elevationGainM: a.elevationGainM ?? 0,
                  calories: a.calories,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                RunSplits(splits: a.splits),
              ],
            ),
    );
  }
}
