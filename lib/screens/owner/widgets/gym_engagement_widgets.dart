import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/activity.dart';
import '../../../shared/activity/gym_sharing.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/widgets/challenge_manager_page.dart';
import '../../member/widgets/activity_widgets.dart' show activityTypeLabel;

String engagementStatusLabel(BuildContext context, String status) =>
    context.tr('engagement.status.$status');

Color? _statusColor(BuildContext context, String status) => switch (status) {
  'active' => Theme.of(context).colorScheme.primary,
  'slipping' || 'at_risk' => FFTokens.warning500,
  _ => null,
};

/// Member detail (owner): visit patterns at each of the owner's gyms, and
/// only the activity the member chose to share with that gym.
class GymMemberActivityCard extends StatefulWidget {
  const GymMemberActivityCard({super.key, required this.memberId});

  final String memberId;

  @override
  State<GymMemberActivityCard> createState() => _GymMemberActivityCardState();
}

class _GymMemberActivityCardState extends State<GymMemberActivityCard> {
  List<GymMemberActivity>? _gyms;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gyms == null) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AppScope.of(
        context,
      ).api.ownerMemberActivity(widget.memberId);
      if (!mounted) return;
      setState(
        () => _gyms = [
          for (final r in rows.whereType<Map>())
            ?GymMemberActivity.tryParse(Map<String, dynamic>.from(r)),
        ],
      );
    } catch (_) {
      // Optional section — the rest of the member page stands on its own.
      if (mounted) setState(() => _gyms = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gyms = _gyms;
    if (gyms == null || gyms.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final fmt = DateFormat('EEE d MMM');
    return Column(
      key: const Key('gym-member-activity'),
      children: [
        for (final g in gyms)
          FFCard(
            margin: const EdgeInsets.only(top: FFTokens.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        gyms.length > 1
                            ? '${context.tr('engagement.title')} · ${g.gym.name ?? ''}'
                            : context.tr('engagement.title'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FFPill(
                      key: const Key('engagement-status'),
                      label: engagementStatusLabel(
                        context,
                        g.engagement.status,
                      ),
                      filled: g.engagement.status == 'active',
                    ),
                  ],
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  [
                    context
                        .tr('engagement.visits30')
                        .replaceAll('{n}', '${g.engagement.visits30}'),
                    context
                        .tr('engagement.perWeek')
                        .replaceAll('{n}', '${g.engagement.avgVisitsPerWeek}'),
                    if (g.engagement.weekStreak > 0)
                      context
                          .tr('engagement.weekStreak')
                          .replaceAll('{n}', '${g.engagement.weekStreak}'),
                  ].map((f) => f.replaceAll(' ', '\u00A0')).join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (g.engagement.daysSinceLastVisit != null)
                  Text(
                    g.engagement.daysSinceLastVisit == 0
                        ? context.tr('engagement.lastToday')
                        : context
                              .tr('engagement.lastDaysAgo')
                              .replaceAll(
                                '{n}',
                                '${g.engagement.daysSinceLastVisit}',
                              ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _statusColor(context, g.engagement.status),
                    ),
                  ),
                const Divider(height: FFTokens.spacingLg),
                Text(
                  context.tr('engagement.sharedWithYou'),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: FFTokens.spacingXs),
                if (g.classAttendance == null &&
                    g.gymWorkouts == null &&
                    g.challenges == null)
                  Row(
                    key: const Key('gym-nothing-shared'),
                    children: [
                      const Icon(Icons.lock_outline, size: 16),
                      const SizedBox(width: FFTokens.spacingSm),
                      Expanded(
                        child: Text(
                          context.tr('engagement.nothingShared'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                if (g.classAttendance case final classes?) ...[
                  Text(
                    context
                        .tr(
                          classes.length == 1
                              ? 'engagement.classesOne'
                              : 'engagement.classes',
                        )
                        .replaceAll('{n}', '${classes.length}'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  for (final c in classes.take(3))
                    Text(
                      '${fmt.format(c.date)}${c.durationMinutes == null ? '' : ' · ${c.durationMinutes} ${context.tr('activity.min')}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
                if (g.challenges case final challenges?) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  Text(
                    context.tr('gymShare.challenges'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  SharedChallengesList(items: challenges),
                ],
                if (g.gymWorkouts case final workouts?) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  Text(
                    context
                        .tr(
                          workouts.length == 1
                              ? 'engagement.workoutsOne'
                              : 'engagement.workouts',
                        )
                        .replaceAll('{n}', '${workouts.length}'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  for (final w in workouts.take(3))
                    Text(
                      '${fmt.format(w.date)} · ${activityTypeLabel(context, ActivityType.fromWire(w.type))}${w.durationMinutes == null ? '' : ' · ${w.durationMinutes} ${context.tr('activity.min')}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Owner home: membership engagement for the selected gym — who's coming,
/// who's slipping away, who's new — from the gym's own check-ins.
class GymEngagementCard extends StatefulWidget {
  const GymEngagementCard({super.key, required this.gymId, this.onOpenMember});

  final String? gymId;
  final ValueChanged<String>? onOpenMember;

  @override
  State<GymEngagementCard> createState() => _GymEngagementCardState();
}

class _GymEngagementCardState extends State<GymEngagementCard> {
  GymEngagementOverview? _o;
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(GymEngagementCard old) {
    super.didUpdateWidget(old);
    _maybeLoad();
  }

  void _maybeLoad() {
    if (_loadedFor == widget.gymId && _o != null) return;
    _loadedFor = widget.gymId;
    _load();
  }

  Future<void> _load() async {
    final gymId = widget.gymId;
    try {
      final res = await AppScope.of(context).api.ownerEngagement(gymId: gymId);
      if (mounted && gymId == widget.gymId) {
        setState(() => _o = GymEngagementOverview.fromJson(res));
      }
    } catch (_) {
      // Leave the card out rather than show an error on the dashboard.
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    if (o == null || o.members == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    Widget band(String key, int n, Color? color) => Expanded(
      child: Column(
        children: [
          Text(
            '$n',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            engagementStatusLabel(context, key),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
    return FFCard(
      key: const Key('gym-engagement-card'),
      margin: const EdgeInsets.only(top: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('engagement.dashboardTitle'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            context
                .tr('engagement.dashboardBody')
                .replaceAll('{n}', '${o.members}')
                .replaceAll('{new}', '${o.newThisMonth}'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Row(
            children: [
              band('active', o.active, theme.colorScheme.primary),
              band('slipping', o.slipping, FFTokens.warning500),
              band('at_risk', o.atRisk, FFTokens.warning500),
              band('lapsed', o.lapsed, null),
            ],
          ),
          if (o.checkIn.isNotEmpty) ...[
            const Divider(height: FFTokens.spacingLg),
            Text(
              context.tr('engagement.checkInWith'),
              style: theme.textTheme.labelLarge,
            ),
            for (final c in o.checkIn.take(5))
              ListTile(
                key: Key('engagement-member-${c.memberId}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: FFAvatar(name: c.displayName ?? '?'),
                title: Text(c.displayName ?? ''),
                subtitle: Text(
                  context
                      .tr('engagement.lastDaysAgo')
                      .replaceAll(
                        '{n}',
                        '${c.engagement.daysSinceLastVisit ?? '-'}',
                      ),
                ),
                trailing: widget.onOpenMember == null
                    ? null
                    : const Icon(Icons.chevron_right),
                onTap: widget.onOpenMember == null
                    ? null
                    : () => widget.onOpenMember!(c.memberId),
              ),
          ],
        ],
      ),
    );
  }
}
