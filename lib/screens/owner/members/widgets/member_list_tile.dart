// Member list row — composes shared FFAvatar + FFBadge per the design.
// One tappable card row: avatar, name + type·tier subtitle, status badge,
// chevron, and a footer line with the last activity time.

import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../data/member_models.dart';
import 'member_format.dart';
import 'member_presentation.dart';

class MemberListTile extends StatelessWidget {
  const MemberListTile({super.key, required this.member, required this.onTap});

  final OwnerMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      member.memberType.label(context),
      if (member.tier != null && member.tier!.isNotEmpty)
        _capitalize(member.tier!),
    ];

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          ),
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: FFTokens.spacing2xs),
                        Text(
                          subtitleParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  MemberStatusBadge(status: member.status),
                  const SizedBox(width: FFTokens.spacingXs),
                  Icon(
                    Icons.chevron_right,
                    size: FFTokens.iconMd,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (member.lastCheckinAt != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: FFTokens.iconXs,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: FFTokens.spacingXs + 2),
                    Text(
                      formatRelative(context, member.lastCheckinAt),
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _capitalize(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
}
