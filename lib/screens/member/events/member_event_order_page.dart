import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_order.dart';
import '../../../shared/events/event_summary.dart';
import '../../../shared/events/event_time.dart';
import '../../../shared/events/events_analytics.dart';
import '../../../shared/events/events_checkout.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/events/registration_draft.dart';
import '../../../shared/i18n.dart';
import 'event_cancel_reason_dialog.dart';
import 'event_status.dart';
import 'events_registration_gate.dart';
import 'register/quote_summary.dart';

/// `/member/events/orders/:orderId` (events S3 spec §5.7): awaiting
/// payment with the hold countdown and the labelled S4 payment slot,
/// expired, cancelled; per-place removal (D17) and whole-order cancel.
class MemberEventOrderPage extends StatefulWidget {
  const MemberEventOrderPage({
    super.key,
    required this.orderId,
    this.options,
    this.now,
    this.pollEvery = const Duration(seconds: 60),
  });

  final String orderId;
  final EventsOptions? options;
  final DateTime? now;
  final Duration pollEvery;

  @override
  State<MemberEventOrderPage> createState() => _MemberEventOrderPageState();
}

class _MemberEventOrderPageState extends State<MemberEventOrderPage>
    with WidgetsBindingObserver {
  EventOrderDetail? _detail;
  bool _loading = true;
  Object? _error;
  bool _gone = false;
  bool _busy = false;
  Timer? _poll;
  final _heading = FocusNode(debugLabel: 'order-heading');

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _heading.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_detail?.order.isAwaitingPayment ?? false)) {
      _load(quiet: true);
    }
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    await _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _detail == null;
        _error = null;
        _gone = false;
      });
    }
    try {
      final json = await _api.getEventOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _detail = EventOrderDetail.fromJson(json);
        _loading = false;
      });
      _schedulePoll();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _heading.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      if (quiet) return;
      setState(() {
        _loading = false;
        if (e is ApiException && e.status == 404) {
          _gone = true;
        } else {
          _error = e;
        }
      });
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (_detail?.order.isAwaitingPayment ?? false) {
      _poll = Timer(widget.pollEvery, () => _load(quiet: true));
    }
  }

  // ── actions ─────────────────────────────────────────────────────────────

  Future<void> _cancelOrder() async {
    final d = _detail;
    if (d == null || _busy) return;
    final reason = await showEventCancelReasonDialog(
      context,
      title: context.tr('events.order.cancel.title'),
      body: context.tr('events.order.cancel.body'),
      confirmLabel: context.tr('events.order.cancel'),
    );
    if (reason == null || !mounted) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr('events.order.cancelled.snack');
    setState(() => _busy = true);
    try {
      final res = await _api.cancelEventOrder(d.order.id, reason: reason);
      if (!mounted) return;
      EventsAnalytics.orderCancelled(orderId: d.order.id, reason: reason);
      final order = res['order'] is Map
          ? EventOrder.fromJson(res['order'] as Map, event: d.order.event)
          : null;
      setState(() {
        _busy = false;
        if (order != null) {
          _detail = EventOrderDetail(
            order: order,
            lines: d.lines,
            registrations: res['registrations'] is List
                ? [
                    for (final r in res['registrations'] as List)
                      if (r is Map) EventRegistration.fromJson(r),
                  ]
                : d.registrations,
            event: d.event,
            team: d.team,
            payment: d.payment,
            paymentInstructions: d.paymentInstructions,
            allowedActions: const [],
          );
        }
      });
      snack.success(done);
      if (order == null) await _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(errorMessage(locale, e));
    }
  }

  Future<void> _removePlace(EventRegistration r) async {
    final d = _detail;
    if (d == null || _busy) return;
    final reason = await showEventCancelReasonDialog(
      context,
      title: context
          .tr('events.reg.remove.title')
          .replaceFirst('{name}', r.fullName),
      body: context.tr('events.reg.remove.body'),
      confirmLabel: context.tr('events.order.remove'),
    );
    if (reason == null || !mounted) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    try {
      await _api.cancelEventRegistration(r.id, reason: reason);
      if (!mounted) return;
      setState(() => _busy = false);
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'remove_whole_line') {
        await showFFConfirmDialog(
          context,
          title: context.tr('events.order.cancel'),
          message: context
              .tr('events.reg.remove.lastLine')
              .replaceFirst('{ticket}', r.ticketTypeName),
          confirmLabel: context.tr('events.order.cancel'),
          cancelLabel: context.tr('common.close'),
          confirmKey: const Key('remove-whole-line-cancel'),
          destructive: true,
        ).then((yes) {
          if (yes && mounted) _cancelOrder();
        });
        return;
      }
      snack.error(errorMessage(locale, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(errorMessage(locale, e));
    }
  }

  /// "Register again": the people of this order become a draft (without
  /// the hold) and the register page offers to continue from it.
  Future<void> _registerAgain() async {
    final d = _detail;
    if (d == null) return;
    final lines = <String, int>{};
    for (final l in d.lines) {
      lines[l.ticketTypeId] = l.quantity;
    }
    await RegistrationDraftStore.save(
      RegistrationDraft(
        eventId: d.order.eventId,
        savedAt: (widget.now ?? DateTime.now()).toUtc(),
        step: 1,
        lines: lines,
        mode: d.registrations.any((r) => r.isSelf)
            ? (d.registrations.length > 1 ? 'selfOthers' : 'self')
            : 'others',
        participants: [
          for (final r in d.registrations)
            EventParticipantInput(
              ticketTypeId: r.ticketTypeId,
              categoryId: r.categoryId,
              isSelf: r.isSelf,
              firstName: r.firstName,
              lastName: r.lastName,
              phone: r.phone ?? '',
              email: r.email ?? '',
              dateOfBirth: r.dateOfBirth ?? '',
              gender: r.gender ?? '',
              emergencyName: r.emergencyContact?.name ?? '',
              emergencyPhone: r.emergencyContact?.phone ?? '',
              kitSize: r.kitSize ?? '',
            ),
        ],
      ),
    );
    if (!mounted) return;
    context.push(AppRoutes.memberEventRegisterPath(d.order.eventId));
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.memberEventOrders);

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          d == null
              ? context.tr('events.reg.order')
              : context
                    .tr('events.order.title')
                    .replaceFirst('{ref}', d.order.reference),
        ),
      ),
      body: _gone
          ? Center(
              child: FFEmptyState(
                key: const Key('order-gone'),
                icon: Icons.receipt_long_outlined,
                title: context.tr('events.order.gone.title'),
                body: context.tr('events.detail.gone.body'),
              ),
            )
          : _loading
          ? FFSkeletonList(
              key: const Key('order-loading'),
              semanticLabel: context.tr('common.loading'),
            )
          : d == null
          ? Center(
              child: FFErrorState(
                key: const Key('order-error'),
                message: _error == null
                    ? null
                    : errorMessage(FFLocaleScope.of(context), _error!),
                retryLabel: context.tr('common.retry'),
                onRetry: _load,
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(quiet: true),
              child: ListView(
                key: const Key('order-scroll'),
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _content(context, d),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _content(BuildContext context, EventOrderDetail d) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final o = d.order;
    final e = d.event?.summary ?? o.event;
    final off = e?.utcOffsetMinutes ?? 0;
    final abbr = e?.timezoneAbbr ?? '';
    final status = context.tr(eventOrderStatusKey(o.status));
    final tone = switch (o.status) {
      EventOrderStatus.awaitingPayment => FFBadgeTone.warning,
      EventOrderStatus.confirmed => FFBadgeTone.success,
      _ => FFBadgeTone.gray,
    };
    final eventOpen =
        e != null &&
        (e.availability == EventAvailability.open ||
            e.availability == EventAvailability.closingSoon);

    return [
      // ── header ────────────────────────────────────────────────────────
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          label:
              '${context.tr('events.order.title').replaceFirst('{ref}', o.reference)}, $status',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e?.title ?? '',
                  key: const Key('order-event-title'),
                  style: tt.titleLarge,
                ),
                const SizedBox(height: FFTokens.spacingXs),
                Wrap(
                  spacing: FFTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FFBadge(
                      key: const Key('order-status'),
                      label: status,
                      tone: tone,
                    ),
                    Text(
                      o.reference,
                      key: const Key('order-reference'),
                      style: tt.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          key: const Key('order-copy-ref'),
          tooltip: context.tr('common.copy'),
          icon: const Icon(Icons.copy_outlined, size: 20),
          onPressed: () async {
            final snack = FFSnack.of(context);
            final copied = context.tr('common.copied');
            await Clipboard.setData(ClipboardData(text: o.reference));
            snack.success(copied);
          },
        ),
      ),
      // ── state banner ──────────────────────────────────────────────────
      if (o.isAwaitingPayment && o.holdExpiresAt != null)
        FFCard(
          key: const Key('order-hold'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context
                    .tr('events.order.heldUntil')
                    .replaceFirst(
                      '{time}',
                      eventTime(o.holdExpiresAt!, off, abbr, locale: lang),
                    ),
                style: tt.titleSmall,
              ),
              FFCountdownText(
                until: o.holdExpiresAt!,
                now: widget.now == null ? null : () => widget.now!,
                minutesLabel: context.tr('events.order.left'),
                secondsLabel: context.tr('events.order.leftSeconds'),
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                urgentStyle: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fuelTextColor(context),
                ),
                onDone: () => _load(quiet: true),
              ),
            ],
          ),
        ),
      if (o.status == EventOrderStatus.expired)
        FFAlert(
          key: const Key('order-expired'),
          tone: FFAlertTone.warning,
          message: context.tr('events.order.expired.body'),
        ),
      if (o.status == EventOrderStatus.cancelled)
        FFAlert(
          key: const Key('order-cancelled'),
          tone: FFAlertTone.info,
          message: o.closeReason == 'admin'
              ? context.tr('events.order.cancelledByAdmin')
              : context
                    .tr('events.order.cancelled.body')
                    .replaceFirst(
                      '{date}',
                      o.closedAt == null
                          ? '—'
                          : eventDate(o.closedAt!, off, locale: lang),
                    ),
        ),
      if (o.status == EventOrderStatus.expired ||
          o.status == EventOrderStatus.cancelled)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingSm),
          child: FFButton(
            key: const Key('order-register-again'),
            label: eventOpen || e == null
                ? context.tr('events.order.again')
                : availabilityLabel(context, e),
            fullWidth: true,
            onPressed: eventOpen ? _registerAgain : null,
          ),
        ),
      // ── payment slot (S4 fills it from next.payment) ──────────────────
      if (o.isAwaitingPayment) ...[
        FFSectionTitle(context.tr('events.order.payment.title')),
        FFCard(
          key: const Key('order-payment-slot'),
          child: d.payment == 'none'
              ? Column(
                  key: const Key('order-payment-placeholder'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('events.order.payment.soon.title'),
                      style: tt.titleSmall,
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    FFAlert(
                      tone: FFAlertTone.info,
                      message: context.tr('events.order.payment.soon.body'),
                    ),
                  ],
                )
              // S4: `manual` → ManualPaymentSteps from next.instructions;
              // `provider` → the provider button. Until then the same
              // placeholder, so an early server answer never renders a
              // payment UI this release cannot complete.
              : Text(
                  context.tr('events.order.payment.soon.title'),
                  key: const Key('order-payment-unsupported'),
                  style: tt.titleSmall,
                ),
        ),
      ],
      // ── quote ─────────────────────────────────────────────────────────
      FFSectionTitle(context.tr('events.review.tickets')),
      FFCard(
        key: const Key('order-quote'),
        child: QuoteLinesTable(
          lines: d.lines,
          currency: o.currency,
          discountTzs: o.discountTzs,
          feesTzs: o.feesTzs,
          totalTzs: o.totalTzs,
        ),
      ),
      // ── participants ──────────────────────────────────────────────────
      FFSectionTitle(context.tr('events.review.participants')),
      for (final r in d.registrations) _participantRow(context, d, r),
      if (d.team case final team?) ...[
        FFSectionTitle(context.tr('events.review.team')),
        FFActionTile(
          key: const Key('order-team'),
          icon: Icons.groups_outlined,
          title: team.name,
          subtitle:
              context.tr('events.team.type.${team.teamType}') ==
                  'events.team.type.${team.teamType}'
              ? null
              : context.tr('events.team.type.${team.teamType}'),
          onTap: () => context.push(AppRoutes.memberEventTeamPath(team.id)),
        ),
      ],
      if (d.event != null) ...[
        FFSectionTitle(context.tr('events.review.refund')),
        FFCard(
          key: const Key('order-refund'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d.event!.refundPolicy.preset == 'no_refund' ||
                  d.event!.refundPolicy.preset == 'refund_until_close')
                Text(
                  context.tr(
                    'events.detail.policy.${d.event!.refundPolicy.preset}',
                  ),
                  style: tt.titleSmall,
                ),
              if (d.event!.refundPolicy.text.isNotEmpty)
                Text(d.event!.refundPolicy.text.of(lang), style: tt.bodySmall),
            ],
          ),
        ),
      ],
      if (o.isAwaitingPayment && d.canCancel) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('order-cancel'),
          label: context.tr('events.order.cancel'),
          variant: FFButtonVariant.destructive,
          loading: _busy,
          onPressed: _cancelOrder,
        ),
      ],
      const SizedBox(height: FFTokens.spacingLg),
      Text(
        o.createdAt == null
            ? ''
            : eventDateTime(o.createdAt!, off, abbr, locale: lang),
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    ];
  }

  Widget _participantRow(
    BuildContext context,
    EventOrderDetail d,
    EventRegistration r,
  ) {
    final tt = Theme.of(context).textTheme;
    final statusKey = eventRegistrationStatusKey(r.status, d.order.status);
    final live = registrationIsLive(r.status, d.order.status);
    final chip = switch (r.claimState) {
      ClaimState.self => (
        context.tr('events.participant.you'),
        FFBadgeTone.brand,
      ),
      ClaimState.claimed => (
        context.tr('events.claim.chip.claimed'),
        FFBadgeTone.success,
      ),
      ClaimState.unclaimed => (
        context.tr('events.claim.chip.pending'),
        FFBadgeTone.defaultTone,
      ),
    };
    final canRemove =
        d.order.isAwaitingPayment &&
        d.canCancel &&
        live &&
        d.registrations
                .where((x) => x.status != EventRegistrationStatus.cancelled)
                .length >
            1;
    return FFCard(
      key: Key('order-participant-${r.id}'),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () =>
                  context.push(AppRoutes.memberEventRegistrationPath(r.id)),
              borderRadius: BorderRadius.circular(FFTokens.radiusLg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(r.fullName, style: tt.titleSmall),
                    Text(
                      [
                        r.categoryName,
                        r.ticketTypeName,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: tt.bodySmall,
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    Wrap(
                      spacing: FFTokens.spacingXs,
                      children: [
                        FFBadge(
                          label: context.tr(statusKey),
                          tone: live ? FFBadgeTone.warning : FFBadgeTone.gray,
                        ),
                        FFBadge(label: chip.$1, tone: chip.$2),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (canRemove)
            PopupMenuButton<String>(
              key: Key('order-participant-menu-${r.id}'),
              tooltip: context.tr('events.order.remove'),
              onSelected: (_) => _removePlace(r),
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: Key('order-participant-remove-${r.id}'),
                  value: 'remove',
                  child: Text(context.tr('events.reg.remove')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
