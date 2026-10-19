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
import '../../shared/models.dart';
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

  /// Check-ins fetched here by date range. The Activity tab only holds the
  /// newest 50, which a frequent visitor passes within weeks.
  final _visits = <String, CheckIn>{};

  /// Start of the oldest window loaded so far.
  late DateTime _loadedFrom = () {
    final now = widget.now ?? DateTime.now();
    return DateTime(now.year, now.month, now.day - activityHistoryDays + 1);
  }();

  bool _loading = false;

  /// The first batch of visits, for the window the page opens on.
  bool _visitsLoading = true;
  bool _visitsFailed = false;
  bool _reachedEnd = false;
  bool _failed = false;

  /// Empty windows in a row before "Show older" gives up: a year, so a
  /// long break doesn't hide what came before it.
  static const _maxEmptyWindows = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRecentVisits();
    });
  }

  Future<void> _loadRecentVisits() async {
    final now = widget.now ?? DateTime.now();
    setState(() {
      _visitsLoading = true;
      _visitsFailed = false;
    });
    final added = await _fetchVisits(
      _loadedFrom,
      now.add(const Duration(days: 1)),
    );
    if (!mounted) return;
    setState(() {
      _visitsLoading = false;
      _visitsFailed = added < 0;
    });
  }

  /// Visits from [from] up to [to]; how many were new, or -1 on failure. A failure only
  /// means fewer visits shown, so it never blocks the activities.
  Future<int> _fetchVisits(DateTime from, DateTime to) async {
    try {
      final rows = await AppScope.of(
        context,
      ).api.myCheckins(from: from, to: to);
      if (!mounted) return 0;
      var added = 0;
      setState(() {
        for (final c in rows.whereType<Map<String, dynamic>>().map(
          CheckIn.fromJson,
        )) {
          if (c.id.isNotEmpty && _visits[c.id] == null) {
            _visits[c.id] = c;
            added++;
          }
        }
      });
      return added;
    } catch (_) {
      return -1;
    }
  }

  /// Fetches window after window back until one has something in it, or
  /// [_maxEmptyWindows] in a row are empty.
  Future<void> _loadOlder() async {
    final scope = AppScope.of(context);
    final userId = scope.auth.user?['id']?.toString() ?? '';
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      for (var empty = 0; empty < _maxEmptyWindows; empty++) {
        final to = _loadedFrom;
        final from = DateTime(to.year, to.month, to.day - activityHistoryDays);
        final (acts, newVisits) = await (
          scope.activity.getActivities(userId: userId, from: from, to: to),
          _fetchVisits(from, to),
        ).wait;
        // A failed visit fetch only means fewer visits; keep going.
        if (!mounted) return;
        final known = {for (final a in _older) a.id};
        final fresh = acts
            .where((a) => !known.contains(a.id) && a.startedAt.isBefore(to))
            .toList();
        setState(() {
          _older.addAll(fresh);
          _loadedFrom = from;
        });
        if (fresh.isNotEmpty || newVisits > 0) {
          setState(() => _loading = false);
          return;
        }
      }
      setState(() {
        _reachedEnd = true;
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
    final visits = {for (final c in data.checkins) c.id: c, ..._visits}.values
        .where((c) {
          final at = DateTime.tryParse(c.timestamp);
          return at != null && !at.toLocal().isBefore(_loadedFrom);
        })
        .toList();
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
        if (_visitsLoading)
          const Padding(
            key: Key('history-visits-loading'),
            padding: EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Center(child: FFSpinner(size: 20)),
          )
        else if (_visitsFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('activity.historyVisitsFailed'),
                    key: const Key('history-visits-failed'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                FFButton(
                  label: context.tr('common.retry'),
                  onPressed: _loadRecentVisits,
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                ),
              ],
            ),
          ),
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
                  DateFormat(
                    'd MMM y',
                    Localizations.localeOf(context).languageCode,
                  ).format(_loadedFrom),
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
    final lang = Localizations.localeOf(context).languageCode;
    final month = DateFormat('MMM y', lang).format(first);
    final dates =
        '${first.day}–${last.day} ${DateFormat('MMM', lang).format(last)}';
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
          // Same weight as a section title, and a heading for screen
          // readers, which hear "Week 3, October 2026" rather than "W3".
          Expanded(
            child: Semantics(
              header: true,
              label: context
                  .tr('activity.weekSpoken')
                  .replaceAll('{n}', '${week.week}')
                  .replaceAll(
                    '{month}',
                    DateFormat('MMMM y', lang).format(first),
                  ),
              excludeSemantics: true,
              child: Text(
                context
                    .tr('activity.week')
                    .replaceAll('{n}', '${week.week}')
                    .replaceAll('{month}', month),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Text(dates, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
