import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_order.dart';
import '../../../../shared/events/event_payment.dart';
import '../../../../shared/events/event_time.dart';
import '../../../../shared/events/events_analytics.dart';
import '../../../../shared/events/events_checkout.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../../../shared/shop_checkout.dart';
import '../../widgets/mobile_money_pay.dart';
import '../events_registration_gate.dart';

/// `/member/events/orders/:orderId/pay` (events S4 spec §5.2, §5.3).
///
/// The order recap with the exact amount and one mobile-money button
/// (AzamPay, the only payment method). Whether paying is open is the
/// server's choice (`next.payment` / options `payment`: `provider` or
/// `none`); anything else goes back to the order.
class MemberEventPaymentPage extends StatefulWidget {
  const MemberEventPaymentPage({
    super.key,
    required this.orderId,
    this.options,
    this.now,
  });

  final String orderId;
  final EventsOptions? options;
  final DateTime? now;

  @override
  State<MemberEventPaymentPage> createState() => _MemberEventPaymentPageState();
}

enum _Phase { loading, form, expired, gone, error }

class _MemberEventPaymentPageState extends State<MemberEventPaymentPage> {
  EventOrderDetail? _detail;
  _Phase _phase = _Phase.loading;
  Object? _error;
  EventsOptions? _freshOptions;

  final _heading = FocusNode(debugLabel: 'pay-heading');
  bool _busy = false;
  bool _offline = false;
  bool _unavailable = false;
  bool _momoOffered = true;
  Object? _inlineError;
  CheckoutAttempt? _attempt;
  bool _startedEvent = false;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options =>
      _freshOptions ?? eventsOptionsOf(context, widget.options);

  /// The server's way to pay: the order's own `next.payment` when it names
  /// one, else the options'.
  String get _mode {
    final fromOrder = _detail?.payment ?? 'none';
    return fromOrder != 'none' ? fromOrder : _options.payment;
  }

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

  void _toOrder({bool changed = false}) {
    if (context.canPop()) {
      context.pop(changed);
    } else {
      context.go(AppRoutes.memberEventOrder(widget.orderId));
    }
  }

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final d = EventOrderDetail.fromJson(
        await _api.getEventOrder(widget.orderId),
      );
      if (!mounted) return;
      _detail = d;
      _offline = false;
      final mode = _mode;
      final live = d.paymentView?.state.isLive ?? false;
      // Nothing to pay here: back to the order, which says why (and shows
      // the S3 wording while payment is not open).
      if (mode != 'provider' || live) {
        _toOrder();
        return;
      }
      // An order whose hold ended is not paid any more (409 hold_expired).
      if (d.order.status == EventOrderStatus.expired) {
        setState(() => _phase = _Phase.expired);
        return;
      }
      if (!d.order.isAwaitingPayment) {
        _toOrder();
        return;
      }
      await _checkMomo();
      if (!mounted) return;
      if (!_startedEvent) {
        _startedEvent = true;
        EventsAnalytics.paymentStarted(
          orderId: d.order.id,
          mode: mode,
          late: false,
          eventId: d.order.eventId,
        );
      }
      setState(() => _phase = _Phase.form);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _heading.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is ApiException && e.status == 404) {
          _phase = _Phase.gone;
        } else {
          _phase = _Phase.error;
          _error = e;
          _offline = isNetworkError(e);
        }
      });
    }
  }

  /// Whether the mobile-money sheet may be offered at all.
  Future<void> _checkMomo() async {
    try {
      final options = await _api.paymentOptions();
      _momoOffered = momoOffers(
        options,
        MomoProduct.eventOrder,
        role: 'member',
      );
    } catch (_) {
      _momoOffered = false;
    }
  }

  /// The way to pay changed under us: re-read the options and the order.
  Future<void> _reloadForMode() async {
    try {
      _freshOptions = EventsOptions.fromJson(await _api.eventsOptions());
    } catch (_) {}
    if (!mounted) return;
    await _load();
  }

  Future<void> _send() async {
    final d = _detail!;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      final res = EventPaymentSubmission.fromJson(
        await _api.payEventOrder(
          d.order.id,
          body: const <String, dynamic>{},
          idempotencyKey: _attempt!.key,
        ),
      );
      if (!mounted) return;
      EventsAnalytics.paymentSubmitted(
        orderId: d.order.id,
        late: false,
        eventId: d.order.eventId,
      );
      setState(() => _busy = false);
      if (res.mode == 'provider') {
        await _openMomo(res);
        return;
      }
      // Nothing left to pay: the order page tells the state.
      _toOrder(changed: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!eventOrderOutcomeUnknown(e)) _attempt = null;
      setState(() => _busy = false);
      await _handleRefusal(e, snack, locale);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (isNetworkError(e)) _offline = true;
      // The request may have reached the server: keep the form and the key.
      await _showUncertain();
    }
  }

  Future<void> _handleRefusal(
    ApiException e,
    FFSnackMessenger snack,
    FFLocale locale,
  ) async {
    if (eventOrderOutcomeUnknown(e)) {
      await _showUncertain();
      return;
    }
    switch (e.code) {
      case 'payment_in_progress':
        snack.info(eventsErrorMessage(locale, e));
        _toOrder(changed: true);
      case 'hold_expired':
        await _load();
      case 'order_not_payable':
        snack.error(eventsErrorMessage(locale, e));
        _toOrder(changed: true);
      case 'payment_mode_mismatch':
        snack.info(eventsErrorMessage(locale, e));
        await _reloadForMode();
      case 'unsupported_currency' || 'tickets_unavailable':
        setState(() => _unavailable = true);
      case 'too_many_attempts' || 'rate_limited':
        setState(() => _inlineError = e);
      default:
        snack.error(eventsErrorMessage(locale, e));
    }
  }

  Future<void> _showUncertain() async {
    final open = await showFFConfirmDialog(
      context,
      title: context.tr('events.pay.uncertain.title'),
      message: context.tr('events.pay.uncertain.body'),
      confirmLabel: context.tr('events.pay.uncertain.open'),
      cancelLabel: context.tr('common.close'),
      confirmKey: const Key('pay-uncertain-open'),
      cancelKey: const Key('pay-uncertain-close'),
    );
    if (open && mounted) _toOrder(changed: true);
  }

  Future<void> _submitProvider() async {
    final d = _detail;
    if (d == null || _busy) return;
    _attempt = CheckoutAttempt.forPurchase(_attempt, 'provider|${d.order.id}');
    await _send();
  }

  Future<void> _openMomo(EventPaymentSubmission res) async {
    final d = _detail!;
    final id = res.paymentRequestId ?? d.paymentRequestId;
    final amount = d.order.totalTzs;
    final done = await offerMobileMoney(
      context,
      paymentRequestId: id,
      amountTzs: amount,
      productType: MomoProduct.eventOrder,
    );
    if (!mounted) return;
    if (!done && !_momoOffered) {
      setState(() => _unavailable = true);
      return;
    }
    // Success, or a sheet closed mid-flight: the order page tells the state.
    _toOrder(changed: true);
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: () => _toOrder(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.pay.title')),
      ),
      body: switch (_phase) {
        _Phase.loading => FFSkeletonList(
          key: const Key('pay-loading'),
          semanticLabel: context.tr('common.loading'),
        ),
        _Phase.gone => Center(
          child: FFEmptyState(
            key: const Key('pay-gone'),
            icon: Icons.receipt_long_outlined,
            title: context.tr('events.order.gone.title'),
            body: context.tr('events.detail.gone.body'),
          ),
        ),
        _Phase.error => Center(
          child: FFErrorState(
            key: const Key('pay-error'),
            message: _error == null
                ? null
                : errorMessage(FFLocaleScope.of(context), _error!),
            retryLabel: context.tr('common.retry'),
            onRetry: _load,
          ),
        ),
        _Phase.expired => Center(
          child: FFEmptyState(
            key: const Key('pay-expired'),
            icon: Icons.timer_off_outlined,
            title: context.tr('events.pay.hold.ended'),
            body: context.tr('events.order.expired.body'),
            action: FFButton(
              key: const Key('pay-back-expired'),
              label: context.tr('events.pay.back'),
              variant: FFButtonVariant.secondary,
              onPressed: _toOrder,
            ),
          ),
        ),
        _Phase.form => _form(context, _detail!),
      },
      bottomNavigationBar: _phase == _Phase.form ? _bar(context) : null,
    );
  }

  Widget _form(BuildContext context, EventOrderDetail d) {
    final tt = Theme.of(context).textTheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final e = d.event?.summary ?? d.order.event;
    final amount = formatCurrency(d.order.totalTzs, currency: d.order.currency);
    final off = e?.utcOffsetMinutes ?? 0;
    final abbr = e?.timezoneAbbr ?? '';

    final children = <Widget>[
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: FFPageHeader(
            title: context.tr('events.pay.title'),
            description: e?.title,
          ),
        ),
      ),
      if (_offline)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('pay-offline'),
            tone: FFAlertTone.warning,
            message: context.tr('events.pay.offline'),
          ),
        ),
      if (_unavailable)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('pay-unavailable'),
            tone: FFAlertTone.error,
            message: context.tr('events.pay.unavailable'),
          ),
        ),
      if (_inlineError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Semantics(
            liveRegion: true,
            child: FFAlert(
              key: const Key('pay-inline-error'),
              tone: FFAlertTone.warning,
              message: eventsErrorMessage(
                FFLocaleScope.of(context),
                _inlineError!,
              ),
            ),
          ),
        ),
      // ── recap ─────────────────────────────────────────────────────────
      FFCard(
        key: const Key('pay-recap'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('events.pay.recap.title'), style: tt.titleSmall),
            const SizedBox(height: FFTokens.spacingXs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${d.order.reference} · ${context.tr('events.order.places').replaceFirst('{n}', '${d.order.placesCount > 0 ? d.order.placesCount : d.registrations.length}')}',
                    key: const Key('pay-recap-ref'),
                    style: tt.bodyMedium,
                  ),
                ),
                IconButton(
                  key: const Key('pay-copy-ref'),
                  tooltip: context.tr('common.copy'),
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  onPressed: () async {
                    final snack = FFSnack.of(context);
                    final copied = context.tr('common.copied');
                    await Clipboard.setData(
                      ClipboardData(text: d.order.reference),
                    );
                    snack.success(copied);
                  },
                ),
              ],
            ),
            Text(
              context.tr('events.pay.exact').replaceFirst('{amount}', amount),
              key: const Key('pay-exact'),
              style: tt.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (d.order.holdExpiresAt != null) ...[
              const SizedBox(height: FFTokens.spacingXs),
              Text(
                context
                    .tr('events.order.heldUntil')
                    .replaceFirst(
                      '{time}',
                      eventTime(
                        d.order.holdExpiresAt!,
                        off,
                        abbr,
                        locale: lang,
                      ),
                    ),
                style: tt.bodySmall,
              ),
              FFCountdownText(
                key: const Key('pay-countdown'),
                until: d.order.holdExpiresAt!,
                now: widget.now == null ? null : () => widget.now!,
                minutesLabel: context.tr('events.order.left'),
                secondsLabel: context.tr('events.order.leftSeconds'),
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                urgentStyle: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? FFTokens.fuelOnDark
                      : FFTokens.fuel,
                ),
                onDone: _load,
              ),
            ],
          ],
        ),
      ),
      _providerBody(context),
      const SizedBox(height: FFTokens.spacingLg),
    ];
    return ListView(
      key: const Key('pay-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _providerBody(BuildContext context) {
    if (_momoOffered) return const SizedBox.shrink();
    return FFAlert(
      key: const Key('pay-provider-unavailable'),
      tone: FFAlertTone.warning,
      message: context.tr('events.pay.provider.unavailable'),
    );
  }

  Widget _bar(BuildContext context) {
    final d = _detail!;
    final amount = formatCurrency(d.order.totalTzs, currency: d.order.currency);
    final cs = Theme.of(context).colorScheme;
    final primary = FFButton(
      key: const Key('pay-provider-cta'),
      label: context
          .tr('events.pay.provider.cta')
          .replaceFirst('{amount}', amount),
      fullWidth: true,
      maxLines: 2,
      loading: _busy,
      onPressed: _busy || _unavailable || !_momoOffered || _offline
          ? null
          : _submitProvider,
    );
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
              child: Row(
                children: [
                  FFButton(
                    key: const Key('pay-back'),
                    label: context.tr('events.pay.back'),
                    variant: FFButtonVariant.ghost,
                    onPressed: _busy ? null : _toOrder,
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(child: primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
