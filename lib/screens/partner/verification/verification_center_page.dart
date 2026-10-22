// Verification centre — where gym owners, trainers and vendors complete their
// KYC / KYB: what's done and what's missing, forms for each item, and
// submitting for review. Reachable while a partner is still pending approval.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/partner_progress.dart';
import '../../../shared/widgets/partner_progress_tracker.dart';
import '../../member/widgets/gym_filters.dart' show tierKeyOf, tierLabel;
import 'verification_forms.dart';
import 'partner_progress_actions.dart' show openPartnerSupport;
import 'verification_models.dart';
import 'verification_repository.dart';

class VerificationCenterPage extends StatefulWidget {
  const VerificationCenterPage({
    super.key,
    this.repository,
    this.pickDocument,
    this.openItem,
  });

  /// A checklist item to open once the centre has loaded (a next action on
  /// the partner progress tracker that names it).
  final PartnerItemRef? openItem;

  /// Injectable for tests; defaults to the app's API.
  final VerificationRepository? repository;

  /// Injectable for tests; defaults to the camera, gallery and file pickers.
  final PickDocument? pickDocument;

  @override
  State<VerificationCenterPage> createState() => _VerificationCenterPageState();
}

class _VerificationCenterPageState extends State<VerificationCenterPage> {
  VerificationRepository? _repo;
  KycOverview? _data;
  Object? _error;
  bool _busy = false;
  bool _openedItem = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo =
          widget.repository ?? VerificationRepository(AppScope.of(context).api);
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await _repo!.overview();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
        _openRequestedItem(data);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Opens [VerificationCenterPage.openItem] once, after the first load.
  void _openRequestedItem(KycOverview data) {
    final ref = widget.openItem;
    if (ref == null || _openedItem) return;
    _openedItem = true;
    final item = _itemFor(data, ref);
    if (item == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(item);
    });
  }

  KycItem? _itemFor(KycOverview data, PartnerItemRef ref) {
    for (final section in data.sections) {
      for (final item in section.items) {
        if (item.key == ref.key &&
            (ref.gymId == null || item.gymId == ref.gymId)) {
          return item;
        }
      }
    }
    return null;
  }

  KycItem? _payoutItem(KycOverview data) {
    for (final section in data.sections) {
      for (final item in section.items) {
        if (item.key == 'settlement.payout_account' ||
            item.key == 'marketplace.settlement') {
          return item;
        }
      }
    }
    return null;
  }

  /// A next action on the tracker, followed inside the centre.
  Future<void> _progressAction(PartnerNextAction action) async {
    final data = _data;
    if (data == null) return;
    switch (action.code) {
      case 'complete_kyc_items' || 'kyc_changes_requested':
        final item = action.missing.isEmpty
            ? null
            : _itemFor(data, action.missing.first);
        if (item != null) await _open(item);
      case 'submit_kyc':
        if (data.readyToSubmit) await _confirmSubmit();
      case 'add_payout_account':
        final item = _payoutItem(data);
        if (item != null) {
          await _open(item);
        } else {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  PayoutAccountsPage(repository: _repo!, overview: data),
            ),
          );
          await _load();
        }
      case 'add_gym':
        context.go(AppRoutes.ownerGyms);
      case 'contact_support' || 'payout_not_ready':
        await openPartnerSupport();
    }
  }

  // Replace any message still showing rather than queueing behind it.
  void _show(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(
    Future<KycOverview> Function() action, {
    String? done,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await action();
      if (!mounted) return;
      setState(() => _data = data);
      if (done != null) _show(context.tr(done));
    } catch (e) {
      if (mounted) _show(_message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object e) {
    if (e is ApiException && e.code == 'kyc_incomplete') {
      return context.tr('kyc.error.incomplete');
    }
    if (e is ApiException && e.code == 'case_locked') {
      return context.tr('kyc.locked');
    }
    return errorMessage(FFLocaleScope.of(context), e);
  }

  Future<void> _confirmSubmit() async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('kyc.submit.title'),
      message: context.tr('kyc.submit.body'),
      cancelLabel: context.tr('kyc.cancel'),
      confirmLabel: context.tr('kyc.submit.action'),
      confirmKey: const Key('kyc-submit-confirm'),
    );
    if (ok == true) await _run(() => _repo!.submit(), done: 'kyc.submit.done');
  }

  Future<void> _open(KycItem item) async {
    final data = _data!;
    if (item.byReviewer) return _show(context.tr('kyc.hint.reviewer'));

    final isAccount =
        item.key == 'settlement.payout_account' ||
        item.key == 'marketplace.settlement';
    if (isAccount) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PayoutAccountsPage(repository: _repo!, overview: data),
        ),
      );
      return _load();
    }

    // Agreements can be read and accepted at any stage, even once submitted.
    final agreementType = KycAgreement.typeForItem(item.key);
    if (agreementType != null) {
      final updated = await Navigator.of(context).push<KycOverview>(
        MaterialPageRoute(
          builder: (_) =>
              AgreementPage(repository: _repo!, agreementType: agreementType),
        ),
      );
      if (mounted && updated != null) setState(() => _data = updated);
      return;
    }

    final external = _externalHint(item);
    if (external == 'kyc.hint.vendorProfile' && _isVendor()) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => VendorKycProfilePage(api: _vendorApi()!),
        ),
      );
      if (saved == true) await _load();
      return;
    }
    if (external != null) return _show(context.tr(external));
    final canEdit = item.requirementKey != null
        ? data.documentsEditable
        : data.editable;
    if (!canEdit) {
      return _show(
        context.tr(data.status.renewable ? 'kyc.lockedApproved' : 'kyc.locked'),
      );
    }

    Widget? page;
    if (item.requirementKey != null) {
      page = DocumentPage(
        repository: _repo!,
        overview: data,
        requirementKey: item.requirementKey!,
        pickDocument: widget.pickDocument ?? pickDocumentFromDevice,
      );
    } else if (item.section == 'identity' || item.section == 'representative') {
      page = PersonFormPage(repository: _repo!, overview: data);
    } else if (item.section == 'business' || item.section == 'company') {
      page = BusinessFormPage(repository: _repo!, overview: data);
    }
    if (page == null) return;
    final updated = await Navigator.of(
      context,
    ).push<KycOverview>(MaterialPageRoute(builder: (_) => page!));
    if (!mounted) return;
    // A document's file may have been uploaded even if its details weren't saved.
    if (updated != null) {
      setState(() => _data = updated);
    } else {
      await _load();
    }
  }

  bool _isVendor() =>
      _vendorApi() != null &&
      context
              .getInheritedWidgetOfExactType<AppScope>()
              ?.auth
              .user?['userType'] ==
          'vendor';

  ApiClient? _vendorApi() =>
      context.getInheritedWidgetOfExactType<AppScope>()?.api;

  /// Items kept on records the partner edits elsewhere in the app.
  String? _externalHint(KycItem item) => switch (item.key) {
    'operational.gym_profile' ||
    'operational.rate_card' ||
    'business.gym_location' => 'kyc.hint.gym',
    'professional.specialisation' => 'kyc.hint.specialisation',
    'business.contact' ||
    'marketplace.product_categories' ||
    'marketplace.delivery' ||
    'marketplace.returns' => 'kyc.hint.vendorProfile',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('kyc.title'))),
      body: data == null
          ? (_error != null
                ? FFEmptyState(
                    title: errorMessage(FFLocaleScope.of(context), _error!),
                    action: FFButton(
                      label: context.tr('kyc.retry'),
                      onPressed: _load,
                    ),
                  )
                : const Center(child: FFSpinner(size: 32)))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: const Key('kyc-center'),
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  if (data.progress != null) ...[
                    PartnerProgressTracker(
                      progress: data.progress!,
                      busy: _busy,
                      onAction: _progressAction,
                    ),
                    const SizedBox(height: FFTokens.spacingMd),
                  ],
                  if (_StatusCard.shows(data)) ...[
                    _StatusCard(data: data),
                    const SizedBox(height: FFTokens.spacingLg),
                  ],
                  for (final section in data.sections) ...[
                    FFSectionTitle(
                      context.tr(
                        // A vendor's person is the vendor themselves.
                        data.partnerType == 'vendor' &&
                                section.key == 'representative'
                            ? 'kyc.section.yourDetails'
                            : 'kyc.section.${section.key}',
                      ),
                    ),
                    FFCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final item in section.items)
                            _ItemTile(
                              item: item,
                              inspection: data.inspectionFor(item),
                              onTap: _busy ? null : () => _open(item),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacingLg),
                  ],
                  Text(
                    context.tr('kyc.privacy'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 96),
                ],
              ),
            ),
      bottomNavigationBar: data == null ? null : _actions(data),
    );
  }

  Widget? _actions(KycOverview data) {
    Widget? button;
    if (data.editable) {
      button = FFButton(
        key: const Key('kyc-submit'),
        label: data.readyToSubmit
            ? context.tr('kyc.submit.action')
            : context
                  .tr('kyc.itemsLeft')
                  .replaceFirst('{n}', '${data.itemsLeft}'),
        onPressed: _busy || !data.readyToSubmit ? null : _confirmSubmit,
      );
    } else if (data.status == KycStatus.submitted) {
      button = FFButton(
        key: const Key('kyc-withdraw'),
        label: context.tr('kyc.withdraw.action'),
        onPressed: _busy
            ? null
            : () => _run(() => _repo!.withdraw(), done: 'kyc.withdraw.done'),
        variant: FFButtonVariant.secondary,
      );
    }
    if (button == null) return null;
    return SafeArea(
      minimum: const EdgeInsets.all(FFTokens.spacingLg),
      child: SizedBox(width: double.infinity, child: button),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.data});
  final KycOverview data;

  /// With the progress tracker on top, the status sentence is said there;
  /// only the reviewer's note and the renewal hint are left to show.
  static bool shows(KycOverview data) {
    if (data.progress == null) return true;
    final note = data.kycCase?.reasonNote;
    return (note != null && note.isNotEmpty) || data.status.renewable;
  }

  @override
  Widget build(BuildContext context) {
    final c = data.kycCase;
    final (String key, FFAlertTone tone) = switch (data.status) {
      KycStatus.none ||
      KycStatus.draft => ('kyc.status.draft', FFAlertTone.info),
      KycStatus.submitted => ('kyc.status.submitted', FFAlertTone.info),
      KycStatus.inReview => ('kyc.status.inReview', FFAlertTone.info),
      KycStatus.infoRequested => (
        'kyc.status.infoRequested',
        FFAlertTone.warning,
      ),
      KycStatus.approved => ('kyc.status.approved', FFAlertTone.success),
      KycStatus.rejected => ('kyc.status.rejected', FFAlertTone.error),
      KycStatus.suspended => ('kyc.status.suspended', FFAlertTone.error),
    };
    final note = c?.reasonNote;
    final message = [
      if (data.progress == null) context.tr(key),
      if (note != null && note.isNotEmpty) note,
      if (data.status.renewable) context.tr('kyc.renewHint'),
    ].join('\n\n');
    return FFAlert(key: const Key('kyc-status'), message: message, tone: tone);
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap, this.inspection});
  final KycItem item;
  final VoidCallback? onTap;
  final KycInspection? inspection;

  static String _number(num n) =>
      n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(1);

  /// "42 / 50 · Premium tier · Visited 12 Oct 2026"; parts not sent are left
  /// out, so a missing maximum never reads "0 / 0".
  static String? inspectionLine(BuildContext context, KycInspection? i) {
    if (i == null) return null;
    final max = i.maxScore;
    final date = i.visitedOn == null
        ? ''
        : context.localDate(i.visitedOn, fallback: '');
    return [
      max != null && max > 0
          ? context
                .tr('kyc.inspection.score')
                .replaceFirst('{score}', _number(i.score))
                .replaceFirst('{max}', _number(max))
          : _number(i.score),
      if (i.vettedTier != null)
        context
            .tr('kyc.inspection.tier')
            .replaceFirst(
              '{tier}',
              tierLabel(context, tierKeyOf(i.vettedTier)),
            ),
      if (date.isNotEmpty)
        context.tr('kyc.inspection.visitedOn').replaceFirst('{date}', date),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final label = context.tr('kyc.item.${item.field}');
    final (String statusKey, FFBadgeTone tone) = switch (item.status) {
      'complete' => ('kyc.itemStatus.complete', FFBadgeTone.success),
      'submitted' => ('kyc.itemStatus.submitted', FFBadgeTone.brand),
      'incomplete' => ('kyc.itemStatus.incomplete', FFBadgeTone.warning),
      'file_missing' => ('kyc.itemStatus.fileMissing', FFBadgeTone.warning),
      'rejected' => ('kyc.itemStatus.rejected', FFBadgeTone.danger),
      'expired' => ('kyc.itemStatus.expired', FFBadgeTone.danger),
      'failed' => ('kyc.itemStatus.failed', FFBadgeTone.danger),
      'mismatch' => ('kyc.itemStatus.mismatch', FFBadgeTone.warning),
      _ => ('kyc.itemStatus.missing', FFBadgeTone.gray),
    };
    final subtitle = [
      if (item.gymName != null) item.gymName!,
      if (item.byReviewer) context.tr('kyc.byFitflex'),
      if (item.note != null && item.note!.isNotEmpty) item.note!,
    ].join(' · ');
    final inspected = inspectionLine(context, inspection);
    final suffix = item.gymId == null ? '' : '-${item.gymId}';
    return ListTile(
      key: Key('kyc-item-${item.key}$suffix'),
      title: Text(label),
      subtitle: subtitle.isEmpty && inspected == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle.isNotEmpty) Text(subtitle),
                if (inspected != null)
                  Text(
                    inspected,
                    key: Key('kyc-inspection$suffix'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
              ],
            ),
      trailing: item.optional && !item.done
          ? FFBadge(
              label: context.tr('kyc.itemStatus.optional'),
              tone: FFBadgeTone.gray,
            )
          : FFBadge(label: context.tr(statusKey), tone: tone),
      onTap: onTap,
    );
  }
}
