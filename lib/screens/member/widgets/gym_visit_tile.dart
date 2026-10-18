import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/activity/activity.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../member_log_activity_page.dart' show openLogActivity;
import 'activity_widgets.dart';

/// One row of Recent activity: an activity on its own, or a gym visit with
/// whatever the member logged during it.
sealed class RecentEntry {
  const RecentEntry();

  DateTime get at;
}

class RecentActivityEntry extends RecentEntry {
  const RecentActivityEntry(this.activity);

  final Activity activity;

  @override
  DateTime get at => activity.startedAt;
}

class RecentVisitEntry extends RecentEntry {
  const RecentVisitEntry(this.checkin, this.at, this.activities);

  final CheckIn checkin;

  @override
  final DateTime at;

  /// Activities at the same gym on the same day, oldest first.
  final List<Activity> activities;
}

DateTime _day(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Activities and gym visits, newest first. A check-in is still not an
/// activity: it adds nothing to totals, goals or streaks. An activity with
/// the visit's `gymId` on the same day sits inside that visit (the closest
/// visit in time, if there were several) instead of being listed twice.
List<RecentEntry> recentTimeline(
  List<Activity> activities,
  List<CheckIn> checkins, {
  int limit = 8,
}) {
  final visits = <(CheckIn, DateTime)>[
    for (final c in checkins)
      if (DateTime.tryParse(c.timestamp) case final at?) (c, at.toLocal()),
  ];
  final linked = <CheckIn, List<Activity>>{for (final v in visits) v.$1: []};
  final standalone = <Activity>[];
  for (final a in activities) {
    final gymId = a.gymId;
    final candidates = gymId == null
        ? const <(CheckIn, DateTime)>[]
        : visits
              .where(
                (v) => v.$1.gymId == gymId && _day(v.$2) == _day(a.startedAt),
              )
              .toList();
    if (candidates.isEmpty) {
      standalone.add(a);
      continue;
    }
    candidates.sort(
      (x, y) => x.$2
          .difference(a.startedAt)
          .abs()
          .compareTo(y.$2.difference(a.startedAt).abs()),
    );
    linked[candidates.first.$1]!.add(a);
  }
  final entries = <RecentEntry>[
    for (final a in standalone) RecentActivityEntry(a),
    for (final v in visits)
      RecentVisitEntry(
        v.$1,
        v.$2,
        linked[v.$1]!..sort((x, y) => x.startedAt.compareTo(y.startedAt)),
      ),
  ]..sort((x, y) => y.at.compareTo(x.at));
  return entries.take(limit).toList();
}

/// A gym visit in Recent activity. Tap to open it: what was logged during
/// the visit, and a way to log what the member did.
class GymVisitTile extends StatefulWidget {
  const GymVisitTile({super.key, required this.entry});

  final RecentVisitEntry entry;

  @override
  State<GymVisitTile> createState() => _GymVisitTileState();
}

class _GymVisitTileState extends State<GymVisitTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.entry;
    final c = e.checkin;
    final gymName = c.gym?.name ?? c.gymId ?? '';
    final logged = e.activities.length;
    final subtitle = [
      DateFormat('EEE d MMM · HH:mm').format(e.at.toLocal()),
      logged == 0
          ? context.tr('visit.nothingLogged')
          : context.tr('visit.logged').replaceAll('{n}', '$logged'),
    ].join(' · ');
    final muted = theme.colorScheme.onSurfaceVariant;
    return FFCard(
      key: Key('visit-${c.id}'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('visit-toggle-${c.id}'),
            borderRadius: BorderRadius.circular(FFTokens.radiusMd),
            onTap: () => setState(() => _open = !_open),
            child: Semantics(
              button: true,
              expanded: _open,
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                child: Row(
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: FFTokens.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context
                                .tr('visit.title')
                                .replaceAll('{gym}', gymName),
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: muted,
                      size: FFTokens.iconMd,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FFTokens.spacingMd,
                0,
                FFTokens.spacingMd,
                FFTokens.spacingMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (logged == 0)
                    Text(
                      context.tr('visit.prompt'),
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    for (final a in e.activities)
                      ActivityTimelineTile(activity: a),
                  const SizedBox(height: FFTokens.spacingSm),
                  FFButton(
                    key: Key('visit-log-${c.id}'),
                    label: context.tr(
                      logged == 0 ? 'visit.log' : 'visit.logAnother',
                    ),
                    onPressed: () =>
                        openLogActivity(context, gymId: c.gymId, at: e.at),
                    variant: logged == 0
                        ? FFButtonVariant.primary
                        : FFButtonVariant.secondary,
                    size: FFButtonSize.sm,
                    icon: Icons.add,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
