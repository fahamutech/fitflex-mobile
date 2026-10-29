import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_claim_link.dart';
import '../../../shared/events/event_order.dart';
import '../../../shared/events/event_time.dart';
import '../../../shared/events/events_analytics.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/i18n.dart';
import '../../../shared/widgets/verify_identifier.dart';
import 'events_registration_gate.dart';

/// "Is this you?" (events S3 spec §5.11). Link mode reads the kept token
/// from `/event-claim/#<token>` and previews it (signed in or not); in-app
/// mode comes from a `claimable` card or the `event_claim_available`
/// notice and claims by id. Masked data only; the claim needs a verified
/// contact (REG-010).
class EventClaimPage extends StatefulWidget {
  const EventClaimPage.link({super.key, this.options}) : registrationId = null;
  const EventClaimPage.inApp({
    super.key,
    required this.registrationId,
    this.options,
  });

  /// Null in link mode.
  final String? registrationId;
  final EventsOptions? options;

  bool get linkMode => registrationId == null;

  @override
  State<EventClaimPage> createState() => _EventClaimPageState();
}

class _EventClaimPageState extends State<EventClaimPage> {
  ClaimPreview? _preview;
  String? _token;
  bool _loading = true;
  Object? _error;

  /// A refusal that has its own screen state (`claim_not_verified`,
  /// `claim_token_expired`, …), keyed by code.
  String? _refusal;
  bool _busy = false;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);
  bool get _signedIn => AppScope.of(context).auth.isSignedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    // In-app mode is gated like every S3 route; link mode keeps working
    // (the token is kept) and tells the person registration is off.
    if (!widget.linkMode && !eventsRegistrationAllowed(context, _options)) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _refusal = null;
    });
    try {
      if (widget.linkMode) {
        final token = await PendingEventClaim.peek();
        if (!mounted) return;
        if (token == null) {
          setState(() {
            _refusal = 'claim_token_invalid';
            _loading = false;
          });
          return;
        }
        _token = token;
        final res = await _api.previewEventClaim(token);
        if (!mounted) return;
        setState(() {
          _preview = ClaimPreview.fromJson(res);
          _loading = false;
        });
      } else {
        // The card data came from `claimable`; reading the list again is
        // the one route that returns the masked row by id.
        final res = await _api.claimableEventRegistrations();
        if (!mounted) return;
        final items = res['items'] is List ? res['items'] as List : const [];
        ClaimPreview? found;
        for (final i in items) {
          if (i is Map && i['id']?.toString() == widget.registrationId) {
            found = ClaimPreview.fromJson(i);
          }
        }
        setState(() {
          _preview = found;
          _refusal = found == null ? 'registration_not_found' : null;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.code == 'feature_disabled') {
          // Registration is off: the kept token stays for when it flips.
          _refusal = 'feature_disabled';
        } else if (e.status == 404 && widget.linkMode) {
          _refusal = 'claim_token_invalid';
          PendingEventClaim.clear();
        } else if (e.status == 410) {
          _refusal = 'claim_token_expired';
          PendingEventClaim.clear();
        } else {
          _error = e;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _claim() async {
    if (_busy) return;
    if (!_signedIn) {
      context.go(AppRoutes.language);
      return;
    }
    setState(() {
      _busy = true;
      _refusal = null;
    });
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr('events.claim.done');
    try {
      final res = widget.linkMode
          ? await _api.claimEventRegistrationByToken(_token!)
          : await _api.claimEventRegistration(widget.registrationId!);
      if (!mounted) return;
      final reg = res['registration'] is Map
          ? EventRegistration.fromJson(res['registration'] as Map)
          : null;
      final id = reg?.id ?? widget.registrationId ?? '';
      EventsAnalytics.registrationClaimed(
        registrationId: id,
        via: widget.linkMode ? 'link' : 'in_app',
      );
      if (widget.linkMode) await PendingEventClaim.clear();
      if (!mounted) return;
      snack.success(done);
      if (id.isNotEmpty) {
        // A paid place has its ticket now (events S4 spec §5.9): open it.
        // A ticket the server did not describe is tried too; the ticket
        // page hands over to the registration if none is issued yet.
        final ticketReady =
            reg != null &&
            reg.status == EventRegistrationStatus.confirmed &&
            (reg.ticket == null || reg.ticket!.isActive);
        context.pushReplacement(
          ticketReady
              ? AppRoutes.memberEventTicketPath(id)
              : AppRoutes.memberEventRegistrationPath(id),
        );
      } else {
        context.go(AppRoutes.memberEventOrders);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final code = e.code ?? '';
      setState(() {
        _busy = false;
        if (const {
          'claim_not_verified',
          'already_claimed',
          'claim_token_expired',
          'claim_token_invalid',
          'registration_closed_state',
          'claim_own_contact',
          'registration_not_found',
        }.contains(code)) {
          _refusal = code;
        }
      });
      if (_refusal == null) snack.error(errorMessage(locale, e));
      if (code == 'claim_token_expired' || code == 'claim_token_invalid') {
        PendingEventClaim.clear();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(errorMessage(locale, e));
    }
  }

  Future<void> _notMe() async {
    await PendingEventClaim.clear();
    if (!mounted) return;
    context.go(_signedIn ? AppRoutes.memberActivity : AppRoutes.language);
  }

  void _verifyNow() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ContactDetailsScreen()));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).auth,
    builder: (context, _) => _scaffold(context),
  );

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(
                  _signedIn ? AppRoutes.memberEventOrders : AppRoutes.language,
                ),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.claim.title')),
      ),
      body: _loading
          ? const Center(child: FFSpinner())
          : ListView(
              key: const Key('claim-scroll'),
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _content(context),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final locale = FFLocaleScope.of(context);
    final p = _preview;

    if (_error != null) {
      return [
        FFErrorState(
          key: const Key('claim-error'),
          message: errorMessage(locale, _error!),
          retryLabel: context.tr('common.retry'),
          onRetry: _load,
        ),
      ];
    }

    // Terminal refusals: the preview (if any) stays above the message.
    final terminal = const {
      'claim_token_invalid',
      'claim_token_expired',
      'already_claimed',
      'registration_closed_state',
      'claim_own_contact',
      'registration_not_found',
      'feature_disabled',
    }.contains(_refusal);

    final out = <Widget>[];
    if (p != null) {
      final date = p.event?.startsAt == null
          ? ''
          : eventDayDate(
              p.event!.startsAt!,
              p.event!.utcOffsetMinutes,
              locale: lang,
            );
      final type = context.tr('events.claim.type.${p.contactType}');
      out.add(
        FFCard(
          key: const Key('claim-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context
                    .tr('events.claim.card')
                    .replaceFirst('{purchaser}', p.purchaserMasked)
                    .replaceFirst('{name}', p.participantMasked)
                    .replaceFirst('{event}', p.event?.title ?? '')
                    .replaceFirst(
                      '{category}',
                      [
                        p.categoryName,
                        date,
                      ].where((s) => s.isNotEmpty).join(', '),
                    ),
                style: tt.titleSmall,
              ),
              if (p.contactMasked.isNotEmpty) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  context
                      .tr('events.claim.needVerified')
                      .replaceFirst('{type}', type)
                      .replaceFirst('{masked}', p.contactMasked),
                  key: const Key('claim-need-verified'),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      );
      if (p.status == 'confirmed') {
        out.add(
          Text(
            context.tr('events.claim.paid'),
            key: const Key('claim-paid'),
            style: tt.bodyMedium,
          ),
        );
      }
      out.add(const SizedBox(height: FFTokens.spacingMd));
    }

    if (terminal) {
      final key = switch (_refusal) {
        'feature_disabled' => 'events.register.unavailable',
        'registration_not_found' => 'error.reason.registrationNotFound',
        _ => errorReasonKeyFor(_refusal!),
      };
      // An expired link can be replaced: the purchaser sends it again.
      final ask = _refusal == 'claim_token_expired'
          ? context
                .tr('events.invite.expiredAsk')
                .replaceFirst(
                  '{name}',
                  (p?.purchaserMasked ?? '').trim().isEmpty
                      ? context.tr('events.cancelpaid.purchaserFallback')
                      : p!.purchaserMasked.split(' ').first,
                )
          : null;
      out.add(
        FFEmptyState(
          key: Key('claim-refused-$_refusal'),
          icon: Icons.link_off,
          title: context.tr(key),
          body: ask,
        ),
      );
      return out;
    }

    if (_refusal == 'claim_not_verified') {
      // The 403 body names no contact: the preview's masked contact and
      // the server's `claim` options say what can be verified.
      final type = p?.contactType.isNotEmpty == true ? p!.contactType : 'phone';
      final masked = p?.contactMasked ?? '';
      final verifiable = _options.claim.verifiable(type);
      out.add(
        FFAlert(
          key: const Key('claim-not-verified'),
          tone: FFAlertTone.warning,
          message: context
              .tr('events.claim.verify')
              .replaceFirst('{masked}', masked),
        ),
      );
      out.add(const SizedBox(height: FFTokens.spacingSm));
      if (verifiable) {
        out.add(
          FFButton(
            key: const Key('claim-verify-now'),
            label: context.tr('events.claim.verifyNow'),
            onPressed: _verifyNow,
          ),
        );
      } else {
        out.add(
          Text(
            context
                .tr('events.claim.emailNotYet')
                .replaceFirst(
                  '{name}',
                  (p?.purchaserMasked ?? '').split(' ').first,
                ),
            key: const Key('claim-email-not-yet'),
            style: tt.bodyMedium,
          ),
        );
      }
      out.add(const SizedBox(height: FFTokens.spacingMd));
    }

    out.add(
      FFButton(
        key: const Key('claim-confirm'),
        label: _signedIn
            ? context.tr('events.claim.confirm')
            : context.tr('events.claim.signIn'),
        fullWidth: true,
        loading: _busy,
        onPressed: _claim,
      ),
    );
    out.add(const SizedBox(height: FFTokens.spacingSm));
    out.add(
      FFButton(
        key: const Key('claim-not-me'),
        label: context.tr('events.claim.no'),
        variant: FFButtonVariant.ghost,
        fullWidth: true,
        onPressed: _busy ? null : _notMe,
      ),
    );
    return out;
  }
}

/// The `error.reason.*` key for a claim refusal code (§5.11 copy).
String errorReasonKeyFor(String code) => switch (code) {
  'claim_token_invalid' => 'error.reason.claimTokenInvalid',
  'claim_token_expired' => 'error.reason.claimTokenExpired',
  'already_claimed' => 'error.reason.alreadyClaimed',
  'registration_closed_state' => 'error.reason.registrationClosedState',
  'claim_own_contact' => 'error.reason.claimOwnContact',
  _ => 'error.requestFailed',
};
