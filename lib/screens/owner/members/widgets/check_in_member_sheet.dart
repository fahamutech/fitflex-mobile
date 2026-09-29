// Shared "Check-in Member" bottom sheet — matches the design's check-in flow:
// a confirmation step (member identity + Confirm Check-in) that transitions
// into the success state (green check, check-in time, who checked them in).
// Replaces the previous "check in directly, then show a sheet" behaviour.

import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../data/member_models.dart';
import 'member_format.dart';

/// Opens the check-in sheet. [onConfirm] performs the actual check-in and
/// returns the check-in time on success, or null on failure.
Future<void> showCheckInMemberSheet(
  BuildContext context, {
  required MemberDetail member,
  required String checkedInBy,
  required Future<DateTime?> Function() onConfirm,
  String? Function()? failureMessage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CheckInMemberSheet(
      member: member,
      checkedInBy: checkedInBy,
      onConfirm: onConfirm,
      failureMessage: failureMessage,
    ),
  );
}

class _CheckInMemberSheet extends StatefulWidget {
  const _CheckInMemberSheet({
    required this.member,
    required this.checkedInBy,
    required this.onConfirm,
    this.failureMessage,
  });

  final MemberDetail member;
  final String checkedInBy;
  final Future<DateTime?> Function() onConfirm;

  /// Why the check-in failed, when the caller knows (e.g. a FitFlex pass
  /// member who must scan their QR instead); otherwise a generic error.
  final String? Function()? failureMessage;

  @override
  State<_CheckInMemberSheet> createState() => _CheckInMemberSheetState();
}

class _CheckInMemberSheetState extends State<_CheckInMemberSheet> {
  bool _busy = false;
  DateTime? _checkInTime; // non-null => success state
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final time = await widget.onConfirm();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (time != null) {
        _checkInTime = time;
      } else {
        _error =
            widget.failureMessage?.call() ?? context.tr('owner.errorGeneric');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final subtitleParts = <String>[
      member.memberType == OwnerMemberType.direct
          ? context.tr('memberType.direct')
          : context.tr('memberType.fitflex'),
      if (member.plan?.tier != null) _capitalize(member.plan!.tier!),
    ];
    final success = _checkInTime != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          FFTokens.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(success: success),
            const SizedBox(height: FFTokens.spacingLg),
            _MemberRow(member: member, subtitle: subtitleParts.join(' · ')),
            const SizedBox(height: FFTokens.spacingMd),
            const Divider(height: 1),
            const SizedBox(height: FFTokens.spacingMd),
            if (success) ...[
              _row(
                context,
                context.tr('members.checkInTime'),
                formatRelative(context, _checkInTime),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              _row(
                context,
                context.tr('members.checkedInBy'),
                widget.checkedInBy,
              ),
              const SizedBox(height: FFTokens.spacingLg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('members.done')),
                ),
              ),
            ] else ...[
              Text(
                context.tr('members.checkInPrompt'),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: FFTokens.spacingLg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _confirm,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.qr_code, size: FFTokens.iconSm),
                  label: Text(context.tr('members.checkInConfirm')),
                ),
              ),
            ],
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

class _Header extends StatelessWidget {
  const _Header({required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            success ? Icons.check_circle : Icons.qr_code_scanner,
            size: 40,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          success
              ? context.tr('members.checkInSuccess')
              : context.tr('members.checkInMember'),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.subtitle});

  final MemberDetail member;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
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
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
