import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_order.dart';
import '../../../shared/events/event_time.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import 'event_cancel_reason_dialog.dart';
import 'events_registration_gate.dart';

/// `/member/events/registrations/:registrationId` (events S3 spec §5.9):
/// one place — status, the QR placeholder (S5), the participant's details,
/// event, team and order rows, and "remove this person" for the purchaser.
class MemberEventRegistrationPage extends StatefulWidget {
  const MemberEventRegistrationPage({
    super.key,
    required this.registrationId,
    this.options,
  });

  final String registrationId;
  final EventsOptions? options;

  @override
  State<MemberEventRegistrationPage> createState() =>
      _MemberEventRegistrationPageState();
}

class _MemberEventRegistrationPageState
    extends State<MemberEventRegistrationPage> {
  EventRegistration? _reg;
  bool _loading = true;
  Object? _error;
  bool _gone = false;
  bool _busy = false;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _reg == null;
      _error = null;
      _gone = false;
    });
    try {
      final json = await _api.getEventRegistration(widget.registrationId);
      if (!mounted) return;
      setState(() {
        _reg = EventRegistration.fromJson(json);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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

  Future<void> _remove() async {
    final r = _reg;
    if (r == null || _busy) return;
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
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'remove_whole_line') {
        final open = await showFFConfirmDialog(
          context,
          title: context.tr('events.order.cancel'),
          message: context
              .tr('events.reg.remove.lastLine')
              .replaceFirst('{ticket}', r.ticketTypeName),
          confirmLabel: context
              .tr('events.reg.openOrder')
              .replaceFirst('{ref}', r.orderReference),
          cancelLabel: context.tr('common.close'),
          confirmKey: const Key('remove-whole-line-open'),
        );
        if (open && mounted) {
          context.push(AppRoutes.memberEventOrder(r.orderId));
        }
        return;
      }
      snack.error(errorMessage(locale, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(errorMessage(locale, e));
    }
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.memberEventOrders);

  @override
  Widget build(BuildContext context) {
    final r = _reg;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.reg.title')),
      ),
      body: _gone
          ? Center(
              child: FFEmptyState(
                key: const Key('reg-gone'),
                icon: Icons.confirmation_number_outlined,
                title: context.tr('events.reg.gone.title'),
                body: context.tr('events.detail.gone.body'),
              ),
            )
          : _loading
          ? FFSkeletonList(
              key: const Key('reg-loading'),
              semanticLabel: context.tr('common.loading'),
            )
          : r == null
          ? Center(
              child: FFErrorState(
                key: const Key('reg-error'),
                message: _error == null
                    ? null
                    : errorMessage(FFLocaleScope.of(context), _error!),
                retryLabel: context.tr('common.retry'),
                onRetry: _load,
              ),
            )
          : ListView(
              key: const Key('reg-scroll'),
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _content(context, r),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _content(BuildContext context, EventRegistration r) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final e = r.event;
    final off = e?.utcOffsetMinutes ?? 0;
    final abbr = e?.timezoneAbbr ?? '';
    final live = registrationIsLive(r.status, r.orderStatus);
    final statusKey = eventRegistrationStatusKey(r.status, r.orderStatus);
    final reserved = live && r.status == EventRegistrationStatus.reserved;

    Widget line(String label, String? value, {Key? key}) =>
        value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            key: key,
            padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    label,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Expanded(child: Text(value, style: tt.bodyMedium)),
              ],
            ),
          );

    return [
      Semantics(
        header: true,
        child: Text(
          r.fullName,
          key: const Key('reg-name'),
          style: tt.titleLarge,
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      // ── status ────────────────────────────────────────────────────────
      if (reserved)
        FFAlert(
          key: const Key('reg-awaiting'),
          tone: FFAlertTone.info,
          message: context
              .tr('events.reg.awaiting')
              .replaceFirst(
                '{time}',
                r.holdExpiresAt == null
                    ? '—'
                    : eventTime(r.holdExpiresAt!, off, abbr, locale: lang),
              ),
        )
      else
        Align(
          alignment: Alignment.centerLeft,
          child: FFBadge(
            key: const Key('reg-status'),
            label: context.tr(statusKey),
            tone: r.status == EventRegistrationStatus.confirmed
                ? FFBadgeTone.success
                : FFBadgeTone.gray,
          ),
        ),
      if (r.orderId.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            key: const Key('reg-open-order'),
            label: context
                .tr('events.reg.openOrder')
                .replaceFirst('{ref}', r.orderReference),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            onPressed: () =>
                context.push(AppRoutes.memberEventOrder(r.orderId)),
          ),
        ),
      // ── ticket placeholder (S5) ───────────────────────────────────────
      FFSectionTitle(context.tr('events.reg.ticket')),
      FFCard(
        key: const Key('reg-ticket-placeholder'),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                  border: Border.all(
                    color: cs.outline,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Icon(Icons.qr_code_2, size: 48, color: cs.outline),
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context.tr('events.reg.ticketSoon'),
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      // ── participant ───────────────────────────────────────────────────
      if (r.hasParticipantDetails) ...[
        FFSectionTitle(context.tr('events.reg.participant')),
        FFCard(
          key: const Key('reg-participant'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line(context.tr('events.participant.phone'), r.phone),
              line(context.tr('events.participant.email'), r.email),
              line(
                context.tr('events.participant.dob'),
                r.dateOfBirth == null
                    ? null
                    : formatDate(r.dateOfBirth, locale: lang),
              ),
              line(
                context.tr('events.participant.gender'),
                r.gender == null
                    ? null
                    : context.tr('onboarding.gender_${r.gender}'),
              ),
              line(
                context.tr('events.participant.kitSize'),
                r.kitSize?.toUpperCase(),
              ),
              if (r.emergencyContact != null && !r.emergencyContact!.isEmpty)
                line(
                  context.tr('events.participant.emergency'),
                  '${r.emergencyContact!.name} · ${r.emergencyContact!.phone}',
                  key: const Key('reg-emergency'),
                ),
            ],
          ),
        ),
      ],
      // ── event ─────────────────────────────────────────────────────────
      if (e != null) ...[
        FFSectionTitle(context.tr('events.reg.event')),
        FFActionTile(
          key: const Key('reg-event'),
          icon: Icons.flag_outlined,
          title: e.title,
          subtitle: [
            r.categoryName,
            if (r.categoryStartsAt ?? e.startsAt case final at?)
              eventDateTime(at, off, abbr, locale: lang),
          ].where((s) => s.isNotEmpty).join(' · '),
          onTap: () => context.push(AppRoutes.memberEventDetailPath(e.id)),
        ),
      ],
      if (r.teamId != null)
        FFActionTile(
          key: const Key('reg-team'),
          icon: Icons.groups_outlined,
          title: r.teamName ?? context.tr('events.review.team'),
          onTap: () => context.push(AppRoutes.memberEventTeamPath(r.teamId!)),
        ),
      // ── consent line ──────────────────────────────────────────────────
      const SizedBox(height: FFTokens.spacingSm),
      Text(
        r.viewerIsPurchaser
            ? context
                  .tr('events.reg.consent.self')
                  .replaceFirst(
                    '{date}',
                    (r.consentAt ?? r.createdAt) == null
                        ? '—'
                        : eventDate(
                            (r.consentAt ?? r.createdAt)!,
                            off,
                            locale: lang,
                          ),
                  )
            : context
                  .tr('events.reg.consent')
                  .replaceFirst('{name}', r.purchaserNameMasked ?? '')
                  .replaceFirst(
                    '{date}',
                    (r.consentAt ?? r.createdAt) == null
                        ? '—'
                        : eventDate(
                            (r.consentAt ?? r.createdAt)!,
                            off,
                            locale: lang,
                          ),
                  ),
        key: const Key('reg-consent'),
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: FFTokens.spacingMd),
      // ── actions ───────────────────────────────────────────────────────
      if (r.viewerIsPurchaser && reserved && r.canCancel)
        FFButton(
          key: const Key('reg-remove'),
          label: context.tr('events.reg.remove'),
          variant: FFButtonVariant.destructive,
          loading: _busy,
          onPressed: _remove,
        )
      else if (!r.viewerIsPurchaser && live)
        Text(
          context
              .tr('events.reg.askPurchaser')
              .replaceFirst(
                '{name}',
                (r.purchaserNameMasked ?? '').split(' ').first,
              ),
          key: const Key('reg-ask-purchaser'),
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
    ];
  }
}
