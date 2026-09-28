// Verification centre — where gym owners, trainers and vendors complete their
// KYC / KYB: what's done and what's missing, forms for each item, and
// submitting for review. Reachable while a partner is still pending approval.

import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'verification_forms.dart';
import 'verification_models.dart';
import 'verification_repository.dart';

class VerificationCenterPage extends StatefulWidget {
  const VerificationCenterPage({super.key, this.repository, this.pickDocument});

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
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('kyc.submit.title')),
        content: Text(ctx.tr('kyc.submit.body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('kyc.cancel')),
          ),
          FilledButton(
            key: const Key('kyc-submit-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('kyc.submit.action')),
          ),
        ],
      ),
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

    final external = _externalHint(item);
    if (external != null) return _show(context.tr(external));
    if (!data.editable) return _show(context.tr('kyc.locked'));

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
                    action: FilledButton(
                      onPressed: _load,
                      child: Text(context.tr('kyc.retry')),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: const Key('kyc-center'),
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  _StatusCard(data: data),
                  const SizedBox(height: FFTokens.spacingLg),
                  for (final section in data.sections) ...[
                    FFSectionTitle(context.tr('kyc.section.${section.key}')),
                    FFCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final item in section.items)
                            _ItemTile(
                              item: item,
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
      button = FilledButton(
        key: const Key('kyc-submit'),
        onPressed: _busy || !data.readyToSubmit ? null : _confirmSubmit,
        child: Text(
          data.readyToSubmit
              ? context.tr('kyc.submit.action')
              : context
                    .tr('kyc.itemsLeft')
                    .replaceFirst('{n}', '${data.itemsLeft}'),
        ),
      );
    } else if (data.status == KycStatus.submitted) {
      button = OutlinedButton(
        key: const Key('kyc-withdraw'),
        onPressed: _busy
            ? null
            : () => _run(() => _repo!.withdraw(), done: 'kyc.withdraw.done'),
        child: Text(context.tr('kyc.withdraw.action')),
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
      context.tr(key),
      if (note != null && note.isNotEmpty) note,
    ].join('\n\n');
    return FFAlert(key: const Key('kyc-status'), message: message, tone: tone);
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap});
  final KycItem item;
  final VoidCallback? onTap;

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
    return ListTile(
      key: Key(
        'kyc-item-${item.key}${item.gymId == null ? '' : '-${item.gymId}'}',
      ),
      title: Text(label),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: FFBadge(label: context.tr(statusKey), tone: tone),
      onTap: onTap,
    );
  }
}
