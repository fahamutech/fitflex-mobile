// Member Details screen — pixel-aligned to the design's "Member Details" layout.
// UI only; data + actions come from [MemberDetailController].

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../owner_shell.dart';
import 'data/member_models.dart';
import 'data/member_repository.dart';
import 'member_controller.dart';
import 'widgets/add_member_sheet.dart';
import 'widgets/check_in_member_sheet.dart';
import 'widgets/member_format.dart';
import 'widgets/member_presentation.dart';
import 'widgets/renew_member_sheet.dart';
import '../widgets/gym_engagement_widgets.dart';
import '../communications/widgets/history_widgets.dart';

class MemberDetailPage extends StatefulWidget {
  const MemberDetailPage({super.key, required this.memberId});

  final String memberId;

  @override
  State<MemberDetailPage> createState() => _MemberDetailPageState();
}

class _MemberDetailPageState extends State<MemberDetailPage> {
  MemberDetailController? _controller;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _controller = MemberDetailController(
      MemberRepository(AppScope.of(context).api),
      widget.memberId,
    );
    _controller!.load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String get _checkedInBy {
    final data = OwnerDataScope.maybeOf(context);
    final name = data?.displayName ?? '';
    return name.isEmpty ? context.tr('members.admin') : name;
  }

  Future<void> _checkIn(MemberDetail detail) async {
    // Route the check-in through the shared confirmation sheet instead of
    // checking in directly: the sheet confirms, performs the action, then
    // shows the success state.
    await showCheckInMemberSheet(
      context,
      member: detail,
      checkedInBy: _checkedInBy,
      onConfirm: () async {
        final ok = await _controller!.checkIn();
        if (!ok) return null;
        final updated = _controller!.detail ?? detail;
        return updated.checkInSummary.lastCheckinAt ?? DateTime.now();
      },
      failureMessage: () => context.tr(_failureKey()),
    );
  }

  /// Why an action on this member failed, in words the owner can act on.
  String _failureKey() => switch (_controller?.errorCode) {
    'direct_membership_required' => 'members.directOnly',
    'member_manages_own_details' => 'members.ownDetails',
    'membership_expired' => 'error.reason.membershipExpired',
    'member_suspended' => 'members.planPaused',
    _ => 'owner.errorGeneric',
  };

  Future<void> _edit(MemberDetail detail) async {
    final payload = await openEditMemberSheet(context, member: detail);
    if (payload == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _controller!.editMember(payload);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.tr(ok ? 'members.memberUpdated' : _failureKey())),
      ),
    );
  }

  Future<void> _renew(MemberDetail detail) async {
    final payload = await openRenewMemberSheet(context, current: detail.plan);
    if (payload == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _controller!.renew(payload);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.tr(ok ? 'members.renewed' : 'owner.errorGeneric'),
        ),
      ),
    );
  }

  Future<void> _toggleSuspend(MemberDetail detail) async {
    final messenger = ScaffoldMessenger.of(context);
    final suspend = !detail.isSuspended;
    if (suspend) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('members.suspend')),
          content: Text(context.tr('members.suspendConfirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('member.cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('members.suspend')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final ok = await _controller!.toggleSuspend(suspend: suspend);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            !ok
                ? _failureKey()
                : (suspend ? 'members.suspended' : 'members.reactivated'),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('members.memberDetails'))),
      body: controller == null
          ? const Center(child: FFSpinner())
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.loading && controller.detail == null) {
                  return const Center(child: FFSpinner());
                }
                if (controller.error != null && controller.detail == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(FFTokens.spacingLg),
                      child: FFEmptyState(
                        title: context.tr('members.errorLoading'),
                        action: OutlinedButton(
                          onPressed: controller.load,
                          child: Text(context.tr('members.retry')),
                        ),
                      ),
                    ),
                  );
                }
                final detail = controller.detail!;
                return Column(
                  children: [
                    Expanded(
                      child: _DetailBody(
                        controller: controller,
                        detail: detail,
                        onViewCheckins: () => context.push(
                          '/owner/members/${widget.memberId}/checkins',
                        ),
                        onViewPayments: () => context.push(
                          '/owner/members/${widget.memberId}/payments',
                        ),
                      ),
                    ),
                    // A FitFlex Pass visitor is FitFlex's member, not the gym's:
                    // the gym sees their visits but can't edit or suspend them.
                    if (detail.memberType == OwnerMemberType.fitflex)
                      Padding(
                        key: const Key('member-fitflex-note'),
                        padding: const EdgeInsets.all(FFTokens.spacingMd),
                        child: FFAlert(
                          message: context.tr('members.fitflexManaged'),
                        ),
                      )
                    else
                      _ActionBar(
                        detail: detail,
                        busy: controller.busy,
                        onCheckIn: () => _checkIn(detail),
                        onRenew: () => _renew(detail),
                        onEdit: () => _edit(detail),
                        onSuspend: () => _toggleSuspend(detail),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.controller,
    required this.detail,
    required this.onViewCheckins,
    required this.onViewPayments,
  });

  final MemberDetailController controller;
  final MemberDetail detail;
  final VoidCallback onViewCheckins;
  final VoidCallback onViewPayments;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        _ProfileCard(detail: detail),
        const SizedBox(height: FFTokens.spacingMd),
        _CheckInSummaryCard(controller: controller),
        // Visit patterns, plus only what the member shares with this gym.
        GymMemberActivityCard(memberId: detail.id),
        if (detail.plan != null) ...[
          const SizedBox(height: FFTokens.spacingMd),
          _PlanCard(plan: detail.plan!),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        _RecentCheckinsCard(
          checkins: detail.recentCheckins,
          onViewAll: onViewCheckins,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        _PaymentHistoryCard(
          payments: detail.paymentHistory,
          onViewAll: onViewPayments,
        ),
        // Messages this gym sent them (hidden without the permission).
        MemberMessagesCard(memberId: detail.id),
      ],
    );
  }
}

/// Thin vertical divider used to separate the three KPI columns inside the
/// member detail section cards (matches the design's gridlines).
class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: FFTokens.spacingSm),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// "View all" text link shown in a section card header.
class _ViewAllLink extends StatelessWidget {
  const _ViewAllLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FFTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FFTokens.spacing2xs,
          vertical: 2,
        ),
        child: Text(
          context.tr('members.viewAll'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.detail});

  final MemberDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      detail.memberType.label(context),
      if (detail.plan?.tier != null) _cap(detail.plan!.tier!),
    ];
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FFAvatar(
                name: detail.resolvedName,
                src: detail.photoUrl,
                size: FFAvatarSize.lg,
              ),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.resolvedName,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: FFTokens.spacing2xs),
                    Text(
                      subtitleParts.join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    MemberStatusBadge(status: detail.status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingMd),
          const Divider(height: 1),
          const SizedBox(height: FFTokens.spacingMd),
          Row(
            children: [
              Expanded(
                child: _MetaItem(
                  label: context.tr('members.memberId'),
                  value: '#${detail.publicId}',
                ),
              ),
              const _VDivider(),
              Expanded(
                child: _MetaItem(
                  label: context.tr('members.phone'),
                  value: detail.phone ?? '—',
                ),
              ),
              const _VDivider(),
              Expanded(
                child: _MetaItem(
                  label: context.tr('members.joinedOn'),
                  value: detail.joinedAt != null
                      ? formatDate(detail.joinedAt!)
                      : '—',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _cap(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: FFTokens.spacing2xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    this.trailing,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: FFTokens.iconSm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ?trailing,
            ],
          ),
          const SizedBox(height: FFTokens.spacingMd),
          child,
        ],
      ),
    );
  }
}

class _CheckInSummaryCard extends StatelessWidget {
  const _CheckInSummaryCard({required this.controller});

  final MemberDetailController controller;

  static String _periodLabel(BuildContext context, CheckInPeriod p) =>
      switch (p) {
        CheckInPeriod.week => context.tr('members.thisWeek'),
        CheckInPeriod.month => context.tr('members.thisMonth'),
        CheckInPeriod.year => context.tr('members.thisYear'),
        CheckInPeriod.custom => context.tr('members.customRange'),
      };

  Future<void> _select(BuildContext context, CheckInPeriod period) async {
    if (period == CheckInPeriod.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange:
            controller.customFrom != null && controller.customTo != null
            ? DateTimeRange(
                start: controller.customFrom!,
                end: controller.customTo!,
              )
            : null,
      );
      if (range == null) return;
      await controller.setPeriod(
        CheckInPeriod.custom,
        from: range.start,
        to: range.end,
      );
      return;
    }
    await controller.setPeriod(period);
  }

  @override
  Widget build(BuildContext context) {
    final summary = controller.checkInSummary ?? const CheckInSummary();
    return _SectionCard(
      icon: Icons.bar_chart,
      title: context.tr('members.checkInSummary'),
      trailing: PopupMenuButton<CheckInPeriod>(
        onSelected: (p) => _select(context, p),
        itemBuilder: (ctx) => [
          for (final p in CheckInPeriod.values)
            PopupMenuItem<CheckInPeriod>(
              value: p,
              child: Text(_periodLabel(ctx, p)),
            ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.summaryLoading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                _periodLabel(context, controller.period),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            const Icon(Icons.keyboard_arrow_down, size: 16),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryStat(
              label: context.tr('members.visits'),
              value: '${summary.visits}',
            ),
          ),
          const _VDivider(),
          Expanded(
            child: _SummaryStat(
              label: context.tr('members.lastCheckIn'),
              value: summary.lastCheckinAt != null
                  ? formatRelative(context, summary.lastCheckinAt)
                  : '—',
            ),
          ),
          const _VDivider(),
          Expanded(
            child: _SummaryStat(
              label: context.tr('members.streak'),
              value: '${summary.streakDays} ${context.tr('members.days')}',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: FFTokens.spacing2xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final MembershipPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tierLabel = plan.tier != null
        ? '${_cap(plan.tier!)} ${context.tr('members.plan')}'
        : context.tr('members.membershipPlan');
    return _SectionCard(
      icon: Icons.card_membership,
      title: context.tr('members.membershipPlan'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tierLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Row(
            children: [
              Expanded(
                child: _MetaItem(
                  label: context.tr('members.startDate'),
                  value: plan.startDate != null
                      ? formatDate(plan.startDate!)
                      : '—',
                ),
              ),
              const _VDivider(),
              Expanded(
                child: _MetaItem(
                  label: context.tr('members.expiryDate'),
                  value: plan.expiresAt != null
                      ? '${formatDate(plan.expiresAt!)}${_daysLeftSuffix(context)}'
                      : '—',
                ),
              ),
              const _VDivider(),
              Expanded(
                child: _MetaItem(
                  label: context.tr('members.statusLabel'),
                  value: _cap(plan.status),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _daysLeftSuffix(BuildContext context) {
    final dl = plan.daysLeft;
    if (dl == null || dl < 0) return '';
    return ' ($dl ${context.tr('members.daysLeft')})';
  }

  static String _cap(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
}

class _RecentCheckinsCard extends StatelessWidget {
  const _RecentCheckinsCard({required this.checkins, required this.onViewAll});

  final List<MemberCheckin> checkins;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.event_available,
      title: context.tr('members.recentCheckins'),
      trailing: _ViewAllLink(onTap: onViewAll),
      child: checkins.isEmpty
          ? Text(context.tr('member.noData'), style: theme.textTheme.bodySmall)
          : Column(
              children: checkins.take(4).map((c) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: FFTokens.iconMd,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: FFTokens.spacingSm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.timestamp != null
                                  ? formatRelative(context, c.timestamp)
                                  : '—',
                              style: theme.textTheme.labelLarge,
                            ),
                            if (c.gymName != null)
                              Text(
                                c.gymName!,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _PaymentHistoryCard extends StatelessWidget {
  const _PaymentHistoryCard({required this.payments, required this.onViewAll});

  final List<MemberPayment> payments;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.receipt_long,
      title: context.tr('members.paymentHistory'),
      trailing: _ViewAllLink(onTap: onViewAll),
      child: payments.isEmpty
          ? Text(context.tr('member.noData'), style: theme.textTheme.bodySmall)
          : Column(
              children: payments.take(4).map((p) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.requestedAt != null
                                  ? formatDate(p.requestedAt!)
                                  : '—',
                              style: theme.textTheme.labelLarge,
                            ),
                            if (p.tier != null)
                              Text(
                                _cap(p.tier!),
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatCurrency(p.amountTzs),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FFBadge(
                            label: context.tr('members.paid'),
                            tone: FFBadgeTone.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  static String _cap(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.detail,
    required this.busy,
    required this.onCheckIn,
    required this.onRenew,
    required this.onEdit,
    required this.onSuspend,
  });

  final MemberDetail detail;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onRenew;
  final VoidCallback onEdit;
  final VoidCallback onSuspend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suspended = detail.isSuspended;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onCheckIn,
                    icon: const Icon(Icons.qr_code, size: FFTokens.iconSm),
                    label: Text(context.tr('members.checkIn')),
                  ),
                ),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onRenew,
                    icon: const Icon(Icons.autorenew, size: FFTokens.iconSm),
                    label: Text(context.tr('members.renew')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onEdit,
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: FFTokens.iconSm,
                    ),
                    label: Text(context.tr('members.editMember')),
                  ),
                ),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onSuspend,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                    icon: Icon(
                      suspended ? Icons.play_circle_outline : Icons.block,
                      size: FFTokens.iconSm,
                    ),
                    label: Text(
                      context.tr(
                        suspended ? 'members.reactivate' : 'members.suspend',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
