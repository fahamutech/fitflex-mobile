import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_options.dart';
import 'banner_form_page.dart';
import 'banner_models.dart';

/// The banner form at its own address: `/vendor/merch/banner/new`
/// (`?copy=<id>` for "Copy to new") and `/vendor/merch/banner/<id>/edit`.
/// It loads what the form needs (the tool switch, the vendor's banners for
/// the one being edited and the confirmation texts, products, the business
/// name), so a refresh brings the form back.
class VendorBannerFormRoute extends StatefulWidget {
  const VendorBannerFormRoute({
    super.key,
    this.bannerId,
    this.copyId,
    this.now,
  });

  final String? bannerId;
  final String? copyId;

  /// The clock (tests).
  final DateTime Function()? now;

  @override
  State<VendorBannerFormRoute> createState() => _VendorBannerFormRouteState();
}

class _VendorBannerFormRouteState extends State<VendorBannerFormRoute> {
  bool _loading = true;
  String? _blocked;
  Object? _error;
  VendorBanner? _banner;
  VendorBanner? _copy;
  List<Map<String, dynamic>> _products = const [];
  String _businessName = '';
  BannerConfirmation? _confirmation;

  String get _vendorId {
    final user = AppScope.of(context).auth.user ?? const <String, dynamic>{};
    final staff = user['userType'] == 'vendor_staff';
    return (staff ? user['vendorId'] : user['id'])?.toString() ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _blocked = null;
    });
    final scope = AppScope.of(context);
    final tools = await VendorToolsOptions.of(context);
    if (!mounted) return;
    String? blocked;
    if (tools.suspended) {
      blocked = 'merch.suspended';
    } else if (!tools.banners) {
      blocked = 'merch.unavailable';
    } else if (!canManageProducts(context)) {
      blocked = 'vendor.noAccess';
    } else if (scope.auth.isPendingApproval &&
        scope.auth.user?['userType'] == 'vendor') {
      blocked = 'merch.pendingTitle';
    }
    if (blocked != null) {
      setState(() {
        _blocked = blocked;
        _loading = false;
      });
      return;
    }
    try {
      final api = scope.api;
      final results = await Future.wait<Object?>([
        _allBanners(api),
        api.vendorProducts().catchError((Object _) => <dynamic>[]),
        api.vendorProfile().catchError((Object _) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final list = results[0] as Map<String, dynamic>;
      final banners = [
        for (final b in (list['items'] as List? ?? const []).whereType<Map>())
          VendorBanner.fromJson(Map<String, dynamic>.from(b)),
      ];
      VendorBanner? find(String? id) =>
          id == null ? null : banners.where((b) => b.id == id).firstOrNull;
      final vendor = list['vendor'] is Map ? list['vendor'] as Map : const {};
      setState(() {
        _banner = find(widget.bannerId);
        _copy = find(widget.copyId);
        _products = (results[1] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _businessName =
            (results[2] as Map)['businessName']?.toString().trim() ?? '';
        _confirmation = BannerConfirmation.fromJson(list['confirmation']);
        if (widget.bannerId != null && _banner == null) {
          _blocked = 'merch.notYours';
        } else if (vendor['canPropose'] == false) {
          _blocked = vendor['reason'] == 'vendor_suspended'
              ? 'merch.suspended'
              : 'merch.pendingTitle';
        } else if (_banner != null && !_banner!.canEdit) {
          _blocked = 'merch.notEditable';
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _blocked = e.code == 'feature_disabled' ? 'merch.unavailable' : null;
        _error = _blocked == null ? e : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  static Future<Map<String, dynamic>> _allBanners(ApiClient api) async {
    final first = await api.vendorShopBanners();
    final items = [...?(first['items'] as List?)];
    var cursor = first['nextCursor']?.toString();
    for (var page = 1; page < 20 && (cursor ?? '').isNotEmpty; page++) {
      final next = await api.vendorShopBanners(cursor: cursor);
      items.addAll((next['items'] as List?) ?? const []);
      final more = next['nextCursor']?.toString();
      if (more == cursor) break;
      cursor = more;
    }
    return {...first, 'items': items};
  }

  void _back() =>
      context.canPop() ? context.pop(false) : context.go(AppRoutes.vendorMerch);

  @override
  Widget build(BuildContext context) {
    if (!_loading && _blocked == null && _error == null) {
      return VendorBannerFormPage(
        banner: _banner,
        copyFrom: _copy,
        products: _products,
        vendorId: _vendorId,
        businessName: _businessName,
        confirmation: _confirmation,
        now: widget.now,
      );
    }
    final Widget body;
    if (_loading) {
      body = FFSkeletonList(
        key: const Key('merch-form-loading'),
        semanticLabel: context.tr('common.loading'),
      );
    } else if (_error != null) {
      final offline = isNetworkError(_error!);
      body = FFErrorState(
        key: const Key('merch-form-error'),
        icon: offline ? Icons.wifi_off : Icons.error_outline,
        title: context.tr(
          offline ? 'merch.offlineTitle' : 'merch.banners.error',
        ),
        onRetry: _load,
      );
    } else {
      body = FFEmptyState(
        key: const Key('merch-form-blocked'),
        icon: Icons.campaign_outlined,
        title: context.tr(_blocked!),
        action: FFButton(
          label: context.tr('merch.back'),
          variant: FFButtonVariant.secondary,
          visualDensity: VisualDensity.standard,
          onPressed: _back,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(
            widget.bannerId == null
                ? 'merch.banner.newTitle'
                : 'merch.banner.editTitle',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [body],
      ),
    );
  }
}
