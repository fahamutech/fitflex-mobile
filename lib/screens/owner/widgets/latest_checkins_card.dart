import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';

/// Owner Home: the last few check-ins at the active gym, so the screen shows
/// the gym is live. Members appear by their public ID, as on the full list.
/// "FitFlex Pro", "Your own plan", "Trainer pass" or "Company benefit".
String checkinPlanLabel(BuildContext context, Map<String, dynamic> c) {
  final type = c['subscriptionType']?.toString();
  final tier = c['passTier']?.toString();
  switch (type) {
    case 'direct_sub':
      return context.tr('owner.latest.ownPlan');
    case 'trainer_pass':
    case 'trainer_home':
      return context.tr('owner.latest.trainer');
    case 'b2b_benefit':
      return context.tr('owner.latest.company');
  }
  if (tier == null || tier.isEmpty) return context.tr('owner.latest.fitflex');
  final key = 'pass.$tier';
  final name = context.tr(key);
  return context
      .tr('owner.latest.fitflexTier')
      .replaceAll('{tier}', name == key ? tier : name);
}

/// Who checked in: their name when the server sent one, else the public ID.
String checkinVisitorLabel(Map<String, dynamic> c) {
  final name = c['displayName']?.toString().trim();
  final handle = c['username']?.toString().trim();
  final base = (name != null && name.isNotEmpty)
      ? name
      : (c['memberPublicId']?.toString() ??
            c['memberName']?.toString() ??
            c['memberId']?.toString() ??
            '');
  // A gym sees the name with the member's username beside it.
  return (handle != null && handle.isNotEmpty) ? '$base (@$handle)' : base;
}

class LatestCheckinsCard extends StatefulWidget {
  const LatestCheckinsCard({
    super.key,
    required this.gymId,
    required this.onSeeAll,
    this.version = 0,
    this.now,
    this.limit = 3,
  });

  final String gymId;
  final VoidCallback onSeeAll;

  /// Changes when the dashboard refreshes, so pulling to refresh reloads this.
  final int version;

  /// Injectable clock for tests.
  final DateTime? now;
  final int limit;

  @override
  State<LatestCheckinsCard> createState() => _LatestCheckinsCardState();
}

class _LatestCheckinsCardState extends State<LatestCheckinsCard> {
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rows == null && !_failed) _load();
  }

  @override
  void didUpdateWidget(LatestCheckinsCard old) {
    super.didUpdateWidget(old);
    if (old.gymId != widget.gymId || old.version != widget.version) {
      _rows = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final gymId = widget.gymId;
    try {
      final res = await AppScope.of(context).api.ownerGymCheckins(gymId);
      if (!mounted || gymId != widget.gymId) return;
      setState(
        () => _rows = [
          for (final r in res.whereType<Map>()) Map<String, dynamic>.from(r),
        ],
      );
    } catch (_) {
      // Optional block: Home stands without it.
      if (mounted) setState(() => _failed = true);
    }
  }

  String _when(DateTime at) {
    final now = widget.now ?? DateTime.now();
    final lang = Localizations.localeOf(context).languageCode;
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay
        ? DateFormat.Hm(lang).format(at)
        : DateFormat('EEE d MMM', lang).format(at);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final rows = _rows;
    final latest = [
      for (final r in rows ?? const <Map<String, dynamic>>[])
        if (DateTime.tryParse(r['timestamp']?.toString() ?? '') case final at?)
          (row: r, at: at.toLocal()),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return Column(
      key: const Key('owner-latest-checkins'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: FFSectionTitle(context.tr('owner.latest.title'))),
            if (latest.isNotEmpty)
              FFButton(
                key: const Key('owner-latest-checkins-all'),
                label: context.tr('owner.latest.seeAll'),
                onPressed: widget.onSeeAll,
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
              ),
          ],
        ),
        if (rows == null)
          const Padding(
            padding: EdgeInsets.all(FFTokens.spacingMd),
            child: Center(child: FFSpinner(size: 24)),
          )
        else if (latest.isEmpty)
          FFCard(
            child: Text(
              context.tr('owner.latest.empty'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          FFCard(
            padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingMd),
            child: Column(
              children: [
                for (var i = 0; i < latest.take(widget.limit).length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: FFTokens.spacingSm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: checkinVisitorLabel(latest[i].row),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      ' · ${checkinPlanLabel(context, latest[i].row)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: FFTokens.spacingSm),
                        Text(
                          _when(latest[i].at),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
