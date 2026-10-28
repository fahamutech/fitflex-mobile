import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_ticket.dart';
import '../../../../shared/events/event_time.dart';
import '../../../../shared/events/events_analytics.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../events_registration_gate.dart';

enum _Phase { loading, ready, revoked, claimedElsewhere, error }

/// `/member/events/registrations/:registrationId/ticket` (events S4 spec
/// §5.5, §5.8). Draws the QR from the server's own payload; the ticket
/// number, participant, category and state are text too, so a screen-reader
/// user never depends on the picture. Makes no claim that the code gets
/// anyone anywhere: while kit scanning is not live it says so.
class MemberEventTicketPage extends StatefulWidget {
  const MemberEventTicketPage({
    super.key,
    required this.registrationId,
    this.options,
  });

  final String registrationId;
  final EventsOptions? options;

  @override
  State<MemberEventTicketPage> createState() => _MemberEventTicketPageState();
}

class _MemberEventTicketPageState extends State<MemberEventTicketPage> {
  _Phase _phase = _Phase.loading;
  EventTicketPayload? _ticket;
  DateTime? _savedAt;
  bool _offline = false;
  bool _busy = false;
  Object? _error;
  String _revokedReason = 'cancelled';
  String _claimedName = '';
  final _heading = FocusNode(debugLabel: 'ticket-heading');

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

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

  void _focusHeading() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _heading.requestFocus();
  });

  Future<void> _load() async {
    setState(() {
      _phase = _ticket == null ? _Phase.loading : _phase;
      _error = null;
    });
    final id = widget.registrationId;
    try {
      final json = await _api.getEventTicket(id);
      if (!mounted) return;
      final t = EventTicketPayload.fromJson(json);
      await EventTicketCache.put(id, json, eventStartsAt: t.event?.startsAt);
      if (!mounted) return;
      EventsAnalytics.ticketOpened(registrationId: id);
      setState(() {
        _ticket = t;
        _savedAt = null;
        _offline = false;
        _phase = _Phase.ready;
      });
      _focusHeading();
    } on ApiException catch (e) {
      if (!mounted) return;
      await _onRefused(e);
    } catch (e) {
      if (!mounted) return;
      await _onUnreachable(e);
    }
  }

  Future<void> _onRefused(ApiException e) async {
    final id = widget.registrationId;
    final cached = await EventTicketCache.get(id);
    switch (e.code) {
      case 'ticket_revoked':
        final reason = e.body is Map
            ? (e.body as Map)['reason']?.toString()
            : null;
        await EventTicketCache.remove(id);
        if (!mounted) return;
        setState(() {
          _revokedReason =
              const {
                'cancelled',
                'event_cancelled',
                'refunded',
              }.contains(reason)
              ? reason!
              : 'cancelled';
          _ticket = null;
          _phase = _Phase.revoked;
        });
        _focusHeading();
      case 'ticket_not_issued':
        // Paid but not issued yet: the registration page says what is going
        // on ("being prepared").
        if (!mounted) return;
        context.pushReplacement(AppRoutes.memberEventRegistrationPath(id));
      case 'registration_not_found':
        await EventTicketCache.remove(id);
        if (!mounted) return;
        setState(() {
          _claimedName = cached?.ticket.firstName ?? _claimedName;
          _ticket = null;
          _phase = _Phase.claimedElsewhere;
        });
        _focusHeading();
      default:
        setState(() {
          _error = e;
          _phase = _ticket == null ? _Phase.error : _phase;
        });
    }
  }

  Future<void> _onUnreachable(Object e) async {
    final cached = await EventTicketCache.get(widget.registrationId);
    if (!mounted) return;
    if (isNetworkError(e) && cached != null) {
      setState(() {
        _ticket = cached.ticket;
        _savedAt = cached.savedAt;
        _offline = true;
        _phase = _Phase.ready;
      });
      _focusHeading();
      return;
    }
    setState(() {
      _error = e;
      _phase = _ticket == null ? _Phase.error : _phase;
    });
  }

  Future<void> _rotate() async {
    if (_busy) return;
    final yes = await showFFConfirmDialog(
      context,
      title: context.tr('events.ticket.rotate.title'),
      message: context.tr('events.ticket.rotate.body'),
      confirmLabel: context.tr('events.ticket.rotate'),
      cancelLabel: context.tr('common.cancel'),
      confirmKey: const Key('ticket-rotate-confirm'),
      cancelKey: const Key('ticket-rotate-cancel'),
    );
    if (!yes || !mounted) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr('events.ticket.rotate.done');
    setState(() => _busy = true);
    try {
      final json = await _api.rotateEventTicket(widget.registrationId);
      if (!mounted) return;
      final t = EventTicketPayload.fromJson(json);
      // The old code is dropped from this phone with the old payload.
      await EventTicketCache.put(
        widget.registrationId,
        json,
        eventStartsAt: t.event?.startsAt,
      );
      if (!mounted) return;
      EventsAnalytics.ticketRotated();
      setState(() {
        _ticket = t;
        _savedAt = null;
        _busy = false;
      });
      snack.success(done);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'ticket_revoked') {
        await _onRefused(e);
      } else {
        snack.error(eventsErrorMessage(locale, e));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(eventsErrorMessage(locale, e));
    }
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(
          AppRoutes.memberEventRegistrationPath(widget.registrationId),
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.reg.ticket')),
      ),
      body: switch (_phase) {
        _Phase.loading => FFSkeletonList(
          key: const Key('ticket-loading'),
          semanticLabel: context.tr('events.ticket.loading'),
        ),
        _Phase.error => Center(
          child: FFErrorState(
            key: const Key('ticket-error'),
            message: _error == null
                ? null
                : errorMessage(FFLocaleScope.of(context), _error!),
            retryLabel: context.tr('common.retry'),
            onRetry: _load,
          ),
        ),
        _ => _content(context),
      },
    );
  }

  Widget _content(BuildContext context) {
    final children = switch (_phase) {
      _Phase.revoked => _revoked(context),
      _Phase.claimedElsewhere => _claimed(context),
      _ => _ready(context, _ticket!),
    };
    return ListView(
      key: const Key('ticket-scroll'),
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

  List<Widget> _revoked(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return [
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: Text(
            context.tr('events.ticket.revoked.$_revokedReason'),
            key: const Key('ticket-revoked-title'),
            style: tt.titleLarge,
          ),
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      // No QR is drawn for a ticket that no longer works.
      FFCard(
        key: const Key('ticket-revoked'),
        child: Row(
          children: [
            const Icon(Icons.block_outlined),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: Text(
                context.tr('events.ticket.revoked.body'),
                style: tt.bodyMedium,
              ),
            ),
          ],
        ),
      ),
      _viewRegistration(context),
    ];
  }

  List<Widget> _claimed(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final name = _claimedName.trim();
    return [
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: Text(context.tr('events.ticket.show'), style: tt.titleLarge),
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFCard(
        key: const Key('ticket-claimed-elsewhere'),
        child: Text(
          name.isEmpty
              ? context.tr('events.ticket.claimedElsewhere.generic')
              : context
                    .tr('events.ticket.claimedElsewhere')
                    .replaceFirst('{name}', name),
          style: tt.bodyMedium,
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FFButton(
          key: const Key('ticket-claimed-back'),
          label: context.tr('events.mine.title'),
          variant: FFButtonVariant.ghost,
          onPressed: () => context.go(AppRoutes.memberEventTickets),
        ),
      ),
    ];
  }

  Widget _viewRegistration(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FFButton(
      key: const Key('ticket-view-registration'),
      label: context.tr('events.ticket.view'),
      variant: FFButtonVariant.ghost,
      onPressed: () => context.push(
        AppRoutes.memberEventRegistrationPath(widget.registrationId),
      ),
    ),
  );

  List<Widget> _ready(BuildContext context, EventTicketPayload t) {
    final tt = Theme.of(context).textTheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final e = t.event;
    final off = e?.utcOffsetMinutes ?? 0;
    final abbr = e?.timezoneAbbr ?? '';
    final scanning = t.scanning || _options.tickets.scanning;
    final when = e?.startsAt == null
        ? null
        : eventDateTime(e!.startsAt!, off, abbr, locale: lang);
    final label = context
        .tr('events.ticket.qr.a11y')
        .replaceFirst('{name}', t.participantName)
        .replaceFirst('{category}', t.categoryName)
        .replaceFirst('{code}', t.displayCode);
    return [
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: FFPageHeader(
            title: e?.title ?? context.tr('events.ticket.show'),
            description: when,
          ),
        ),
      ),
      if (_offline)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('ticket-offline'),
            tone: FFAlertTone.warning,
            message: context.tr('events.ticket.offline'),
          ),
        ),
      // The code: fixed dark ink on white in both themes, with a quiet zone.
      FFCard(
        padding: EdgeInsets.zero,
        child: Container(
          key: const Key('ticket-qr-card'),
          color: FFTokens.qrBackground,
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, c) {
              final size = (c.maxWidth).clamp(240.0, 320.0);
              return Center(
                child: Semantics(
                  container: true,
                  label: label,
                  image: true,
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: size,
                      child: FFQrCode(
                        key: const Key('ticket-qr'),
                        data: t.drawn,
                        size: size,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      Text(
        t.participantName,
        key: const Key('ticket-participant'),
        style: tt.titleMedium,
      ),
      Text(
        [
          t.categoryName,
          t.ticketTypeName,
        ].where((s) => s.isNotEmpty).join(' · '),
        key: const Key('ticket-category'),
        style: tt.bodyMedium,
      ),
      const SizedBox(height: FFTokens.spacingXs),
      Row(
        children: [
          Expanded(
            child: Text(
              context
                  .tr('events.ticket.number')
                  .replaceFirst('{code}', t.displayCode),
              key: const Key('ticket-number'),
              style: tt.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            key: const Key('ticket-copy-number'),
            tooltip: context.tr('events.ticket.copy'),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: () async {
              final snack = FFSnack.of(context);
              final copied = context.tr('events.ticket.copied');
              await Clipboard.setData(ClipboardData(text: t.displayCode));
              snack.success(copied);
            },
          ),
        ],
      ),
      Wrap(
        spacing: FFTokens.spacingSm,
        runSpacing: FFTokens.spacingXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FFBadge(
            key: const Key('ticket-state'),
            label: context.tr('events.ticket.ready'),
            tone: FFBadgeTone.success,
          ),
          if (_savedAt != null)
            FFBadge(
              key: const Key('ticket-cached'),
              label: context
                  .tr('events.ticket.cached')
                  .replaceFirst(
                    '{time}',
                    formatDateTime(_savedAt, locale: lang),
                  ),
              tone: FFBadgeTone.gray,
              wrap: true,
            ),
        ],
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFAlert(
        key: const Key('ticket-scan-note'),
        tone: FFAlertTone.info,
        message: context.tr(
          scanning ? 'events.ticket.scan.live' : 'events.ticket.scan.soon',
        ),
      ),
      if (t.isHandover) ...[
        const SizedBox(height: FFTokens.spacingSm),
        FFAlert(
          key: const Key('ticket-handover'),
          tone: FFAlertTone.info,
          message: context
              .tr('events.ticket.handover')
              .replaceFirst('{name}', t.firstName),
        ),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      FFButton(
        key: const Key('ticket-rotate'),
        label: context.tr('events.ticket.rotate'),
        variant: FFButtonVariant.ghost,
        loading: _busy,
        onPressed: _offline ? null : _rotate,
      ),
      _viewRegistration(context),
    ];
  }
}
