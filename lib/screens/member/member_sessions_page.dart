// My trainer sessions and my refunds. A member cancels a session here (an
// unpaid one any time before it starts, a paid one up to 24 hours before,
// refunded in full), follows each refund from approved to paid, and can ask
// for a pass or plan payment back. The server decides what can be cancelled:
// every booking carries its own `cancellation` answer.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/ff_datetime.dart';

class MemberSessionsPage extends StatefulWidget {
  const MemberSessionsPage({super.key});

  @override
  State<MemberSessionsPage> createState() => _MemberSessionsPageState();
}

class _MemberSessionsPageState extends State<MemberSessionsPage> {
  List<Map<String, dynamic>>? _bookings;
  List<Map<String, dynamic>> _refunds = const [];
  Object? _error;
  String? _busyId;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  static List<Map<String, dynamic>> _maps(dynamic list) => [
    for (final row in (list as List? ?? const []))
      if (row is Map) row.cast<String, dynamic>(),
  ];

  Future<void> _load() async {
    try {
      final api = AppScope.of(context).api;
      final bookings = await api.myTrainerBookings();
      final refunds = await api.myRefunds();
      if (!mounted) return;
      setState(() {
        _bookings = _maps(bookings)
          ..sort(
            (a, b) => '${b['date']} ${b['slot']}'.compareTo(
              '${a['date']} ${a['slot']}',
            ),
          );
        _refunds = _maps(refunds['refunds']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _cancel(Map<String, dynamic> booking) async {
    final rule = (booking['cancellation'] as Map?) ?? const {};
    final refundable = rule['refundable'] == true;
    final amount = formatCurrency(booking['amountTzs'] as num? ?? 0);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('sessions.cancelTitle')),
        content: Text(
          refundable
              ? context
                    .tr('sessions.cancelConfirmRefund')
                    .replaceFirst('{amount}', amount)
              : context.tr('sessions.cancelConfirm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('sessions.keep')),
          ),
          FilledButton(
            key: const Key('session-cancel-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('sessions.cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr(
      refundable ? 'sessions.cancelledRefund' : 'sessions.cancelled',
    );
    setState(() => _busyId = booking['id']?.toString());
    try {
      await AppScope.of(
        context,
      ).api.cancelMyTrainerBooking(booking['id'].toString());
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(locale, e))));
      await _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _askRefund() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RefundRequestSheet(),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('refunds.requestSent'))),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = _bookings;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('sessions.title'))),
      body: bookings == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('inbox.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                    action: FilledButton(
                      onPressed: _load,
                      child: Text(context.tr('comms.retry')),
                    ),
                  ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  FFSectionTitle(context.tr('sessions.mine')),
                  if (bookings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: FFTokens.spacingMd,
                      ),
                      child: Text(
                        context.tr('sessions.empty'),
                        key: const Key('sessions-empty'),
                      ),
                    )
                  else
                    for (final b in bookings) ...[
                      _SessionCard(
                        booking: b,
                        busy: _busyId == b['id']?.toString(),
                        onCancel: () => _cancel(b),
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                    ],
                  const SizedBox(height: FFTokens.spacingLg),
                  FFSectionTitle(context.tr('refunds.title')),
                  if (_refunds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: FFTokens.spacingMd,
                      ),
                      child: Text(context.tr('refunds.empty')),
                    )
                  else
                    for (final r in _refunds) ...[
                      _RefundCard(refund: r),
                      const SizedBox(height: FFTokens.spacingSm),
                    ],
                  const SizedBox(height: FFTokens.spacingMd),
                  OutlinedButton(
                    key: const Key('refund-ask'),
                    onPressed: _askRefund,
                    child: Text(context.tr('refunds.ask')),
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  Text(
                    context.tr('refunds.askHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.booking,
    required this.busy,
    required this.onCancel,
  });

  final Map<String, dynamic> booking;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final status = booking['status']?.toString() ?? '';
    final rule = (booking['cancellation'] as Map?) ?? const {};
    final canCancel = rule['canCancel'] == true;
    // A paid, upcoming session inside the notice period: say why there is no button.
    final tooLate =
        !canCancel && status == 'confirmed' && rule['cancelBy'] != null;
    final (String key, FFBadgeTone tone) = switch (status) {
      'confirmed' => ('sessions.status.confirmed', FFBadgeTone.success),
      'payment_pending' => ('sessions.status.pending', FFBadgeTone.warning),
      'completed' => ('sessions.status.completed', FFBadgeTone.brand),
      'cancelled' => ('sessions.status.cancelled', FFBadgeTone.gray),
      _ => ('sessions.status.notPaid', FFBadgeTone.gray),
    };
    final trainer = (booking['trainer'] as Map?)?['displayName']?.toString();
    final gym = (booking['gym'] as Map?)?['name']?.toString();
    return FFCard(
      key: Key('session-${booking['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trainer ?? context.tr('sessions.trainer'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FFBadge(label: context.tr(key), tone: tone),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              '${booking['date']} · ${formatClockText('${booking['slot']}')}',
              ?gym,
              formatCurrency(booking['amountTzs'] as num? ?? 0),
            ].join(' · '),
          ),
          if (tooLate)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.tr('sessions.tooLate'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (canCancel)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: Key('session-cancel-${booking['id']}'),
                onPressed: busy ? null : onCancel,
                child: Text(context.tr('sessions.cancel')),
              ),
            ),
        ],
      ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  const _RefundCard({required this.refund});

  final Map<String, dynamic> refund;

  @override
  Widget build(BuildContext context) {
    final status = refund['status']?.toString() ?? 'requested';
    final (String key, FFBadgeTone tone) = switch (status) {
      'approved' => ('refunds.status.approved', FFBadgeTone.brand),
      'paid' => ('refunds.status.paid', FFBadgeTone.success),
      'rejected' => ('refunds.status.rejected', FFBadgeTone.gray),
      _ => ('refunds.status.requested', FFBadgeTone.warning),
    };
    final kind = switch (refund['kind']) {
      'trainer_booking' => 'refunds.kind.session',
      'shop_order' => 'refunds.kind.order',
      _ => 'refunds.kind.pass',
    };
    final detail = switch (status) {
      'paid' =>
        context
            .tr('refunds.paidRef')
            .replaceFirst(
              '{ref}',
              refund['paymentReference']?.toString() ?? '',
            ),
      'rejected' => refund['decisionNote']?.toString() ?? '',
      'approved' => context.tr('refunds.approvedHint'),
      _ => context.tr('refunds.requestedHint'),
    };
    return FFCard(
      key: Key('refund-${refund['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatCurrency(refund['amountTzs'] as num? ?? 0)} · ${context.tr(kind)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FFBadge(label: context.tr(key), tone: tone),
            ],
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Ask for a pass or plan payment back: pick the payment, say why.
class _RefundRequestSheet extends StatefulWidget {
  const _RefundRequestSheet();

  @override
  State<_RefundRequestSheet> createState() => _RefundRequestSheetState();
}

class _RefundRequestSheetState extends State<_RefundRequestSheet> {
  List<Map<String, dynamic>>? _payments;
  String? _paymentId;
  String _reason = 'charged_twice';
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await AppScope.of(context).api.myPayments();
      if (!mounted) return;
      // Only confirmed pass or plan payments: sessions and orders are
      // refunded by cancelling them.
      final payments = [
        for (final p in rows)
          if (p is Map &&
              p['status'] == 'approved' &&
              p['subscriptionId'] != null)
            p.cast<String, dynamic>(),
      ];
      setState(() {
        _payments = payments;
        _paymentId = payments.isEmpty ? null : payments.first['id']?.toString();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _payments = const [];
          _error = errorMessage(FFLocaleScope.of(context), e);
        });
      }
    }
  }

  Future<void> _send() async {
    final note = _note.text.trim();
    if (_reason == 'other' && note.isEmpty) {
      setState(() => _error = context.tr('refunds.noteRequired'));
      return;
    }
    final locale = FFLocaleScope.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).api.requestRefund(
        paymentRequestId: _paymentId!,
        reasonCode: _reason,
        note: note.isEmpty ? null : note,
      );
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _paymentLabel(Map<String, dynamic> p) {
    final what = (p['tier'] ?? p['plan'] ?? '').toString();
    final day = DateTime.tryParse(
      (p['decidedAt'] ?? p['requestedAt'] ?? '').toString(),
    );
    // Pass tiers have names ("Premium"); anything else is shown as sent.
    final isTier = const {
      'basic',
      'pro',
      'premium',
      'executive',
    }.contains(what.toLowerCase());
    return [
      formatCurrency(p['amountTzs'] as num? ?? 0),
      if (what.isNotEmpty)
        isTier ? context.tr('pass.${what.toLowerCase()}') : what,
      if (day != null) DateFormat('d MMM yyyy').format(day.toLocal()),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          FFTokens.spacingLg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('refunds.ask'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: FFTokens.spacingMd),
            if (payments == null)
              const Center(child: FFSpinner())
            else if (payments.isEmpty)
              Text(_error ?? context.tr('refunds.noPayments'))
            else ...[
              DropdownButtonFormField<String>(
                key: const Key('refund-payment'),
                initialValue: _paymentId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('refunds.payment'),
                ),
                items: [
                  for (final p in payments)
                    DropdownMenuItem(
                      value: p['id']?.toString(),
                      child: Text(
                        _paymentLabel(p),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _paymentId = v),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              DropdownButtonFormField<String>(
                key: const Key('refund-reason'),
                initialValue: _reason,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('refunds.reason'),
                ),
                items: [
                  for (final r in const [
                    'charged_twice',
                    'not_activated',
                    'other',
                  ])
                    DropdownMenuItem(
                      value: r,
                      child: Text(context.tr('refunds.reason.$r')),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _reason = v ?? 'other'),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              TextField(
                key: const Key('refund-note'),
                controller: _note,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: context.tr('refunds.note'),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('refund-send'),
                  onPressed: _busy || _paymentId == null ? null : _send,
                  child: Text(context.tr('refunds.send')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
