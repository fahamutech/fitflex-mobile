// Vendor tools · S3: what a receipt shows, from a recorded sale (the server's
// `sale`) or from a sale still queued on this device, and the plain-text
// version shared through the system share sheet (spec §4.2).
import '../../../shared/formatters.dart';
import 'sale_models.dart';

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? _str(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    this.variant,
    required this.qty,
    required this.unitPriceTzs,
    required this.listPriceTzs,
    required this.discountTzs,
    required this.lineTotalTzs,
    this.priceChangedBy,
  });

  final String name;
  final String? variant;
  final int qty;
  final int unitPriceTzs;
  final int listPriceTzs;
  final int discountTzs;
  final int lineTotalTzs;
  final String? priceChangedBy;

  bool get priceChanged => unitPriceTzs != listPriceTzs;
}

class ReceiptPayment {
  const ReceiptPayment(this.method, this.amountTzs, this.reference);
  final String method;
  final int amountTzs;
  final String? reference;
}

class ReceiptData {
  const ReceiptData({
    this.id,
    this.number,
    this.clientRef,
    this.business,
    this.contact,
    this.address,
    required this.soldAt,
    this.recordedAt,
    this.servedBy,
    this.servedById,
    required this.lines,
    required this.subtotalTzs,
    required this.lineDiscountTzs,
    required this.saleDiscountTzs,
    required this.totalTzs,
    required this.payments,
    required this.changeTzs,
    this.status = 'completed',
    this.note,
    this.voidedBy,
    this.voidedAt,
    this.voidReason,
    this.lateRecorded = false,
    this.queued = false,
  });

  final String? id;
  final String? number;
  final String? clientRef;
  final String? business;
  final String? contact;
  final String? address;
  final String? soldAt;
  final String? recordedAt;
  final String? servedBy;
  final String? servedById;
  final List<ReceiptLine> lines;
  final int subtotalTzs;
  final int lineDiscountTzs;
  final int saleDiscountTzs;
  final int totalTzs;
  final List<ReceiptPayment> payments;
  final int changeTzs;
  final String status;
  final String? note;
  final String? voidedBy;
  final String? voidedAt;
  final String? voidReason;
  final bool lateRecorded;

  /// Still on this device: no receipt number yet.
  final bool queued;

  bool get voided => status == 'voided';
  int get discountsTzs => lineDiscountTzs + saleDiscountTzs;
  String? get tempRef => clientRef == null ? null : tempRefOf(clientRef!);

  /// A sale as the server sends it (POST /vendor/sales, GET /vendor/sales/:id).
  factory ReceiptData.fromSale(
    Map<String, dynamic> sale, {
    Map<String, dynamic> profile = const {},
  }) {
    Map? person(Object? v) => v is Map ? v : null;
    final soldAt = _str(sale['soldAt']);
    final recordedAt = _str(sale['recordedAt']);
    final late =
        sale['lateRecorded'] == true ||
        (sale['lateRecorded'] == null && recordedLate(soldAt, recordedAt));
    return ReceiptData(
      id: _str(sale['id']),
      number: _str(sale['number']),
      clientRef: _str(sale['clientRef']),
      business: _str(profile['businessName']),
      contact: _str(profile['contactNumber']),
      address: _str(profile['address']),
      soldAt: soldAt,
      recordedAt: recordedAt,
      servedBy: _str(person(sale['createdBy'])?['name']),
      servedById: _str(person(sale['createdBy'])?['id']),
      lines: [
        for (final l in (sale['lines'] as List? ?? []).whereType<Map>())
          ReceiptLine(
            name: _str(l['nameSnapshot']) ?? '',
            variant: _str(l['variant']),
            qty: _int(l['qty']),
            unitPriceTzs: _int(l['unitPriceTzs']),
            listPriceTzs: _int(l['listPriceTzs']),
            discountTzs: _int(l['discountTzs']),
            lineTotalTzs: _int(l['lineTotalTzs']),
            priceChangedBy: _str(person(l['priceChangedBy'])?['name']),
          ),
      ],
      subtotalTzs: _int(sale['subtotalTzs']),
      lineDiscountTzs: _int(sale['lineDiscountTzs']),
      saleDiscountTzs: _int(sale['discountTzs']),
      totalTzs: _int(sale['totalTzs']),
      payments: [
        for (final p in (sale['payments'] as List? ?? []).whereType<Map>())
          ReceiptPayment(
            p['method']?.toString() ?? 'other',
            _int(p['amountTzs']),
            _str(p['reference']),
          ),
      ],
      changeTzs: _int(sale['changeTzs']),
      status: sale['status']?.toString() ?? 'completed',
      note: _str(sale['note']),
      voidedBy: _str(person(sale['voidedBy'])?['name']),
      voidedAt: _str(sale['voidedAt']),
      voidReason: _str(sale['voidReason']),
      lateRecorded: late,
    );
  }

  /// A queued sale: its request plus the snapshot taken when it was queued.
  factory ReceiptData.fromQueued(
    Map<String, dynamic> body,
    Map<String, dynamic> display,
  ) {
    final shown = (display['lines'] as List? ?? []).whereType<Map>().toList();
    final rows = (body['lines'] as List? ?? []).whereType<Map>().toList();
    final lines = <ReceiptLine>[];
    var subtotal = 0;
    var lineDiscounts = 0;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final s = i < shown.length ? shown[i] : const {};
      final list = _int(s['listPriceTzs']);
      final price = r['unitPriceTzs'] == null ? list : _int(r['unitPriceTzs']);
      final qty = _int(r['qty']);
      final discount = _int(r['discountTzs']);
      subtotal += qty * price;
      lineDiscounts += discount;
      lines.add(
        ReceiptLine(
          name: _str(s['name']) ?? '',
          variant: _str(r['variant']),
          qty: qty,
          unitPriceTzs: price,
          listPriceTzs: list,
          discountTzs: discount,
          lineTotalTzs: qty * price - discount,
        ),
      );
    }
    final saleDiscount = _int(body['discountTzs']);
    final total = subtotal - lineDiscounts - saleDiscount;
    final payments = [
      for (final p in (body['payments'] as List? ?? []).whereType<Map>())
        ReceiptPayment(
          p['method']?.toString() ?? 'other',
          _int(p['amountTzs']),
          _str(p['reference']),
        ),
    ];
    final paid = payments.fold(0, (s, p) => s + p.amountTzs);
    return ReceiptData(
      clientRef: _str(body['clientRef']),
      business: _str(display['business']),
      contact: _str(display['contact']),
      address: _str(display['address']),
      soldAt: _str(body['soldAt']),
      servedBy: _str(display['servedBy']),
      lines: lines,
      subtotalTzs: subtotal,
      lineDiscountTzs: lineDiscounts,
      saleDiscountTzs: saleDiscount,
      totalTzs: total,
      payments: payments,
      changeTzs: paid > total ? paid - total : 0,
      note: _str(body['note']),
      queued: true,
    );
  }
}

/// Recorded more than 5 minutes after it was sold (an offline sale).
bool recordedLate(String? soldAt, String? recordedAt) {
  final sold = DateTime.tryParse(soldAt ?? '');
  final recorded = DateTime.tryParse(recordedAt ?? '');
  if (sold == null || recorded == null) return false;
  return recorded.difference(sold) > const Duration(minutes: 5);
}

/// "19 Oct 2026, 14:05" in East Africa time (UTC+3), whatever the device zone.
String eatDateTime(String? iso, {String locale = 'en'}) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  final eat = d.toUtc().add(const Duration(hours: 3));
  final local = DateTime(eat.year, eat.month, eat.day, eat.hour, eat.minute);
  return formatDateTime(local, locale: locale);
}

/// The EAT calendar day of an instant, for "same day" checks.
DateTime? eatDayOf(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return null;
  final eat = d.toUtc().add(const Duration(hours: 3));
  return DateTime.utc(eat.year, eat.month, eat.day);
}

const _width = 30;

String _row(String label, String amount, {String indent = ''}) {
  final left = '$indent$label';
  final gap = _width - left.length - amount.length;
  return '$left${' ' * (gap < 1 ? 1 : gap)}$amount';
}

/// The receipt as plain text (spec §4.2), in the language [t] answers in.
/// [t] looks up an i18n key in the receipt's language.
String receiptShareText(
  ReceiptData r,
  String Function(String key) t,
  String lang,
) {
  String fill(String key, Map<String, Object?> v) {
    var out = t(key);
    v.forEach((k, val) => out = out.replaceAll('{$k}', '$val'));
    return out;
  }

  const rule = '--------------------';
  final b = StringBuffer();
  if (r.business != null) b.writeln(r.business);
  if (r.queued || r.number == null) {
    b.writeln(fill('vendor.pos.shareProvisional', {'ref': r.tempRef ?? ''}));
  } else {
    b.writeln(fill('vendor.pos.receiptNo', {'number': r.number}));
  }
  final when = eatDateTime(r.soldAt, locale: lang);
  if (when.isNotEmpty) b.writeln(when);
  b.writeln(rule);
  for (final l in r.lines) {
    final name = l.variant == null ? l.name : '${l.name} (${l.variant})';
    final gross = l.qty * l.unitPriceTzs;
    if (l.qty > 1 || l.priceChanged) {
      b.writeln('${l.qty} x $name');
      b.writeln(
        _row(
          '@ ${formatMoney(l.unitPriceTzs)}',
          formatMoney(gross),
          indent: '   ',
        ),
      );
    } else {
      b.writeln(_row('${l.qty} x $name', formatMoney(gross)));
    }
    if (l.discountTzs > 0) {
      b.writeln(
        _row(
          t('vendor.pos.lineDiscountShort'),
          '-${formatMoney(l.discountTzs)}',
          indent: '   ',
        ),
      );
    }
  }
  b.writeln(rule);
  b.writeln(_row(t('vendor.pos.subtotal'), formatMoney(r.subtotalTzs)));
  if (r.discountsTzs > 0) {
    b.writeln(
      _row(t('vendor.pos.discounts'), '-${formatMoney(r.discountsTzs)}'),
    );
  }
  b.writeln(_row(t('vendor.pos.total'), formatCurrency(r.totalTzs)));
  for (final p in r.payments) {
    final method = t(paymentMethodKey(p.method));
    b.writeln(
      _row(
        p.reference == null ? method : '$method (${p.reference})',
        formatMoney(p.amountTzs),
      ),
    );
  }
  if (r.changeTzs > 0) {
    b.writeln(_row(t('vendor.pos.change'), formatMoney(r.changeTzs)));
  }
  b.writeln(rule);
  if (r.servedBy != null) {
    b.writeln(fill('vendor.pos.servedBy', {'name': r.servedBy}));
  }
  if (r.business != null) {
    b.writeln(fill('vendor.pos.receiptFooter', {'business': r.business}));
  }
  b.write(t('vendor.pos.notFiscal'));
  return b.toString();
}
