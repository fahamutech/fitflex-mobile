import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_order.dart';
import '../../../../shared/events/event_refund.dart';
import '../../../../shared/events/events_analytics.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../events_registration_gate.dart';

/// Cancel and refund a paid place or a whole paid order (events S4 spec
/// §5.7, §3.12.2). The refund amount is the server's own number: the page
/// shows it and sends it back only as an equality check, so a policy tier
/// that moved while the member was reading is caught (`refund_changed`).
class MemberEventCancelPage extends StatefulWidget {
  const MemberEventCancelPage.registration({
    super.key,
    required String registrationId,
    this.orderId,
    this.options,
  }) : id = registrationId,
       isOrder = false;

  const MemberEventCancelPage.order({
    super.key,
    required String orderId,
    this.options,
  }) : id = orderId,
       orderId = null,
       isOrder = true;

  /// The registration's or the order's id.
  final String id;
  final bool isOrder;

  /// For a single place: the order to return to after the cancel.
  final String? orderId;
  final EventsOptions? options;

  @override
  State<MemberEventCancelPage> createState() => _MemberEventCancelPageState();
}

class _MemberEventCancelPageState extends State<MemberEventCancelPage> {
  CancelPreview? _preview;
  bool _loading = true;
  Object? _error;
  bool _busy = false;
  bool _ack = false;
  bool _changed = false;
  String _reason = memberCancelReasons.first;

  /// A refusal at confirm time that closes the page's action
  /// (`payment_submitted`, `refund_in_progress`, …).
  String? _refusedWith;
  final _heading = FocusNode(debugLabel: 'cancel-heading');

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);
  String get _scope => widget.isOrder ? 'order' : 'registration';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _heading.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _ack = false;
    });
    try {
      final json = widget.isOrder
          ? await _api.eventOrderCancelPreview(widget.id)
          : await _api.eventRegistrationCancelPreview(widget.id);
      if (!mounted) return;
      final p = CancelPreview.fromJson(json);
      EventsAnalytics.cancelPreviewViewed(scope: _scope, mode: p.mode.name);
      setState(() {
        _preview = p;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _heading.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  CancelMode get _mode => _preview?.mode ?? CancelMode.closed;

  bool get _canAct {
    final p = _preview;
    if (p == null || _busy || _refusedWith != null || p.isBlocked) return false;
    if (_mode == CancelMode.none && !_ack) return false;
    return true;
  }

  String _amount(int tzs, String currency) =>
      formatCurrency(tzs, currency: currency);

  Future<void> _confirm() async {
    final p = _preview;
    if (p == null || !_canAct) return;
    final yes = await showFFConfirmDialog(
      context,
      title: context.tr(
        widget.isOrder
            ? 'events.cancelpaid.confirm.titleOrder'
            : 'events.cancelpaid.confirm.title',
      ),
      message: context.tr(
        _mode == CancelMode.manualReview
            ? 'events.cancelpaid.refund.review'
            : 'events.cancelpaid.warn',
      ),
      confirmLabel: _actionLabel(p),
      cancelLabel: context.tr('events.cancelpaid.keep'),
      destructive: true,
      confirmKey: const Key('cancel-confirm'),
      cancelKey: const Key('cancel-keep'),
    );
    if (!yes || !mounted) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final doneKey = switch (_mode) {
      CancelMode.auto => 'events.cancelpaid.done.refund',
      CancelMode.manualReview => 'events.cancelpaid.done.review',
      _ => 'events.cancelpaid.done.none',
    };
    final done = context
        .tr(doneKey)
        .replaceFirst('{amount}', _amount(p.refundTzs, p.currency));
    setState(() {
      _busy = true;
      _changed = false;
    });
    try {
      final res = widget.isOrder
          ? await _api.cancelEventOrder(
              widget.id,
              reason: _reason,
              expectedRefundTzs: p.refundTzs,
            )
          : await _api.cancelEventRegistration(
              widget.id,
              reason: _reason,
              expectedRefundTzs: p.refundTzs,
            );
      if (!mounted) return;
      EventsAnalytics.cancelConfirmed(scope: _scope, mode: _mode.name);
      snack.success(done);
      final orderId = widget.isOrder
          ? widget.id
          : (res['order'] is Map
                    ? (res['order'] as Map)['id']?.toString()
                    : null) ??
                (res['registration'] is Map
                    ? (res['registration'] as Map)['orderId']?.toString()
                    : null) ??
                widget.orderId;
      if (orderId != null && orderId.isNotEmpty) {
        context.pushReplacement(AppRoutes.memberEventOrder(orderId));
      } else if (context.canPop()) {
        context.pop(true);
      } else {
        context.go(AppRoutes.memberEventOrders);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      switch (e.code) {
        case 'refund_changed':
          // The tier moved: show the new number and ask again.
          await _load();
          if (mounted) setState(() => _changed = true);
        case 'payment_submitted' ||
            'refund_in_progress' ||
            'cancellation_window_closed' ||
            'event_cancelled' ||
            'purchaser_only' ||
            'kit_collected':
          setState(() => _refusedWith = e.code);
        default:
          snack.error(eventsErrorMessage(locale, e));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(eventsErrorMessage(locale, e));
    }
  }

  String _actionLabel(CancelPreview p) => switch (_mode) {
    CancelMode.auto =>
      context
          .tr('events.cancelpaid.cta.refund')
          .replaceFirst('{amount}', _amount(p.refundTzs, p.currency)),
    CancelMode.manualReview => context.tr('events.cancelpaid.cta.review'),
    _ => context.tr('events.cancelpaid.cta.none'),
  };

  void _back() => context.canPop()
      ? context.pop()
      : context.go(
          widget.isOrder
              ? AppRoutes.memberEventOrder(widget.id)
              : AppRoutes.memberEventRegistrationPath(widget.id),
        );

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.cancelpaid.title')),
      ),
      body: _loading
          ? FFSkeletonList(
              key: const Key('cancel-loading'),
              semanticLabel: context.tr('events.cancelpaid.loading'),
            )
          : p == null
          ? Center(
              child: FFErrorState(
                key: const Key('cancel-error'),
                message: _error == null
                    ? null
                    : eventsErrorMessage(FFLocaleScope.of(context), _error!),
                retryLabel: context.tr('common.retry'),
                onRetry: _load,
              ),
            )
          : ListView(
              key: const Key('cancel-scroll'),
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _content(context, p),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: p == null || _loading || _blockedCode(p) != null
          ? null
          : _bar(context, p),
    );
  }

  /// The blocked reason to show, from the preview or a refusal at confirm.
  String? _blockedCode(CancelPreview p) {
    if (_refusedWith != null) return _refusedWith;
    if (p.blocked != null) return p.blocked;
    if (!p.eligible || p.mode == CancelMode.closed) {
      return 'cancellation_window_closed';
    }
    return null;
  }

  Widget _bar(BuildContext context, CancelPreview p) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingSm),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: FFButton(
                key: const Key('cancel-action'),
                label: _actionLabel(p),
                variant: FFButtonVariant.destructive,
                fullWidth: true,
                maxLines: 2,
                loading: _busy,
                onPressed: _canAct ? _confirm : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, CancelPreview p) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final blocked = _blockedCode(p);

    final policyLine = switch (p.policyPreset) {
      'no_refund' || 'refund_until_close' => context.tr(
        'events.detail.policy.${p.policyPreset}',
      ),
      _ =>
        p.deadlineAt == null || p.percent <= 0
            ? null
            : context
                  .tr(
                    p.percent >= 100
                        ? 'events.cancelpaid.policy.line.full'
                        : 'events.cancelpaid.policy.line.partial',
                  )
                  .replaceFirst(
                    '{date}',
                    formatDate(p.deadlineAt, locale: lang),
                  )
                  .replaceFirst('{percent}', '${p.percent}'),
    };
    final snapshot = p.policyText.of(lang);

    String refundText() {
      final amount = _amount(p.refundTzs, p.currency);
      return switch (p.mode) {
        CancelMode.auto =>
          p.percent > 0 && p.percent < 100
              ? context
                    .tr('events.cancelpaid.refund.partial')
                    .replaceFirst('{amount}', amount)
                    .replaceFirst('{percent}', '${p.percent}')
                    .replaceFirst('{paid}', _amount(p.paidTzs, p.currency))
              : context
                    .tr('events.cancelpaid.refund.full')
                    .replaceFirst('{amount}', amount),
        CancelMode.none => context.tr('events.cancelpaid.refund.none'),
        CancelMode.manualReview => context.tr(
          'events.cancelpaid.refund.review',
        ),
        CancelMode.closed => '',
      };
    }

    return [
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: FFPageHeader(title: context.tr('events.cancelpaid.title')),
        ),
      ),
      if (_changed)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Semantics(
            liveRegion: true,
            child: FFAlert(
              key: const Key('cancel-changed'),
              tone: FFAlertTone.warning,
              message: context.tr('events.cancelpaid.changed'),
            ),
          ),
        ),
      if (blocked != null)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: Key('cancel-blocked-$blocked'),
            tone: blocked == 'event_cancelled'
                ? FFAlertTone.info
                : FFAlertTone.warning,
            message: context
                .tr('events.cancelpaid.blocked.$blocked')
                .replaceFirst(
                  '{name}',
                  context.tr('events.cancelpaid.purchaserFallback'),
                ),
          ),
        ),
      // ── what is being cancelled ───────────────────────────────────────
      if (p.places.isNotEmpty)
        FFCard(
          key: const Key('cancel-summary'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('events.cancelpaid.summary'),
                style: tt.titleSmall,
              ),
              const SizedBox(height: FFTokens.spacingXs),
              for (final place in p.places)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(place.name, style: tt.bodyMedium)),
                      Text(
                        _amount(place.paidTzs, p.currency),
                        style: tt.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      // ── policy ────────────────────────────────────────────────────────
      FFCard(
        key: const Key('cancel-policy'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('events.cancelpaid.policy'), style: tt.titleSmall),
            if (snapshot.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Text(snapshot, style: tt.bodyMedium),
              ),
            if (policyLine != null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Text(
                  policyLine,
                  key: const Key('cancel-policy-line'),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
      // ── the refund ────────────────────────────────────────────────────
      if (blocked == null || p.mode != CancelMode.closed) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingSm),
          child: Semantics(
            liveRegion: true,
            child: Text(
              refundText(),
              key: const Key('cancel-refund'),
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (p.mode == CancelMode.auto && p.deadlineAt != null)
          Text(
            context
                .tr('events.cancelpaid.refund.until')
                .replaceFirst('{date}', formatDate(p.deadlineAt, locale: lang)),
            key: const Key('cancel-deadline'),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
      ],
      // ── reason and acknowledgement ────────────────────────────────────
      if (blocked == null) ...[
        const SizedBox(height: FFTokens.spacingMd),
        Text(context.tr('events.cancelpaid.reason'), style: tt.titleSmall),
        const SizedBox(height: FFTokens.spacingSm),
        for (final r in memberCancelReasons)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFChoiceTile(
              key: Key('cancel-reason-$r'),
              title: context.tr('events.order.cancel.reason.$r'),
              selected: _reason == r,
              minHeight: 48,
              onSelected: () => setState(() => _reason = r),
            ),
          ),
        if (_mode == CancelMode.none)
          CheckboxListTile(
            key: const Key('cancel-ack'),
            value: _ack,
            onChanged: _busy ? null : (v) => setState(() => _ack = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              context.tr('events.cancelpaid.ack'),
              style: tt.bodyMedium,
            ),
          ),
      ],
      const SizedBox(height: FFTokens.spacingLg),
    ];
  }
}
