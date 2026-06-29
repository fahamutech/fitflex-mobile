// Filter Members bottom sheet — member type + status multi-pill selector.
// Returns the chosen filters; the controller performs the reload.

import 'package:flutter/material.dart';

import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../data/member_models.dart';
import '../member_controller.dart';
import 'member_presentation.dart';

class MemberFilterResult {
  final MemberTypeFilter type;
  final OwnerMemberStatus? status;
  const MemberFilterResult({required this.type, required this.status});
}

Future<MemberFilterResult?> openFilterMembersSheet(
  BuildContext context, {
  required MemberTypeFilter type,
  required OwnerMemberStatus? status,
}) {
  return showModalBottomSheet<MemberFilterResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _FilterMembersSheet(type: type, status: status),
  );
}

class _FilterMembersSheet extends StatefulWidget {
  const _FilterMembersSheet({required this.type, required this.status});

  final MemberTypeFilter type;
  final OwnerMemberStatus? status;

  @override
  State<_FilterMembersSheet> createState() => _FilterMembersSheetState();
}

class _FilterMembersSheetState extends State<_FilterMembersSheet> {
  late MemberTypeFilter _type = widget.type;
  late OwnerMemberStatus? _status = widget.status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('members.filterTitle'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('members.memberTypeLabel'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingSm,
              children: [
                for (final t in MemberTypeFilter.values)
                  _Pill(
                    label: _typeLabel(context, t),
                    selected: _type == t,
                    onTap: () => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingLg),
            Text(
              context.tr('members.statusLabel'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingSm,
              children: [
                _Pill(
                  label: context.tr('members.filterAll'),
                  selected: _status == null,
                  onTap: () => setState(() => _status = null),
                ),
                for (final s in OwnerMemberStatus.values)
                  _Pill(
                    label: s.label(context),
                    selected: _status == s,
                    onTap: () => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingXl),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                MemberFilterResult(type: _type, status: _status),
              ),
              child: Text(context.tr('members.applyFilters')),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                const MemberFilterResult(
                  type: MemberTypeFilter.all,
                  status: null,
                ),
              ),
              child: Text(context.tr('members.clearFilters')),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(BuildContext context, MemberTypeFilter t) => switch (t) {
    MemberTypeFilter.all => context.tr('members.filterAll'),
    MemberTypeFilter.direct => context.tr('memberType.direct'),
    MemberTypeFilter.fitflex => context.tr('memberType.fitflex'),
  };
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: FFTokens.motionFast,
        padding: const EdgeInsets.symmetric(
          horizontal: FFTokens.spacingMd,
          vertical: FFTokens.spacingSm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(FFTokens.radiusFull),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
