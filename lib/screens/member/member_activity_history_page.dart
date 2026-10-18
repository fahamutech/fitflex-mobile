import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/activity.dart';
import '../../shared/activity/activity_config.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/gym_visit_tile.dart';

/// Activity → Recent activity → View more: every activity and gym visit,
/// newest first, in weeks of the month (W4 · Jan 2026, W3 · Jan 2026…).
///
/// Starts with what the Activity tab already holds (the last
/// [activityHistoryDays] days); "Show older" fetches the window before that.
class MemberActivityHistoryPage extends StatefulWidget {
  const MemberActivityHistoryPage({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<MemberActivityHistoryPage> createState() =>
      _MemberActivityHistoryPageState();
}

class _MemberActivityHistoryPageState extends State<MemberActivityHistoryPage> {
  /// Fetched here, older than what the Activity tab loaded.
  final _older = <Activity>[];

  /// Start of the oldest window loaded so far.
  late DateTime _loadedFrom = () {
    final now = widget.now ?? DateTime.now();
    return DateTime(now.year, now.month, now.day - activityHistoryDays + 1);
  }();

  bool _loading = false;
  bool _reachedEnd = false;
  bool _failed = false;

  Future<void> _loadOlder() async {
    final scope = AppScope.of(context);
    final userId = scope.auth.user?['id']?.toString() ?? '';
    final to = _loadedFrom;
    final from = DateTime(to.year, to.month, to.day - activityHistoryDays);
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final acts = await scope.activity.getActivities(
        userId: userId,
        from: from,
        to: to,
      );
      if (!mounted) return;
      final known = {for (final a in _older) a.id};
      setState(() {
        _older.addAll(
          acts.where((a) => !known.contains(a.id) && a.startedAt.isBefore(to)),
        );
        _loadedFrom = from;
        // A whole window with nothing in it: treat it as the beginning.
        _reachedEnd = acts.isEmpty;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = MemberDataScope.of(context);
    final ids = {for (final a in data.activities) a.id};
    final activities = [
      ...data.activities,
      ..._older.where((a) => !ids.contains(a.id)),
    ];
    // Visits older than what's loaded can't show what was logged during
    // them yet, so they wait for "Show older" too.
    final visits = data.checkins.where((c) {
      final at = DateTime.tryParse(c.timestamp);
      return at != null && !at.toLocal().isBefore(_loadedFrom);
    }).toList();
    final groups = groupByMonthWeek(
      recentTimeline(activities, visits, limit: null),
    );

    return ListView(
      key: const Key('activity-history'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            label: context.tr('activity.title'),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go(AppRoutes.memberActivity),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            icon: Icons.arrow_back,
          ),
        ),
        FFPageHeader(title: context.tr('activity.history')),
        if (groups.isEmpty)
          FFEmptyState(title: context.tr('activity.noActivity'))
        else
          for (final (week, entries) in groups) ...[
            _WeekHeader(week: week),
            for (final e in entries) recentEntryTile(e),
          ],
        const SizedBox(height: FFTokens.spacingMd),
        if (_failed)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Text(
              context.tr('activity.historyLoadFailed'),
              key: const Key('history-load-failed'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (_reachedEnd)
          Text(
            context
                .tr('activity.historyStart')
                .replaceAll(
                  '{date}',
                  DateFormat('d MMM y').format(_loadedFrom),
                ),
            key: const Key('history-end'),
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          )
        else
          FFButton(
            key: const Key('history-older'),
            label: context.tr('activity.showOlder'),
            onPressed: _loading ? null : _loadOlder,
            loading: _loading,
            variant: FFButtonVariant.secondary,
            fullWidth: true,
          ),
      ],
    );
  }
}

/// "W4 · Jan 2026" with the week's dates, "22–31 Jan".
class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.week});

  final MonthWeek week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (first, last) = monthWeekRange(week);
    final month = DateFormat('MMM y').format(first);
    final dates = '${first.day}–${last.day} ${DateFormat('MMM').format(last)}';
    return Padding(
      key: Key('history-week-${week.year}-${week.month}-${week.week}'),
      padding: const EdgeInsets.only(
        top: FFTokens.spacingMd,
        bottom: FFTokens.spacingSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              context
                  .tr('activity.week')
                  .replaceAll('{n}', '${week.week}')
                  .replaceAll('{month}', month),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            dates,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
