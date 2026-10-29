import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/tone_theme.dart';
import '../../shared/formatters.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/i18n.dart';
import '../../shared/manual_payment.dart';
import '../../shared/models.dart';
import '../../shared/pass_gyms.dart';
import '../../shared/photo_footer_flag.dart';
import '../../shared/photo_hero_flag.dart';
import '../../shared/payment_labels.dart';
import 'widgets/mobile_money_pay.dart';
import 'widgets/pass_gyms_sheet.dart';
import 'member_shell.dart';

/// PHOTO_HERO_UI (owner 2026-10-22, bands "too dark"): no clear photo on
/// the buy band. Any clear photo needs the band about 97px taller (the
/// 48px lead-in and the top fade come first), which puts the first plan
/// card (at 43% of a 390x844 screen today) below 55% of the screen...
const double buyBandClearPhoto = 0;

/// ...and none on Upgrade plan's band either: its first option already
/// starts at 55% of a 390x844 screen.
const double upgradeBandClearPhoto = 0;

class MemberPassesPage extends StatelessWidget {
  const MemberPassesPage({super.key});

  Future<void> _retry(BuildContext context, MemberData data) async {
    final api = AppScope.of(context).api;
    data.update((d) {
      d.passesLoaded = false;
      d.passes = [];
    });
    try {
      final res = await api.listSubscriptionTiers();
      data.update((d) {
        d.passes = res
            .whereType<Map<String, dynamic>>()
            .map(PassTier.fromJson)
            .toList();
        d.passesLoaded = true;
      });
    } catch (_) {
      try {
        final res = await api.listPasses();
        data.update((d) {
          d.passes = res
              .whereType<Map<String, dynamic>>()
              .map(PassTier.fromJson)
              .toList();
          d.passesLoaded = true;
        });
      } catch (_) {
        data.update((d) => d.passesLoaded = true);
      }
    }
  }

  /// The selected tier if it is still on sale, else the first one offered.
  static String _effectiveTier(MemberData data) =>
      data.passes.any((p) => p.id == data.selectedTier)
      ? data.selectedTier
      : data.passes.first.id;

  /// The full catalogue and the continue button, for a member buying a pass.
  static List<Widget> normalList(BuildContext context, MemberData data) => [
    ...data.passes.map(
      (p) => _SelectablePass(
        pass: p,
        selected: p.id == _effectiveTier(data),
        gyms: data.gyms,
        onTap: () => data.update((d) => d.selectedTier = p.id),
      ),
    ),
    const SizedBox(height: 12),
    FFAlert(message: context.tr('pass.note'), tone: FFAlertTone.info),
    const SizedBox(height: 16),
    FFButton(
      label: context.tr('member.continuePayment'),
      onPressed: () {
        // Never carry a stale or default tier into checkout.
        data.update((d) => d.selectedTier = _effectiveTier(data));
        context.go(AppRoutes.memberPayment);
      },
    ),
  ];

  /// PHOTO_HERO_UI (spec §23): the band hero for buy mode and the states
  /// the page decides itself. Upgrade mode draws its own (_UpgradeGate).
  static Widget buyHero(
    BuildContext context, {
    bool headline = true,
    bool subline = true,
    bool pending = false,
    String? eyebrowKey,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
    child: FFHeroBand(
      key: const Key('passes-hero'),
      photo: FFHeroPhoto.upgrade,
      minHeight: 180,
      wideHeight: 200,
      clearPhoto: buyBandClearPhoto,
      eyebrow: context.tr(eyebrowKey ?? 'pay.product.fitflexPass'),
      headlineLead: !headline
          ? null
          : context.tr(
              pending ? 'home.hero.pending.lead' : 'hero.signUp.member.lead',
            ),
      headlineAccent: !headline
          ? null
          : context.tr(
              pending
                  ? 'home.hero.pending.accent'
                  : 'hero.signUp.member.accent',
            ),
      subline: headline && subline && !pending
          ? context.tr('member.planBody')
          : null,
    ),
  );

  Widget _buildPhotoHero(BuildContext context, MemberData data) {
    final listed =
        data.pendingPass == null && data.passesLoaded && data.passes.isNotEmpty;
    return _PassesScroll(
      // Footer (spec §33.6): once the pass list is shown; never while the
      // pending-payment card is on screen. In upgrade mode the gate decides
      // (options shown, no manual-payment fields).
      gated: listed && data.hasActivePass,
      footerEnabled: listed,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: () => context.go(AppRoutes.memberHome),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('pay.product.fitflexPass')),
      ),
      children: (onGateReady) => _photoHeroBody(context, data, onGateReady),
    );
  }

  List<Widget> _photoHeroBody(
    BuildContext context,
    MemberData data,
    ValueChanged<bool> onGateReady,
  ) {
    final List<Widget> body;
    if (data.pendingPass != null) {
      body = [
        buyHero(context, pending: true),
        _PendingBlockCard(pending: data.pendingPass!),
      ];
    } else if (!data.passesLoaded) {
      // Eyebrow only while loading; no headline to take back.
      body = [
        buyHero(
          context,
          headline: false,
          eyebrowKey: data.hasActivePass ? 'member.upgradePlan' : null,
        ),
        const Center(child: FFSpinner(size: 32)),
      ];
    } else if (data.passes.isEmpty) {
      body = [buyHero(context, headline: false), _loadError(context, data)];
    } else if (data.hasActivePass) {
      body = [
        _UpgradeGate(
          withHero: true,
          onFooterReady: onGateReady,
          fallback: Column(
            children: [buyHero(context), ...normalList(context, data)],
          ),
        ),
      ];
    } else {
      body = [buyHero(context), ...normalList(context, data)];
    }
    return body;
  }

  Widget _loadError(BuildContext context, MemberData data) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            context.tr('home.passesLoadError'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FFButton(
            label: context.tr('home.retry'),
            onPressed: () => _retry(context, data),
            variant: FFButtonVariant.secondary,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    if (photoHeroUi) return _buildPhotoHero(context, data);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: () => context.go(AppRoutes.memberHome),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('pay.product.fitflexPass')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.tr('member.planBody'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          const SizedBox(height: 4),
          // Only an open FitFlex Pass payment holds this screen: a pending
          // gym plan or trainer session is a different product.
          if (data.pendingPass != null)
            _PendingBlockCard(pending: data.pendingPass!)
          else if (!data.passesLoaded)
            const Center(child: FFSpinner(size: 32))
          else if (data.passes.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Text(
                      context.tr('home.passesLoadError'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    FFButton(
                      label: context.tr('home.retry'),
                      onPressed: () => _retry(context, data),
                      variant: FFButtonVariant.secondary,
                    ),
                  ],
                ),
              ),
            )
          else if (data.hasActivePass)
            // A member with a paid pass moves up by paying the difference;
            // when there is nothing to upgrade the full list is shown.
            _UpgradeGate(fallback: Column(children: normalList(context, data)))
          else
            ...normalList(context, data),
        ],
      ),
    );
  }
}

/// Asks the server what the member can move up to. A member with a paid pass
/// sees the higher plans and what each costs them (the difference); anyone
/// else, or a member with nothing to upgrade from, gets [fallback].
class _UpgradeGate extends StatefulWidget {
  const _UpgradeGate({
    required this.fallback,
    this.withHero = false,
    this.onFooterReady,
  });

  final Widget fallback;

  /// PHOTO_FOOTER_UI: whether the page footer may show (the options or the
  /// buy list are on screen, and no manual-payment fields).
  final ValueChanged<bool>? onFooterReady;

  /// PHOTO_HERO_UI: lead with the Upgrade plan band hero.
  final bool withHero;

  @override
  State<_UpgradeGate> createState() => _UpgradeGateState();
}

class _UpgradeGateState extends State<_UpgradeGate> {
  late Future<Map<String, dynamic>> _future;
  String? _selected;
  bool _sending = false;
  PaymentModes _modes = PaymentModes.none;
  final _manualInput = ManualPaymentInput();

  @override
  void initState() {
    super.initState();
    // Read without depending on it: initState may not register dependencies.
    final api = context.getInheritedWidgetOfExactType<AppScope>()!.api;
    _future = api.upgradeOptions();
    loadPaymentModes(api).then((m) {
      if (!mounted) return;
      _manualInput.prefillPhone(
        context
            .getInheritedWidgetOfExactType<MemberDataScope>()
            ?.notifier
            ?.me
            ?.user
            .phone,
      );
      setState(() => _modes = m);
    });
  }

  @override
  void dispose() {
    _manualInput.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = AppScope.of(context).api.upgradeOptions());
  }

  Future<void> _submit() async {
    final tier = _selected;
    if (tier == null || _sending) return; // a second tap must not send twice
    final manual = _modes.manual;
    String? reference;
    String? payerPhone;
    if (manual != null) {
      final ready = _manualInput.check(manual);
      if (ready == null) {
        setState(() {});
        return;
      }
      reference = ready.reference;
      payerPhone = ready.payerPhone;
    }
    // Let go of the focused field before it is disabled for the request:
    // disabling a focused field throws "Null check operator used on a null
    // value" on the web, even when the request then fails (L4).
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sending = true);
    try {
      final created = await AppScope.of(
        context,
      ).api.upgradePass(tier, reference: reference, payerPhone: payerPhone);
      if (!mounted) return;
      // A focused field must not outlive the page it is on (L4).
      FocusManager.instance.primaryFocus?.unfocus();
      // An upgrade applies to the pass the member already has once it is
      // approved; it does not start a new plan.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              manual != null
                  ? 'manualPay.submittedUpgrade'
                  : 'upgrade.submitted',
            ),
          ),
        ),
      );
      // With mobile money switched on, pay the difference straight away.
      // A transaction ID means it was paid by hand already.
      final req = created['paymentRequest'];
      if (manual == null && req is Map) {
        await offerMobileMoney(
          context,
          paymentRequestId: req['id'] as String?,
          amountTzs: (req['amountTzs'] as num?) ?? 0,
          productType: MomoProduct.fitflexPass,
        );
        if (!mounted) return;
      }
      final shellState = context.findAncestorStateOfType<MemberShellState>();
      await shellState?.refreshQr();
      await shellState?.refreshMe();
      if (!mounted) return;
      context.go(AppRoutes.memberHome);
    } catch (e) {
      if (!mounted) return;
      if (manual != null && _manualInput.takeServerError(e)) {
        setState(() {});
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(FFLocaleScope.of(context), e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool? _reportedReady;

  void _footerReady(bool ready) {
    if (widget.onFooterReady == null || _reportedReady == ready) return;
    _reportedReady = ready;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFooterReady?.call(ready);
    });
  }

  /// The Upgrade plan hero: eyebrow only while loading or on an error; the
  /// headline says whether there is a higher plan. No price, date or count.
  Widget _hero(BuildContext context, {String? key}) => Padding(
    padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
    child: FFHeroBand(
      key: const Key('passes-hero'),
      photo: FFHeroPhoto.upgrade,
      minHeight: 180,
      wideHeight: 200,
      clearPhoto: upgradeBandClearPhoto,
      eyebrow: context.tr('member.upgradePlan'),
      headlineLead: key == null ? null : context.tr('$key.lead'),
      headlineAccent: key == null ? null : context.tr('$key.accent'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.withHero) return _build(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final error = snap.error;
        final done = snap.connectionState == ConnectionState.done;
        // Buy mode draws its own hero (the fallback).
        if (done && error is ApiException) {
          _footerReady(true);
          return _build(context);
        }
        final options = snap.data?['options'] as List?;
        final key = !done || error != null || !snap.hasData
            ? null
            : (options == null || options.isEmpty)
            ? 'hero.upgrade.top'
            : 'hero.upgrade';
        // The manual-payment fields are a payment step: no footer (§33.6).
        _footerReady(
          key != null && !(_modes.manual != null && _selected != null),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(context, key: key),
            _build(context),
          ],
        );
      },
    );
  }

  Widget _build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // F-10 under the flag: the design-system spinner.
          return widget.withHero
              ? const Center(child: FFSpinner(size: 32))
              : const Center(child: CircularProgressIndicator());
        }
        final error = snap.error;
        // The server answered "nothing to upgrade from": buy a pass as usual.
        if (error is ApiException) return widget.fallback;
        // Never fall back on a bad connection: that would sell the full price.
        if (error != null || !snap.hasData) {
          return Column(
            children: [
              Text(
                context.tr('home.passesLoadError'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FFButton(
                label: context.tr('home.retry'),
                onPressed: _reload,
                variant: FFButtonVariant.secondary,
              ),
            ],
          );
        }
        final current = (snap.data!['current'] as Map?) ?? const {};
        final options = (snap.data!['options'] as List? ?? const [])
            .whereType<Map>()
            .toList();
        final theme = Theme.of(context);
        final memberData = MemberDataScope.of(context);
        // What the member's current plan opens, to show what each upgrade adds.
        final currentAccess = memberData.passes
            .where((p) => p.id == current['tier'])
            .map((p) => p.gymAccess)
            .firstOrNull;
        final knowsCurrent =
            memberData.gyms.isNotEmpty &&
            memberData.passes.any((p) => p.id == current['tier']);
        // The upgrade keeps the plan's end date: show it, and warn when it is close.
        final endsAt = DateTime.tryParse(
          '${current['expiresAt'] ?? ''}',
        )?.toLocal();
        final endsLabel = endsAt == null ? '' : context.localDate(endsAt);
        final daysLeft = endsAt?.difference(DateTime.now()).inDays;
        Map? chosen;
        for (final o in options) {
          if (o['tier'] == _selected) chosen = o;
        }
        final currentCard = FFCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('upgrade.currentPlan'),
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('pass.${current['tier']}'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              Text(
                formatCurrency(((current['priceTzs'] as num?) ?? 0).toInt()),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
        );
        if (options.isEmpty) {
          return Column(
            children: [
              currentCard,
              // Under the flag the hero says it (one owner per message).
              if (!widget.withHero) ...[
                const SizedBox(height: 12),
                FFAlert(
                  message: context.tr('upgrade.highest'),
                  tone: FFAlertTone.info,
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            currentCard,
            const SizedBox(height: 16),
            Text(
              context.tr('upgrade.choose'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...options.map((o) {
              final selected = o['tier'] == _selected;
              final diff = ((o['differenceTzs'] as num?) ?? 0).toInt();
              final access = o['gymAccess'] as String?;
              final added = knowsCurrent
                  ? gymsAddedByUpgrade(currentAccess, access, memberData.gyms)
                  : const <Gym>[];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => setState(() => _selected = o['tier'] as String),
                  borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                  child: Container(
                    padding: const EdgeInsets.all(FFTokens.spacingMd),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary.withValues(alpha: 0.1)
                          : theme.colorScheme.surface,
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('pass.${o['tier']}'),
                                style: theme.textTheme.titleMedium,
                              ),
                              if (added.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    context
                                        .tr('passGyms.added')
                                        .replaceFirst('{n}', '${added.length}'),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              if (memberData.gyms.isNotEmpty)
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    // 48dp, also on the web.
                                    minimumSize: const Size(48, 48),
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    visualDensity: VisualDensity.standard,
                                    alignment: Alignment.centerLeft,
                                  ),
                                  onPressed: () => showPassGymsSheet(
                                    context,
                                    tierId: o['tier'] as String,
                                    gymAccess: access,
                                    gyms: memberData.gyms,
                                    highlightIds: added
                                        .map((g) => g.id)
                                        .toSet(),
                                    onChoose: () => setState(
                                      () => _selected = o['tier'] as String,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.fitness_center,
                                    size: 16,
                                  ),
                                  label: Text(context.tr('passGyms.view')),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '+ ${formatCurrency(diff)}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),
            FFAlert(
              message: context
                  .tr('upgrade.explain')
                  .replaceFirst('{date}', endsLabel),
              tone: FFAlertTone.info,
            ),
            if (daysLeft != null && daysLeft <= 7) ...[
              const SizedBox(height: 8),
              FFAlert(
                message: context
                    .tr('upgrade.late')
                    .replaceFirst('{days}', '${daysLeft < 0 ? 0 : daysLeft}'),
                tone: FFAlertTone.warning,
              ),
            ],
            if (_modes.manual != null && chosen != null) ...[
              const SizedBox(height: 16),
              ManualPaymentFields(
                key: const Key('upgrade-manual-pay'),
                manual: _modes.manual!,
                amountLabel: formatCurrency(
                  ((chosen['differenceTzs'] as num?) ?? 0).toInt(),
                ),
                input: _manualInput,
                enabled: !_sending,
                upgrade: true,
                onChanged: (_) {
                  if (_manualInput.clearErrors()) setState(() {});
                },
              ),
            ],
            const SizedBox(height: 16),
            // Nothing to submit until a plan is picked: say so instead of
            // showing a button that does nothing (L3).
            if (chosen == null)
              Text(
                context.tr('member.chooseFirst'),
                key: const Key('upgrade-choose-first'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              FFButton(
                key: const Key('upgrade-submit'),
                label: _modes.manual != null
                    ? context.tr('manualPay.submit')
                    : context
                          .tr('upgrade.pay')
                          .replaceFirst(
                            '{amount}',
                            formatCurrency(
                              ((chosen['differenceTzs'] as num?) ?? 0).toInt(),
                            ),
                          ),
                onPressed: _sending ? null : _submit,
                loading: _sending,
              ),
          ],
        );
      },
    );
  }
}

class _PendingBlockCard extends StatelessWidget {
  const _PendingBlockCard({required this.pending});

  final PaymentRequest pending;

  void _openSupport() {
    launchUrl(
      Uri.parse('https://wa.me/255786670499'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FFToneTheme.of(context).warning.bg,
                  border: Border.all(
                    color: FFToneTheme.of(context).warning.border,
                  ),
                  borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                ),
                child: Icon(
                  Icons.hourglass_top_rounded,
                  color: FFToneTheme.of(context).warning.fg,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The title says it is waiting; the badge and status row
                    // that repeated it are gone (owner: say a fact once).
                    Text(
                      context.tr('member.paymentPendingTitle'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('member.paymentPendingBody'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 12),
          _DetailRow(
            label: context.tr('member.paymentPendingPlan'),
            value: paymentProductLabel(context, pending),
          ),
          _DetailRow(
            label: context.tr('member.paymentPendingAmount'),
            value: formatCurrency(pending.amountTzs),
          ),
          if (pending.memberReference case final ref?)
            _DetailRow(
              key: const Key('pending-transaction-id'),
              label: context.tr('manualPay.idLabel'),
              value: ref,
            ),
          if (pending.payerPhone case final phone?)
            _DetailRow(
              key: const Key('pending-payer-phone'),
              label: context.tr('manualPay.paidFrom'),
              value: phone,
            ),
          const SizedBox(height: 16),
          PayNowButton(request: pending),
          SizedBox(
            width: double.infinity,
            child: FFButton(
              label: context.tr('member.contactSupport'),
              onPressed: _openSupport,
              variant: FFButtonVariant.secondary,
              icon: Icons.support_agent,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SelectablePass extends StatelessWidget {
  const _SelectablePass({
    required this.pass,
    required this.selected,
    required this.onTap,
    this.gyms = const [],
  });

  final PassTier pass;
  final bool selected;
  final VoidCallback onTap;
  final List<Gym> gyms;

  @override
  Widget build(BuildContext context) {
    final accessibleGyms = gymsForPass(pass.gymAccess, gyms);
    final gymCount = accessibleGyms.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: AnimatedContainer(
          duration: FFTokens.motionFast,
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(FFTokens.radiusXl),
            boxShadow: selected ? FFTokens.shadowXs : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('pass.${pass.id}'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pass.visitCap == null
                          ? context.tr('pass.unlimited')
                          : '${pass.visitCap} ${context.tr('pass.visits')}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (pass.gymAccess != null && pass.gymAccess!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        // Wraps: at 360 wide Premium's "Standard + Mid-tier
                        // + Premium gyms" is the point of the card, so it is
                        // never cut.
                        child: Text(
                          passGymAccessLabel(context, pass.gymAccess),
                          key: Key('pass-gym-access-${pass.id}'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                    if (gymCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '$gymCount ${gymCount == 1 ? context.tr('gym.gym') : context.tr('gym.gyms')} · ${gymSplitSummary(context, accessibleGyms)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    if (gyms.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          // 48dp, also on the web.
                          minimumSize: const Size(48, 48),
                          tapTargetSize: MaterialTapTargetSize.padded,
                          visualDensity: VisualDensity.standard,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: () => showPassGymsSheet(
                          context,
                          tierId: pass.id,
                          gymAccess: pass.gymAccess,
                          gyms: gyms,
                          onChoose: onTap,
                        ),
                        icon: const Icon(Icons.fitness_center, size: 16),
                        label: Text(context.tr('passGyms.view')),
                      ),
                  ],
                ),
              ),
              Text(
                formatCurrency(pass.price),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The Upgrade plan page under PHOTO_HERO_UI: the page, its scroll view and,
/// with PHOTO_FOOTER_UI, the photo footer: shown when [footerEnabled], or in
/// upgrade mode ([gated]) once the upgrade gate says it may.
class _PassesScroll extends StatefulWidget {
  const _PassesScroll({
    required this.appBar,
    required this.children,
    required this.footerEnabled,
    required this.gated,
  });

  final PreferredSizeWidget appBar;
  final List<Widget> Function(ValueChanged<bool> onGateReady) children;
  final bool footerEnabled;
  final bool gated;

  @override
  State<_PassesScroll> createState() => _PassesScrollState();
}

class _PassesScrollState extends State<_PassesScroll> {
  bool _gateReady = false;

  void _onGateReady(bool ready) {
    if (mounted && ready != _gateReady) setState(() => _gateReady = ready);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar,
      body: footerListView(
        key: const Key('passes-scroll'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        footer: photoFooterUi
            ? FFPhotoFooter.sliver(
                key: const Key('passes-footer'),
                pageKey: 'member.passes',
                top: FFHeroPhoto.upgrade,
                enabled: widget.gated ? _gateReady : widget.footerEnabled,
                gap: FFTokens.spacingXl - FFTokens.spacingLg,
              )
            : null,
        children: widget.children(_onGateReady),
      ),
    );
  }
}
