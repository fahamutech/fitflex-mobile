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

/// 429 rate_limited.
bool isRateLimited(Object e) => e is ApiException && e.status == 429;

/// "Too many tries. Wait {n} seconds." from the server's retryAfterSeconds.
String rateLimitedText(BuildContext context, Object e) {
  final body = e is ApiException && e.body is Map ? e.body as Map : const {};
  final n = intOf(body['retryAfterSeconds']);
  return fillIn(context.tr('vendor.customers.rateLimited'), {
    'n': n > 0 ? n : 60,
  });
}

/// An aging bucket's label for a tile: a day range never breaks inside
/// the numbers ("1–30", word joiners around the dash) or between a word and
/// the number after it ("Siku 1–30", "siku 90": non-breaking space). Other
/// spaces wrap as usual, so "Bado muda haujafika" and "Zaidi ya siku 90"
/// still fit a narrow tile at large text.
String agingTileLabel(String bucket, String label) {
  if (bucket == 'current') return label;
  return label
      .replaceAll(RegExp(r' (?=\d)'), '\u00A0')
      .replaceAll('–', '\u2060–\u2060');
}

/// How many aging tiles share a row: five from 900 wide; two when narrow
/// (under 300) or at large text; else three (spec §5.1: 3 + 2 at 375).
int agingTilesPerRow(double width, double textScale) {
  if (width >= 900) return 5;
  if (width < 300 || textScale > 1.3) return 2;
  return 3;
}

/// Five aging tiles (Not due yet … Over 90 days). Zero tiles stay, muted,
/// so the positions never move. With [onSelect] each tile is a filter
/// toggle that says whether it is selected.
///
/// UAT D2: labels wrap and are never cut; every amount has the same size
/// (it wraps between "TSh" and the figure if it must, never shrinks).
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
    return LayoutBuilder(
      builder: (context, box) {
        final perRow = agingTilesPerRow(
          box.maxWidth,
          MediaQuery.textScalerOf(context).scale(1),
        );
        // Very narrow (a 320 phone at large text): a tighter gap and side
        // padding so "Siku 1–30" still fits on one line.
        final tight = box.maxWidth < 300;
        final gap = tight ? FFTokens.spacingXs : FFTokens.spacingSm;
        final w = (box.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: FFTokens.spacingSm,
          children: [
            for (final b in agingBuckets)
              SizedBox(
                width: w,
                child: _tile(context, b, intOf(aging[b]), tight: tight),
              ),
          ],
        );
      },
    );
  }

  Widget _tile(
    BuildContext context,
    String b,
    int amount, {
    bool tight = false,
  }) {
    final theme = Theme.of(context);
    final label = context.tr('vendor.aging.$b');
    final value = formatCurrency(amount);
    final isSelected = selected == b;
    final muted = amount == 0;
    final fg = muted
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    final body = Container(
      padding: EdgeInsets.symmetric(
        horizontal: tight ? FFTokens.spacingXs : FFTokens.spacingSm,
        vertical: FFTokens.spacingSm,
      ),
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            key: Key('$keyPrefix-$b-amount'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: FFTokens.spacing2xs),
          Text(
            agingTileLabel(b, label),
            key: Key('$keyPrefix-$b-label'),
            style: theme.textTheme.bodySmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
    if (onSelect == null) {
      return Semantics(
        key: Key('$keyPrefix-$b'),
        container: true,
        label: '$label, $value',
        excludeSemantics: true,
        child: body,
      );
    }
    return Semantics(
      key: Key('$keyPrefix-$b'),
      container: true,
      button: true,
      selected: isSelected,
      label: '$label, $value',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          onTap: () => onSelect!(b),
          child: body,
        ),
      ),
    );
  }
}

/// The plain text of a document is shared through the system share sheet
/// (spec §7). Replaceable in tests.
typedef ShareCustomerText = Future<void> Function(String text, String subject);
