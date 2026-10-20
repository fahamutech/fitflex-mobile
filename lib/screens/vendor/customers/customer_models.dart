// Vendor tools · S4 (customers, pay later, customer payments, owed/aging):
// the rules the screens share. Pure Dart (no widgets, storage or network),
// so the money maths is tested on its own.
//
// The client mirrors the server (fitflex-functions src/shared/vendor-customer.mjs,
// #224) to guide the vendor; the server recomputes and wins. Money is whole
// TZS. Dates are EAT calendar days (YYYY-MM-DD).
//
// A-02: nothing here keeps customer data anywhere but memory. The POS draft
// and the offline queue store a customer's opaque id only.
import 'dart:math';

import '../../../shared/formatters.dart';
import '../sales/sale_models.dart';

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? _str(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Server limits (vendor-customer.mjs).
const customerNameMin = 2;
const customerNameMax = 80;
const customerAddressMax = 200;
const customerNoteMax = 500;
const customerPaymentNoteMax = 200;
const receivedOnBackDays = 30;
const dueDateMaxDays = 365;
const defaultDueDays = 7;
const statementPaymentDays = 90;
const customersPageSize = 50;
const activityPageSize = 20;

/// Aging buckets, in the order the tiles show them.
const agingBuckets = ['current', 'd1_30', 'd31_60', 'd61_90', 'd90plus'];

/// Customer list filters and sorts (Customers segment).
const customerFilters = [
  'all',
  'owes',
  'overdue',
  'manual',
  'marketplace',
  'archived',
];
const customerSorts = ['name', 'owed', 'overdue', 'recent'];

/// What a staff member with `sales` only may ask the picker for.
const pickerFilters = {'all', 'manual', 'marketplace'};

/// The i18n key of a filter pill.
String customerFilterKey(String f) => switch (f) {
  'owes' => 'vendor.customers.filter.owe',
  'manual' => 'vendor.customers.filter.shop',
  'marketplace' => 'vendor.customers.filter.app',
  _ => 'vendor.customers.filter.$f',
};

/// Pay later needs the customers flag, walk-in sales, and BOTH `sales` and
/// `customers` (server: 403 credit_not_allowed otherwise).
bool payLaterAllowed({
  required bool customersFlag,
  required bool walkInSales,
  required bool canSales,
  required bool canCustomers,
}) => customersFlag && walkInSales && canSales && canCustomers;

/// A customer's name for display. An app buyer who deleted their FitFlex
/// account (`forgotten`) has no name: [t] gives "Deleted member".
///
/// Same rule as the portal: `forgotten: true` → "Deleted member"; no name
/// but not forgotten → "FitFlex member"; nothing known → "Customer".
String customerDisplayName(Map? c, String Function(String key) t) {
  if (c == null) return t('vendor.customers.unnamed');
  if (c['forgotten'] == true) return t('vendor.customers.deletedMember');
  return _str(c['name']) ?? t('vendor.orders.buyerUnnamed');
}

/// "•••• 234" from a full phone or `phoneLast3`. Null when there is none.
String? phoneEnding(Map c) {
  final last3 = _str(c['phoneLast3']);
  if (last3 != null) return '•••• $last3';
  final phone = _str(c['phone']);
  if (phone == null || phone.length < 3) return null;
  return '•••• ${phone.substring(phone.length - 3)}';
}

/// Tanzanian phone → +255XXXXXXXXX (mobile: 6… or 7… after the country
/// code), as the server stores it. Anything else → null.
String? normaliseTzPhone(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
  String? local;
  if (RegExp(r'^\+255\d{9}$').hasMatch(s)) {
    local = s.substring(4);
  } else if (RegExp(r'^255\d{9}$').hasMatch(s)) {
    local = s.substring(3);
  } else if (RegExp(r'^0\d{9}$').hasMatch(s)) {
    local = s.substring(1);
  } else if (RegExp(r'^\d{9}$').hasMatch(s)) {
    local = s;
  }
  return local != null && RegExp(r'^[67]\d{8}$').hasMatch(local)
      ? '+255$local'
      : null;
}

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
bool validEmail(String v) => v.length <= 254 && _email.hasMatch(v.trim());

/// A new idempotency key for a customer write (payment, quick-add).
String newCustomerClientRef(String prefix, [Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return '${prefix}_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

// ── dates (EAT calendar days) ─────────────────────────────────────────────

/// A YYYY-MM-DD as a UTC date, or null.
DateTime? parseDay(String? day) {
  if (day == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
    return null;
  }
  final d = DateTime.tryParse('${day}T00:00:00Z');
  return d == null || dayString(d) != day ? null : d;
}

String dayString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Today in East Africa as YYYY-MM-DD.
String eatTodayString([DateTime? now]) {
  final eat = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
  return dayString(DateTime.utc(eat.year, eat.month, eat.day));
}

String addDaysTo(String day, int n) =>
    dayString(parseDay(day)!.add(Duration(days: n)));

/// a − b in whole days.
int daysBetween(String a, String b) =>
    parseDay(a)!.difference(parseDay(b)!).inDays;

/// "27 Oct 2026" for an EAT day.
String formatDay(String? day, {String locale = 'en'}) {
  final d = parseDay(day);
  if (d == null) return '';
  return formatDate(DateTime(d.year, d.month, d.day), locale: locale);
}

/// Aging bucket of [daysOverdue] (server §10.2): ≤ 0 not due yet.
String agingBucketOf(int daysOverdue) {
  if (daysOverdue <= 0) return 'current';
  if (daysOverdue <= 30) return 'd1_30';
  if (daysOverdue <= 60) return 'd31_60';
  if (daysOverdue <= 90) return 'd61_90';
  return 'd90plus';
}

/// A pay-later due date: from the sale's EAT day up to 365 days later.
({String earliest, String latest}) dueDateRange(String saleDay) =>
    (earliest: saleDay, latest: addDaysTo(saleDay, dueDateMaxDays));

bool dueDateInRange(String due, String saleDay) {
  final r = dueDateRange(saleDay);
  return parseDay(due) != null &&
      due.compareTo(r.earliest) >= 0 &&
      due.compareTo(r.latest) <= 0;
}

/// Date received: today back to 30 days, never in the future.
({String earliest, String latest}) receivedOnRange(String today) =>
    (earliest: addDaysTo(today, -receivedOnBackDays), latest: today);

// ── open sales and allocation ─────────────────────────────────────────────

/// One open pay-later sale of a customer (profile `openSales`).
class OpenSale {
  const OpenSale({
    required this.id,
    required this.number,
    required this.balanceTzs,
    this.totalTzs = 0,
    this.dueDate,
    this.soldAt,
    this.daysOverdue = 0,
    this.overdue = false,
  });

  final String id;
  final String number;
  final int balanceTzs;
  final int totalTzs;
  final String? dueDate;
  final String? soldAt;
  final int daysOverdue;
  final bool overdue;

  static OpenSale? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _str(raw['id']);
    if (id == null) return null;
    return OpenSale(
      id: id,
      number: _str(raw['number']) ?? '',
      balanceTzs: _int(raw['balanceTzs']),
      totalTzs: _int(raw['totalTzs']),
      dueDate: _str(raw['dueDate']),
      soldAt: _str(raw['soldAt']),
      daysOverdue: _int(raw['daysOverdue']),
      overdue: raw['overdue'] == true || _int(raw['daysOverdue']) > 0,
    );
  }
}

/// The profile's open sales, oldest due first (dueDate, soldAt, id), the
/// order the server pays them in. Sales with nothing left are dropped.
List<OpenSale> openSalesOf(Map? customer) {
  final rows = [
    for (final r in (customer?['openSales'] as List? ?? []))
      ?OpenSale.fromJson(r),
  ].where((s) => s.balanceTzs > 0).toList();
  rows.sort((a, b) {
    final d = (a.dueDate ?? '').compareTo(b.dueDate ?? '');
    if (d != 0) return d;
    final s = (a.soldAt ?? '').compareTo(b.soldAt ?? '');
    return s != 0 ? s : a.id.compareTo(b.id);
  });
  return rows;
}

/// One part of a payment towards one sale (the preview).
class AllocationLine {
  const AllocationLine(this.sale, this.amountTzs);
  final OpenSale sale;
  final int amountTzs;

  int get leftTzs => max(0, sale.balanceTzs - amountTzs);
  bool get paysOff => leftTzs == 0;
}

/// Oldest due first (server allocateOldestFirst): covers [amount] up to
/// what the sales owe.
List<AllocationLine> allocateOldestFirst(List<OpenSale> open, int amount) {
  final out = <AllocationLine>[];
  var left = amount;
  for (final sale in open) {
    if (left <= 0) break;
    final take = min(left, sale.balanceTzs);
    if (take > 0) out.add(AllocationLine(sale, take));
    left -= take;
  }
  return out;
}

/// Where a customer payment form stands (spec §6.1).
class CustomerPaymentCheck {
  CustomerPaymentCheck({
    required this.owedTzs,
    required this.amountTzs,
    required this.method,
    this.reference = '',
    required this.openSales,
    this.manual,
    this.online = true,
  });

  final int owedTzs;
  final int amountTzs;
  final String? method;
  final String reference;
  final List<OpenSale> openSales;

  /// "Choose sales": saleId → amount. Null = oldest due first.
  final Map<String, int>? manual;
  final bool online;

  bool get overOwed => amountTzs > owedTzs;
  bool get needsReference =>
      method != null && referenceRequiredMethods.contains(method);
  bool get referenceMissing => needsReference && reference.trim().isEmpty;

  int get allocatedTzs =>
      manual?.values.fold<int>(0, (s, v) => s + max(0, v)) ?? amountTzs;

  /// Manual amounts that do not add up to the payment.
  bool get allocMismatch => manual != null && allocatedTzs != amountTzs;

  /// A manual amount above that sale's balance.
  bool get allocOverBalance {
    final m = manual;
    if (m == null) return false;
    for (final s in openSales) {
      if ((m[s.id] ?? 0) > s.balanceTzs) return true;
    }
    return false;
  }

  /// The preview lines (oldest first, or the manual split).
  List<AllocationLine> get preview {
    final m = manual;
    if (m == null) {
      return amountTzs <= 0 || overOwed
          ? const []
          : allocateOldestFirst(openSales, amountTzs);
    }
    return [
      for (final s in openSales)
        if ((m[s.id] ?? 0) > 0) AllocationLine(s, m[s.id]!),
    ];
  }

  bool get canSave =>
      online &&
      owedTzs > 0 &&
      amountTzs >= 1 &&
      !overOwed &&
      method != null &&
      !referenceMissing &&
      !allocMismatch &&
      !allocOverBalance;

  /// The request (`receivedOn` only when the vendor picked a day).
  Map<String, dynamic> toRequest({
    required String clientRef,
    String? receivedOn,
    String note = '',
  }) {
    final m = manual;
    final ref = reference.trim();
    final trimmed = note.trim();
    return {
      'clientRef': clientRef,
      'amountTzs': amountTzs,
      'method': method,
      if (method != 'cash' && ref.isNotEmpty) 'reference': ref.toUpperCase(),
      'receivedOn': ?receivedOn,
      if (trimmed.isNotEmpty) 'note': trimmed,
      if (m != null)
        'allocations': [
          for (final s in openSales)
            if ((m[s.id] ?? 0) > 0) {'saleId': s.id, 'amountTzs': m[s.id]},
        ],
    };
  }
}

// ── pay later in the POS ──────────────────────────────────────────────────

/// Where the payment rows stand for a pay-later sale (spec §3.3): paid now
/// must be below the total and never give change.
class CreditCheck {
  CreditCheck(this.totalTzs, List<PaymentRow> rows)
    : rows = [
        for (final r in rows)
          if (r.amountTzs > 0) r,
      ] {
    paidTzs = this.rows.fold(0, (s, r) => s + r.amountTzs);
  }

  final int totalTzs;

  /// Rows with an amount (a row set to 0 is dropped).
  final List<PaymentRow> rows;
  late final int paidTzs;

  int get balanceTzs => max(0, totalTzs - paidTzs);
  bool get fullyPaid => totalTzs > 0 && paidTzs == totalTzs;
  bool get wouldGiveChange => paidTzs > totalTzs;
  bool get rowsComplete => rows.every((r) => r.method != null);
  List<PaymentRow> get missingReferences =>
      rows.where((r) => r.referenceMissing).toList();

  bool canComplete({
    required bool hasCustomer,
    required bool hasDueDate,
    required bool online,
  }) =>
      online &&
      totalTzs > 0 &&
      hasCustomer &&
      hasDueDate &&
      paidTzs < totalTzs &&
      rows.length <= maxSalePayments &&
      rowsComplete &&
      missingReferences.isEmpty;

  List<Map<String, dynamic>> toRequest() => [
    for (final r in rows) r.toRequest(),
  ];
}

/// The terms of a pay-later sale sent with the payments.
class CreditTerms {
  const CreditTerms({required this.customerId, required this.dueDate});
  final String customerId;
  final String dueDate;
}

/// The i18n key for a refusal of a pay-later / customer sale, or null when
/// the S3 handling applies.
String? creditErrorKey(String? code) => switch (code) {
  'credit_not_allowed' => 'vendor.pos.credit.notAllowed',
  'due_date_out_of_range' => 'vendor.pos.credit.dueInvalid',
  'credit_fully_paid' => 'vendor.pos.credit.fullyPaid',
  'change_not_allowed' => 'vendor.pos.credit.noChange',
  'customer_required' => 'vendor.pos.credit.customerRequired',
  'customer_not_found' || 'customer_archived' => 'vendor.pos.customer.gone',
  _ => null,
};

/// Whether a refused sale is about its customer (the sync screen offers
/// "Try again without customer").
bool isCustomerConflict(String? code, Map body) =>
    code == 'customer_not_found' ||
    code == 'customer_archived' ||
    (code == 'feature_disabled' && body['feature'] == 'customers');

// ── plain-text documents (spec §7) ────────────────────────────────────────

const _docWidth = 32;
const _rule = '--------------------';

String _row(String label, String amount) {
  final gap = _docWidth - label.length - amount.length;
  if (gap >= 1) return '$label${' ' * gap}$amount';
  final pad = _docWidth - amount.length;
  return '$label\n${' ' * (pad < 0 ? 0 : pad)}$amount';
}

String _fill(String text, Map<String, Object?> v) {
  var out = text;
  v.forEach((k, val) => out = out.replaceAll('{$k}', '$val'));
  return out;
}

/// A customer payment as plain text (§7.2), in [t]'s language.
String paymentShareText(
  Map payment, {
  required String customerName,
  required int stillOwedTzs,
  String? business,
  required String Function(String key) t,
  required String lang,
}) {
  final b = StringBuffer();
  if (business != null) b.writeln(business);
  b.writeln(_fill(t('vendor.pay.receiptTitle'), {'number': payment['number']}));
  final day = formatDay(_str(payment['receivedOn']), locale: lang);
  if (day.isNotEmpty) b.writeln(day);
  b.writeln(_fill(t('vendor.receipt.customer'), {'name': customerName}));
  b.writeln(_rule);
  final method = t(paymentMethodKey(_str(payment['method'])));
  final ref = _str(payment['reference']);
  b.writeln(
    _row(
      ref == null ? method : '$method ($ref)',
      formatMoney(_int(payment['amountTzs'])),
    ),
  );
  final allocs = (payment['allocations'] as List? ?? []).whereType<Map>();
  if (allocs.isNotEmpty) {
    b.writeln('${t('vendor.pay.paidTowards')}:');
    for (final a in allocs) {
      b.writeln(
        _row(_str(a['saleNumber']) ?? '', formatMoney(_int(a['amountTzs']))),
      );
    }
  }
  b.writeln(_rule);
  b.writeln(_row(t('vendor.pay.stillOwed'), formatCurrency(stillOwedTzs)));
  if (business != null) {
    b.writeln(_fill(t('vendor.pos.receiptFooter'), {'business': business}));
  }
  b.write(t('vendor.pos.notFiscal'));
  return b.toString();
}

/// The customer statement as plain text (§7.3). [payments] are the last
/// 90 days' (voided ones are left out).
String statementShareText({
  required Map customer,
  required List<Map> payments,
  String? business,
  required String Function(String key) t,
  required String lang,
}) {
  final b = StringBuffer();
  if (business != null) b.writeln(business);
  b.writeln(
    _fill(t('vendor.statement.title'), {
      'name': customerDisplayName(customer, t),
    }),
  );
  b.writeln(
    _fill(t('vendor.customers.asOf'), {
      'date': formatDay(_str(customer['asOf']), locale: lang),
    }),
  );
  b.writeln(_rule);
  final open = openSalesOf(customer);
  final owed = _int(customer['owedTzs']);
  if (owed <= 0 && open.isEmpty) {
    b.writeln(t('vendor.statement.nothingOwed'));
  } else {
    b.writeln('${t('vendor.customers.openSales')}:');
    for (final s in open) {
      b.writeln(_row(s.number, formatMoney(s.balanceTzs)));
      final parts = [
        _fill(t('vendor.customers.dueOn'), {
          'date': formatDay(s.dueDate, locale: lang),
        }),
        if (s.daysOverdue > 0)
          _fill(t('vendor.customers.daysOverdue'), {'n': s.daysOverdue}),
      ];
      b.writeln('  ${parts.join(' · ')}');
    }
  }
  final shown = payments.where((p) => p['status'] != 'voided').toList();
  if (shown.isNotEmpty) {
    b.writeln(_rule);
    b.writeln('${t('vendor.statement.recentPayments')}:');
    for (final p in shown) {
      b.writeln(
        _row(
          '${_str(p['number']) ?? ''} ${formatDay(_str(p['receivedOn']), locale: lang)}',
          formatMoney(_int(p['amountTzs'])),
        ),
      );
    }
  }
  b.writeln(_rule);
  b.writeln(_row(t('vendor.statement.totalOwed'), formatCurrency(owed)));
  final aging = customer['aging'] is Map ? customer['aging'] as Map : const {};
  final overdueParts = [
    for (final k in agingBuckets.skip(1))
      if (_int(aging[k]) > 0)
        '${t('vendor.aging.$k')} ${formatCurrency(_int(aging[k]))}',
  ];
  if (overdueParts.isNotEmpty) {
    b.writeln('${t('vendor.owed.overdue')}: ${overdueParts.join(' · ')}');
  }
  b.write(t('vendor.pos.notFiscal'));
  return b.toString();
}
