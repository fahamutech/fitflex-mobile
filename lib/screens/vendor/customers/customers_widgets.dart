// Vendor tools · S4: pieces the customer screens share — routes, the gate
// every customer route passes (flag + `customers`), the in-memory
// CustomerRepository, badges and the aging tiles. Built only from the
// shared FF* components.
//
// A-02 / spec §8: customer data is never written to the device. The
// repository keeps names in memory only, per API client and signed-in
// session, and is cleared on sign-out.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_options.dart';
import 'customer_models.dart';

const customersHomeRoute = '/vendor/home?open=customers';
const owedHomeRoute = '/vendor/home?open=customers&view=owed';
const newCustomerRoute = '/vendor/customers/new';
String customerRoute(String id) =>
    '/vendor/customers/${Uri.encodeComponent(id)}';
String editCustomerRoute(String id) => '${customerRoute(id)}/edit';
String statementRoute(String id) => '${customerRoute(id)}/statement';

/// A sale seen from its customer's profile: read-only for people with
/// `customers` only (GET /vendor/customers/:id/sales/:saleId).
String customerSaleRoute(String id, String saleId) =>
    '${customerRoute(id)}/sales/${Uri.encodeComponent(saleId)}';

/// Ids in customer addresses: the characters the server issues.
final customerIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,100}$');

/// Checks a customer route may open: `tools.customers` is on and this
/// person has `customers`. Otherwise leaves (no message when the feature is
/// off; "no access" without the permission) and answers null.
Future<VendorTools?> enterCustomersRoute(BuildContext context) async {
  final tools = await VendorToolsOptions.of(context);
  if (!context.mounted) return null;
  if (!tools.customers) {
    context.go('/vendor/home');
    return null;
  }
  if (!canVendor(context, 'customers')) {
    FFSnack.error(context, context.tr('vendor.customers.noAccess'));
    context.go('/vendor/home');
    return null;
  }
  return tools;
}

class _Names {
  _Names(this.token);
  final String? token;
  final Map<String, String> names = {};
}

/// Customer names seen this session, in memory only (spec §0.3, §8). The
/// POS draft keeps a customer's id; its name comes from here, or from the
/// server, when the cart reopens.
class CustomerRepository {
  CustomerRepository._();

  static final Expando<_Names> _cache = Expando<_Names>('vendorCustomers');

  static _Names _of(ApiClient api, String? token) {
    final hit = _cache[api];
    if (hit != null && hit.token == token) return hit;
    return _cache[api] = _Names(token);
  }

  static void remember(BuildContext context, String id, String name) {
    final scope = AppScope.of(context);
    _of(scope.api, scope.auth.token).names[id] = name;
  }

  static String? nameOf(BuildContext context, String id) {
    final scope = AppScope.of(context);
    return _of(scope.api, scope.auth.token).names[id];
  }

  /// Sign-out (and tests): forget every name.
  static void clear(ApiClient api) => _cache[api] = null;

  /// The name of [id]: memory first, then the profile (needs `customers`).
  /// Null when it cannot be known (offline, or `sales` only).
  static Future<String?> fetchName(BuildContext context, String id) async {
    final known = nameOf(context, id);
    if (known != null) return known;
    if (!canVendor(context, 'customers')) return null;
    try {
      final res = await AppScope.of(context).api.vendorCustomer(id);
      final c = res['customer'];
      if (c is! Map || !context.mounted) return null;
      final name = customerDisplayName(c, context.tr);
      remember(context, id, name);
      return name;
    } catch (_) {
      return null;
    }
  }
}

/// "App customer" / "Shop customer".
Widget customerSourceBadge(BuildContext context, Map c) => FFBadge(
  label: context.tr(
    c['source'] == 'marketplace'
        ? 'vendor.customers.badge.app'
        : 'vendor.customers.badge.shop',
  ),
  tone: FFBadgeTone.defaultTone,
  wrap: true,
);

Widget overdueBadge(BuildContext context, {String? label}) => FFBadge(
  label: label ?? context.tr('vendor.customers.overdueBadge'),
  tone: FFBadgeTone.warning,
  wrap: true,
);

int intOf(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// What an API failure means for a customer screen.
enum CustomerLoadProblem { none, failed, network, notFound, noAccess }

CustomerLoadProblem problemOf(Object e) {
  if (e is ApiException) {
    if (e.status == 404) return CustomerLoadProblem.notFound;
    if (e.status == 403) return CustomerLoadProblem.noAccess;
    return CustomerLoadProblem.failed;
  }
  return CustomerLoadProblem.network;
}

/// The error state for a failed customer load.
Widget customerErrorState(
  BuildContext context,
  CustomerLoadProblem problem, {
  required String failedKey,
  VoidCallback? onRetry,
  Key? key,
}) => FFErrorState(
  key: key,
  message: context.tr(switch (problem) {
    CustomerLoadProblem.network => 'error.network',
    CustomerLoadProblem.noAccess => 'vendor.customers.noAccess',
    CustomerLoadProblem.notFound => 'vendor.customers.notFound',
    _ => failedKey,
  }),
  onRetry: problem == CustomerLoadProblem.notFound ? null : onRetry,
);

/// "Too many changes at once" for 429 rate_limited.
bool isRateLimited(Object e) => e is ApiException && e.status == 429;

/// Five aging tiles (Not due yet … Over 90 days): 3 + 2 on a phone, five
/// in a row from 900 wide, two per row at large text. Zero tiles stay,
/// muted, so the positions never move. With [onSelect] each tile is a
/// filter toggle.
class AgingTiles extends StatelessWidget {
  const AgingTiles({
    super.key,
    required this.aging,
    this.selected,
    this.onSelect,
    this.keyPrefix = 'aging',
  });

  final Map aging;
  final String? selected;
  final ValueChanged<String>? onSelect;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final perRow = box.maxWidth >= 900 ? 5 : (big ? 2 : 3);
        const gap = FFTokens.spacingSm;
        final w = (box.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final b in agingBuckets)
              SizedBox(
                width: w,
                child: _tile(context, theme, b, intOf(aging[b])),
              ),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, ThemeData theme, String b, int amount) {
    final label = context.tr('vendor.aging.$b');
    final value = formatCurrency(amount);
    final isSelected = selected == b;
    final tile = Opacity(
      opacity: amount == 0 ? 0.6 : 1,
      child: FFStatTile(
        icon: b == 'current' ? Icons.schedule : Icons.warning_amber_outlined,
        value: value,
        label: label,
        fitValue: true,
      ),
    );
    if (onSelect == null) {
      return Semantics(
        key: Key('$keyPrefix-$b'),
        container: true,
        label: '$label, $value',
        excludeSemantics: true,
        child: tile,
      );
    }
    return Semantics(
      key: Key('$keyPrefix-$b'),
      button: true,
      selected: isSelected,
      label: '$label, $value',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          side: BorderSide(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          onTap: () => onSelect!(b),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: tile,
          ),
        ),
      ),
    );
  }
}

/// The plain text of a document is shared through the system share sheet
/// (spec §7). Replaceable in tests.
typedef ShareCustomerText = Future<void> Function(String text, String subject);
