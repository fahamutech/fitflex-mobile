import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../../../shared/pass_gyms.dart';
import 'gym_filters.dart';

/// The tier name as the member reads it elsewhere ("Pro", "Basic"…).
String passTierName(BuildContext context, String tierId) =>
    context.tr('pass.$tierId');

/// Label for a gym tier group ("Standard", "Mid-tier"…).
String gymTierGroupLabel(BuildContext context, String tier) =>
    tierLabel(context, tier);

/// A one-line split of [gyms] by gym tier: "9 Standard · 5 Mid-tier".
String gymSplitSummary(BuildContext context, List<Gym> gyms) =>
    groupGymsByTier(gyms).entries
        .map((e) => '${e.value.length} ${gymTierGroupLabel(context, e.key)}')
        .join(' · ');

/// Opens the list of active gyms a pass tier opens, so the member can review
/// them before choosing. [highlightIds] marks gyms an upgrade adds. When
/// [onChoose] is given the sheet ends in a button that picks this tier.
Future<void> showPassGymsSheet(
  BuildContext context, {
  required String tierId,
  required String? gymAccess,
  required List<Gym> gyms,
  Set<String> highlightIds = const {},
  VoidCallback? onChoose,
}) {
  final router = GoRouter.of(context);
  final name = passTierName(context, tierId);
  final title = context.tr('passGyms.sheetTitle').replaceFirst('{tier}', name);
  return showFFSheet<void>(
    context,
    title: title,
    child: PassGymsList(
      gyms: gymsForPass(gymAccess, gyms),
      highlightIds: highlightIds,
      chooseLabel: onChoose == null
          ? null
          : context.tr('passGyms.choose').replaceFirst('{tier}', name),
      onChoose: onChoose,
      onOpenGym: (g) => router.push('/member/gyms/${g.id}'),
    ),
  );
}

/// The searchable, tier-grouped list inside the sheet.
class PassGymsList extends StatefulWidget {
  const PassGymsList({
    super.key,
    required this.gyms,
    this.highlightIds = const {},
    this.chooseLabel,
    this.onChoose,
    this.onOpenGym,
  });

  final List<Gym> gyms;
  final Set<String> highlightIds;
  final String? chooseLabel;
  final VoidCallback? onChoose;
  final void Function(Gym gym)? onOpenGym;

  @override
  State<PassGymsList> createState() => _PassGymsListState();
}

class _PassGymsListState extends State<PassGymsList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.gyms
        : widget.gyms
              .where(
                (g) =>
                    g.name.toLowerCase().contains(q) ||
                    g.location.toLowerCase().contains(q),
              )
              .toList();
    final groups = groupGymsByTier(shown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.gyms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              context.tr('passGyms.none'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          )
        else ...[
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr('member.searchGyms'),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.gyms.length} · ${gymSplitSummary(context, widget.gyms)}',
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                context.tr('passGyms.empty'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                '${gymTierGroupLabel(context, entry.key)} · ${entry.value.length}',
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final g in entry.value)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: g.location.isEmpty
                    ? null
                    : Text(
                        g.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: widget.highlightIds.contains(g.id)
                    ? FFBadge(
                        label: context.tr('passGyms.new'),
                        tone: FFBadgeTone.success,
                      )
                    : const Icon(Icons.chevron_right, size: 18),
                onTap: widget.onOpenGym == null
                    ? null
                    : () {
                        Navigator.of(context).maybePop();
                        widget.onOpenGym!(g);
                      },
              ),
          ],
          const SizedBox(height: 12),
          Text(context.tr('passGyms.note'), style: theme.textTheme.bodySmall),
        ],
        if (widget.onChoose != null && widget.chooseLabel != null) ...[
          const SizedBox(height: FFTokens.spacingMd),
          FilledButton(
            onPressed: () {
              Navigator.of(context).maybePop();
              widget.onChoose!();
            },
            child: Text(widget.chooseLabel!),
          ),
        ],
      ],
    );
  }
}
