// Check-in Successful confirmation sheet — mirrors the design's success card:
// a green check, member identity, check-in time, who checked them in, and Done.

import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../data/member_models.dart';
import 'member_format.dart';

Future<void> showCheckInSuccessSheet(
  BuildContext context, {
  required MemberDetail member,
  required DateTime checkInTime,
  required String checkedInBy,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _CheckInSuccessSheet(
      member: member,
      checkInTime: checkInTime,
      checkedInBy: checkedInBy,
    ),
  );
}

class _CheckInSuccessSheet extends StatelessWidget {
  const _CheckInSuccessSheet({
    required this.member,
    required this.checkInTime,
    required this.checkedInBy,
  });

  final MemberDetail member;
  final DateTime checkInTime;
  final String checkedInBy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      member.memberType == OwnerMemberType.direct
          ? context.tr('memberType.direct')
          : context.tr('memberType.fitflex'),
      if (member.plan?.tier != null) _capitalize(member.plan!.tier!),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('members.checkInSuccess'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: FFTokens.spacingLg),
            Row(
              children: [
                FFAvatar(
                  name: member.resolvedName,
                  src: member.photoUrl,
                  size: FFAvatarSize.lg,
                ),
                const SizedBox(width: FFTokens.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.resolvedName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: FFTokens.spacing2xs),
                      Text(
                        subtitleParts.join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingMd),
            const Divider(height: 1),
            const SizedBox(height: FFTokens.spacingMd),
            _row(
              context,
              context.tr('members.checkInTime'),
              formatRelative(context, checkInTime),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            _row(context, context.tr('members.checkedInBy'), checkedInBy),
            const SizedBox(height: FFTokens.spacingLg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.tr('members.done')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(
          value,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static String _capitalize(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
}
