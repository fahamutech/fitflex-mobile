// Partner progress (B4b): where a next action leads from outside the
// Verification centre (the pending screen, vendor home), and the compact
// banner vendor home shows while the partner is not finished.
//
// No routes are added: the Verification centre and the payout account
// screen are pushed as pages, as the centre itself already does.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/partner_progress.dart';
import '../../../shared/widgets/partner_progress_tracker.dart';
import 'verification_center_page.dart';
import 'verification_forms.dart';
import 'verification_models.dart';
import 'verification_repository.dart';

/// FitFlex support on WhatsApp, the same number the profile pages open.
const partnerSupportUrl = 'https://wa.me/255786670499';

Future<void> openPartnerSupport() async {
  await launchUrl(
    Uri.parse(partnerSupportUrl),
    mode: LaunchMode.externalApplication,
  );
}

/// Follows [action] from a screen other than the Verification centre.
/// Completes when the partner comes back, so the caller can reload.
Future<void> runPartnerAction(
  BuildContext context,
  PartnerNextAction action, {
  required VerificationRepository repository,
  required KycOverview overview,
}) async {
  final nav = Navigator.of(context);
  switch (action.code) {
    case 'complete_kyc_items' || 'kyc_changes_requested' || 'submit_kyc':
      await nav.push<void>(
        MaterialPageRoute(
          builder: (_) => VerificationCenterPage(
            repository: repository,
            openItem: action.missing.isEmpty ? null : action.missing.first,
          ),
        ),
      );
    case 'add_payout_account':
      await nav.push<void>(
        MaterialPageRoute(
          builder: (_) =>
              PayoutAccountsPage(repository: repository, overview: overview),
        ),
      );
    case 'add_gym':
      context.go(AppRoutes.ownerGyms);
    case 'contact_support' || 'payout_not_ready':
      await openPartnerSupport();
  }
}

/// Vendor home's banner: the compact tracker while the vendor is not
/// finished. Without a `progress` block (server flag off) or if it can't be
/// loaded, [fallback] shows instead, so the screen is what it was before.
class PartnerProgressBanner extends StatefulWidget {
  const PartnerProgressBanner({
    super.key,
    this.fallback,
    this.padding = EdgeInsets.zero,
    this.repository,
  });

  /// What showed here before (the pending banner), or nothing.
  final Widget? fallback;

  /// Around the tracker only; the fallback brings its own.
  final EdgeInsetsGeometry padding;

  /// Injectable for tests; defaults to the app's API.
  final VerificationRepository? repository;

  @override
  State<PartnerProgressBanner> createState() => _PartnerProgressBannerState();
}

class _PartnerProgressBannerState extends State<PartnerProgressBanner> {
  VerificationRepository? _repo;
  KycOverview? _overview;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo != null) return;
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    final repo =
        widget.repository ??
        (scope == null ? null : VerificationRepository(scope.api));
    if (repo == null) return;
    _repo = repo;
    // Only the vendor's own account has a verification; staff don't.
    if (widget.repository != null ||
        scope?.auth.user?['userType'] == 'vendor') {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await _repo!.overview();
      if (mounted) setState(() => _overview = data);
    } catch (_) {
      // The fallback stays.
    }
  }

  Future<void> _act(PartnerNextAction action) async {
    final overview = _overview;
    if (overview == null || _busy) return;
    setState(() => _busy = true);
    try {
      await runPartnerAction(
        context,
        action,
        repository: _repo!,
        overview: overview,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _overview?.progress;
    if (progress == null) return widget.fallback ?? const SizedBox.shrink();
    if (progress.finished) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: PartnerProgressTracker(
        progress: progress,
        compact: true,
        busy: _busy,
        onAction: _act,
      ),
    );
  }
}

/// Top-of-column padding the vendor home banner uses.
const partnerBannerPadding = EdgeInsets.fromLTRB(
  FFTokens.spacingLg,
  FFTokens.spacingMd,
  FFTokens.spacingLg,
  0,
);
