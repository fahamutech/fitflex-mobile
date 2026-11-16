import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/friend_invites.dart' show shareFriendInvite;
import '../../../shared/gym_passes/gym_pass.dart';
import '../../../shared/i18n.dart';

/// Custom Gym Passes: the passes I bought and the passes I am covered by.
/// Opening it also attaches me to passes waiting on a contact I verified
/// (`GET /me/gym-passes`).
class MemberGymPassesPage extends StatefulWidget {
  const MemberGymPassesPage({super.key});

  @override
  State<MemberGymPassesPage> createState() => _MemberGymPassesPageState();
}

class _MemberGymPassesPageState extends State<MemberGymPassesPage> {
  GymPassesMine? _mine;
  Object? _error;
  bool _unavailable = false;
  bool _loading = true;
  bool _started = false;

  /// Ids of buyer / person actions in flight: a second tap does nothing.
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await AppScope.of(context).api.myGymPasses();
      if (!mounted) return;
      setState(() {
        _mine = GymPassesMine.fromJson(out);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _unavailable = isGymPassesUnavailable(e);
        _error = _unavailable ? null : e;
        _loading = false;
      });
    }
  }

  void _fail(Object e) {
    if (!mounted) return;
    FFSnack.error(
      context,
      gymPassErrorMessage(FFLocaleScope.of(context), e, errorMessage),
    );
  }

  /// Runs one action once at a time per [key], then reloads.
  Future<void> _run(String key, Future<void> Function() action) async {
    if (!_busy.add(key)) return;
    setState(() {});
    try {
      await action();
      if (!mounted) return;
      await _load();
    } catch (e) {
      _fail(e);
    } finally {
      _busy.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _addPerson(GymPassPurchase p) async {
    final contact = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddPersonSheet(),
    );
    if (contact == null || !mounted) return;
    await _run('add:${p.id}', () async {
      await AppScope.of(context).api.addGymPassPerson(p.id, contact);
      if (mounted) FFSnack.success(context, context.tr('gymPass.person.added'));
    });
  }

  Future<void> _personAction(
    GymPassPurchase p,
    GymPassPerson who,
    String action,
  ) async {
    if (action == 'remove') {
      final ok = await showFFConfirmDialog(
        context,
        title: context.tr('gymPass.removeTitle'),
        message: context.tr('gymPass.removeBody'),
        confirmLabel: context.tr('gymPass.removeConfirm'),
        destructive: true,
        confirmKey: const Key('gym-pass-remove-confirm'),
      );
      if (!ok || !mounted) return;
    }
    final key = 'person:${who.id}';
    if (action == 'invite') {
      if (!_busy.add(key)) return;
      setState(() {});
      try {
        final out = await AppScope.of(
          context,
        ).api.changeGymPassPerson(p.id, who.id, 'invite');
        if (!mounted) return;
        // Opaque answer: never inferred into an account state. A null link
        // (no portal host on the server) is never shared or copied.
        final s = gymPassInviteShare(out);
        switch (s.kind) {
          case GymPassInviteShare.linkAndText:
            await shareFriendInvite(context, text: s.text!, link: s.link!);
          case GymPassInviteShare.textOnly:
            await shareFriendInvite(context, text: s.text!, link: s.text!);
          case GymPassInviteShare.nothing:
            FFSnack.info(context, context.tr('gymPass.invite.sentByMessage'));
        }
      } on ApiException catch (e) {
        // 404 is only a removed person, the buyer's own row or an unknown
        // id; the wording is neutral and says nothing about accounts.
        if (e.status == 404 && mounted) {
          FFSnack.info(context, context.tr('gymPass.invite.none'));
        } else {
          _fail(e);
        }
      } catch (e) {
        _fail(e);
      } finally {
        _busy.remove(key);
        if (mounted) setState(() {});
      }
      return;
    }
    await _run(
      key,
      () => AppScope.of(context).api.changeGymPassPerson(p.id, who.id, action),
    );
  }

  Future<void> _cancelPurchase(GymPassPurchase p) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('gymPass.cancelTitle'),
      message: context.tr('gymPass.cancelBody'),
      confirmLabel: context.tr('gymPass.cancelConfirm'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      'cancel:${p.id}',
      () => AppScope.of(context).api.cancelGymPassPurchase(p.id),
    );
  }

  Future<void> _leave(GymPassMembership m) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('gymPass.leaveTitle'),
      message: context.tr('gymPass.leaveBody'),
      confirmLabel: context.tr('gymPass.leaveConfirm'),
      destructive: true,
      confirmKey: const Key('gym-pass-leave-confirm'),
    );
    if (!ok || !mounted) return;
    await _run(
      'leave:${m.purchaseId}',
      () => AppScope.of(context).api.leaveGymPass(m.purchaseId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('gymPass.mineTitle'))),
      body: _loading && mine == null
          ? const Center(child: FFSpinner(size: 32))
          : _unavailable
          ? Center(
              child: FFEmptyState(
                key: const Key('gym-passes-unavailable'),
                title: context.tr('gymPass.unavailable'),
              ),
            )
          : _error != null && mine == null
          ? Center(
              child: FFEmptyState(
                title: context.tr('inbox.loadFailed'),
                body: errorMessage(FFLocaleScope.of(context), _error!),
                action: FFButton(
                  label: context.tr('home.retry'),
                  onPressed: _load,
                  variant: FFButtonVariant.secondary,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  if (mine == null || mine.isEmpty)
                    FFEmptyState(
                      key: const Key('gym-passes-empty'),
                      title: context.tr('gymPass.mineEmpty'),
                      body: context.tr('gymPass.mineEmptyBody'),
                    ),
                  if (mine != null && mine.purchased.isNotEmpty) ...[
                    FFSectionTitle(context.tr('gymPass.bought.title')),
                    for (final p in mine.purchased)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PurchasedCard(
                          key: Key('gym-pass-purchased-${p.id}'),
                          purchase: p,
                          busy: _busy,
                          onAdd: () => _addPerson(p),
                          onAction: (who, a) => _personAction(p, who, a),
                          onCancel: () => _cancelPurchase(p),
                        ),
                      ),
                  ],
                  if (mine != null && mine.memberships.isNotEmpty) ...[
                    FFSectionTitle(context.tr('gymPass.covered.title')),
                    for (final m in mine.memberships)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MembershipCard(
                          key: Key('gym-pass-membership-${m.beneficiaryId}'),
                          membership: m,
                          busy: _busy.contains('leave:${m.purchaseId}'),
                          onLeave: () => _leave(m),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

FFBadgeTone _purchaseTone(String status) => switch (status) {
  'active' => FFBadgeTone.success,
  'pending_payment' => FFBadgeTone.warning,
  'expired' || 'cancelled' => FFBadgeTone.gray,
  _ => FFBadgeTone.gray,
};

FFBadgeTone _personTone(String status) => switch (status) {
  'active' => FFBadgeTone.success,
  'suspended' => FFBadgeTone.danger,
  'invited' ||
  'pending_registration' ||
  'awaiting_payment' => FFBadgeTone.warning,
  _ => FFBadgeTone.gray,
};

String _statusKey(String prefix, String status) => '$prefix.$status';

class _PurchasedCard extends StatelessWidget {
  const _PurchasedCard({
    super.key,
    required this.purchase,
    required this.busy,
    required this.onAdd,
    required this.onAction,
    required this.onCancel,
  });

  final GymPassPurchase purchase;
  final Set<String> busy;
  final VoidCallback onAdd;
  final void Function(GymPassPerson who, String action) onAction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = purchase;
    final people = p.onPass;
    final name = p.planName.isEmpty
        ? context.tr('gymPass.genericLabel')
        : p.planName;
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FFBadge(
                  label: _statusLabel(context, 'gymPass.status', p.status),
                  tone: _purchaseTone(p.status),
                  dot: true,
                  wrap: true,
                ),
              ),
            ],
          ),
          if (p.gymName != null) ...[
            const SizedBox(height: 2),
            Text(p.gymName!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          if (p.isPendingPayment)
            Text(
              context.tr('gymPass.awaitingPayment'),
              style: theme.textTheme.labelMedium,
            )
          else if (p.expiresAt != null)
            Text(
              context
                  .tr('gymPass.sharedExpiry')
                  .replaceFirst('{date}', context.localDate(p.expiresAt)),
              key: Key('gym-pass-expiry-${p.id}'),
              style: theme.textTheme.labelMedium,
            ),
          if (p.limit > 0) ...[
            const SizedBox(height: 2),
            Text(
              context
                  .tr('gymPass.slots')
                  .replaceFirst('{used}', '${p.used}')
                  .replaceFirst('{limit}', '${p.limit}'),
              style: theme.textTheme.labelSmall,
            ),
          ],
          const SizedBox(height: 8),
          for (final who in people)
            _PersonRow(
              key: Key('gym-pass-person-row-${who.id}'),
              purchase: p,
              person: who,
              busy: busy.contains('person:${who.id}'),
              onAction: (a) => onAction(who, a),
            ),
          if (p.canAddPerson) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: Key('gym-pass-add-${p.id}'),
                label: context.tr('gymPass.addPerson'),
                variant: FFButtonVariant.secondary,
                loading: busy.contains('add:${p.id}'),
                onPressed: busy.contains('add:${p.id}') ? null : onAdd,
              ),
            ),
          ],
          if (p.isPendingPayment) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: Key('gym-pass-cancel-${p.id}'),
                label: context.tr('gymPass.cancelAction'),
                variant: FFButtonVariant.ghost,
                loading: busy.contains('cancel:${p.id}'),
                onPressed: busy.contains('cancel:${p.id}') ? null : onCancel,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _statusLabel(BuildContext context, String prefix, String status) {
  final key = _statusKey(prefix, status);
  final label = context.tr(key);
  if (label != key) return label;
  // A status this app does not know: a neutral word, never raw server text.
  return context.tr('$prefix.unknown');
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    super.key,
    required this.purchase,
    required this.person,
    required this.busy,
    required this.onAction,
  });

  final GymPassPurchase purchase;
  final GymPassPerson person;
  final bool busy;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = person;
    final title = who.you
        ? context.tr('gymPass.person.you')
        : (who.displayName?.trim().isNotEmpty ?? false)
        ? who.displayName!
        : (who.contact?.trim().isNotEmpty ?? false)
        ? who.contact!
        : context.tr('gymPass.person.slot').replaceFirst('{n}', '${who.slot}');
    // Actions only on a running pass, and never on the buyer's own slot.
    final canAct = purchase.isActive && !who.isPurchaser;
    final actions = <String>[
      if (canAct && who.status == 'suspended') 'resume',
      if (canAct && (who.status == 'active' || who.status == 'invited'))
        'suspend',
      if (canAct && who.status == 'invited') 'invite',
      if (canAct) 'remove',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (who.isPurchaser && !who.you)
                  Text(
                    context.tr('gymPass.person.buyer'),
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FFBadge(
              label: _statusLabel(context, 'gymPass.person', who.status),
              tone: _personTone(who.status),
              dot: true,
              wrap: true,
            ),
          ),
          if (actions.isNotEmpty)
            busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: FFSpinner(size: 16),
                  )
                : PopupMenuButton<String>(
                    key: Key('gym-pass-person-menu-${who.id}'),
                    tooltip: context.tr('gymPass.personMenu'),
                    onSelected: onAction,
                    itemBuilder: (ctx) => [
                      for (final a in actions)
                        PopupMenuItem<String>(
                          key: Key('gym-pass-action-$a'),
                          value: a,
                          child: Text(ctx.tr('gymPass.action.$a')),
                        ),
                    ],
                  ),
        ],
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({
    super.key,
    required this.membership,
    required this.busy,
    required this.onLeave,
  });

  final GymPassMembership membership;
  final bool busy;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = membership;
    final name = m.planName.isEmpty
        ? context.tr('gymPass.genericLabel')
        : m.planName;
    // Check-in works on the member's own QR; nothing here changes it.
    final canVisit = m.isRunning && m.status == 'active';
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FFBadge(
                  label: _statusLabel(context, 'gymPass.person', m.status),
                  tone: _personTone(m.status),
                  dot: true,
                  wrap: true,
                ),
              ),
            ],
          ),
          if (m.gymName != null) ...[
            const SizedBox(height: 2),
            Text(m.gymName!, style: theme.textTheme.bodySmall),
          ],
          if (m.expiresAt != null) ...[
            const SizedBox(height: 6),
            Text(
              context
                  .tr('gymPass.sharedExpiry')
                  .replaceFirst('{date}', context.localDate(m.expiresAt)),
              style: theme.textTheme.labelMedium,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (canVisit)
                FFButton(
                  key: Key('gym-pass-qr-${m.beneficiaryId}'),
                  label: context.tr('gymPass.showQr'),
                  variant: FFButtonVariant.secondary,
                  onPressed: () => context.go(AppRoutes.memberQr),
                ),
              FFButton(
                key: Key('gym-pass-leave-${m.purchaseId}'),
                label: context.tr('gymPass.leaveAction'),
                variant: FFButtonVariant.ghost,
                loading: busy,
                onPressed: busy ? null : onLeave,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddPersonSheet extends StatefulWidget {
  const _AddPersonSheet();

  @override
  State<_AddPersonSheet> createState() => _AddPersonSheetState();
}

class _AddPersonSheetState extends State<_AddPersonSheet> {
  final _contact = TextEditingController();
  bool _bad = false;

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  void _submit() {
    final body = gymPassContactBody(_contact.text);
    if (body == null) {
      setState(() => _bad = true);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, body);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: FFTokens.spacingLg,
          right: FFTokens.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + FFTokens.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('gymPass.addPerson'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('gymPass.notifyNote'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 12),
              FFTextField(
                key: const Key('gym-pass-add-contact'),
                controller: _contact,
                label: context.tr('gymPass.personLabelAdd'),
                hint: context.tr('gymPass.personHint'),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                errorText: _bad
                    ? context.tr('gymPass.error.contactProblem')
                    : null,
                onChanged: (_) {
                  if (_bad) setState(() => _bad = false);
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FFButton(
                  key: const Key('gym-pass-add-submit'),
                  label: context.tr('gymPass.addPersonConfirm'),
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
