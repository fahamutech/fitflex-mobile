// "View all" data tables for a member's check-in history and payment history.
// Paginated (load-more), with custom date-range selection and search — backed
// by the paginated /owner/members/:id/checkins and /payments endpoints.
// UI only; pagination/search/date-range logic lives in [PagedListController].

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import 'data/member_models.dart';
import 'data/member_repository.dart';
import 'member_controller.dart';
import 'widgets/member_format.dart';

/// Which history table to show.
enum MemberHistoryKind { checkins, payments }

class MemberHistoryPage extends StatefulWidget {
  const MemberHistoryPage({
    super.key,
    required this.memberId,
    required this.kind,
  });

  final String memberId;
  final MemberHistoryKind kind;

  @override
  State<MemberHistoryPage> createState() => _MemberHistoryPageState();
}

class _MemberHistoryPageState extends State<MemberHistoryPage> {
  PagedListController<Object>? _controller;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final repo = MemberRepository(AppScope.of(context).api);
    _controller = PagedListController<Object>(_buildFetcher(repo));
    _controller!.refresh();
    _scrollCtrl.addListener(_onScroll);
  }

  PagedFetcher<Object> _buildFetcher(MemberRepository repo) {
    return ({cursor, limit = 20, from, to, search}) async {
      if (widget.kind == MemberHistoryKind.checkins) {
        final page = await repo.fetchCheckins(
          widget.memberId,
          cursor: cursor,
          limit: limit,
          from: from,
          to: to,
          search: search,
        );
        return PagedResult<Object>(
          items: page.items,
          total: page.total,
          nextCursor: page.nextCursor,
        );
      }
      final page = await repo.fetchPayments(
        widget.memberId,
        cursor: cursor,
        limit: limit,
        from: from,
        to: to,
        search: search,
      );
      return PagedResult<Object>(
        items: page.items,
        total: page.total,
        nextCursor: page.nextCursor,
      );
    };
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _controller?.loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _controller?.setSearch(value);
    });
  }

  Future<void> _pickDateRange() async {
    final c = _controller!;
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: c.from != null && c.to != null
          ? DateTimeRange(start: c.from!, end: c.to!)
          : null,
    );
    if (picked != null) {
      await c.setDateRange(picked.start, picked.end);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  bool get _isCheckins => widget.kind == MemberHistoryKind.checkins;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final title = _isCheckins
        ? context.tr('members.allCheckins')
        : context.tr('members.allPayments');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: controller == null
          ? const Center(child: FFSpinner())
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Column(
                children: [
                  _FilterBar(
                    searchCtrl: _searchCtrl,
                    searchHint: _isCheckins
                        ? context.tr('members.searchCheckins')
                        : context.tr('members.searchPayments'),
                    onSearchChanged: _onSearchChanged,
                    total: controller.total,
                    hasDateRange: controller.hasDateRange,
                    from: controller.from,
                    to: controller.to,
                    onPickRange: _pickDateRange,
                    onClearRange: controller.clearDateRange,
                  ),
                  Expanded(child: _buildBody(context, controller)),
                ],
              ),
            ),
    );
  }

  Widget _buildBody(BuildContext context, PagedListController<Object> c) {
    if (c.loading && c.items.isEmpty) {
      return const Center(child: FFSpinner());
    }
    if (c.error != null && c.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: FFEmptyState(
            title: context.tr('members.errorLoading'),
            action: OutlinedButton(
              onPressed: c.refresh,
              child: Text(context.tr('members.retry')),
            ),
          ),
        ),
      );
    }
    if (c.isEmpty) {
      return Center(
        child: FFEmptyState(
          title: _isCheckins
              ? context.tr('members.noCheckins')
              : context.tr('members.noPayments'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        itemCount: c.items.length + (c.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= c.items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingMd),
              child: Center(
                child: c.loadingMore
                    ? const FFSpinner()
                    : OutlinedButton(
                        onPressed: c.loadMore,
                        child: Text(context.tr('members.loadMore')),
                      ),
              ),
            );
          }
          final item = c.items[i];
          return _isCheckins
              ? _CheckinRow(checkin: item as MemberCheckin)
              : _PaymentRow(payment: item as MemberPayment);
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchCtrl,
    required this.searchHint,
    required this.onSearchChanged,
    required this.total,
    required this.hasDateRange,
    required this.from,
    required this.to,
    required this.onPickRange,
    required this.onClearRange,
  });

  final TextEditingController searchCtrl;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final int total;
  final bool hasDateRange;
  final DateTime? from;
  final DateTime? to;
  final VoidCallback onPickRange;
  final Future<void> Function() onClearRange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rangeLabel = hasDateRange && from != null && to != null
        ? '${formatDate(from!)} – ${formatDate(to!)}'
        : context.tr('members.dateRange');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingMd,
        FFTokens.spacingLg,
        0,
      ),
      child: Column(
        children: [
          FFTextField(
            controller: searchCtrl,
            hint: searchHint,
            prefixIcon: const Icon(Icons.search, size: FFTokens.iconMd),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickRange,
                  icon: const Icon(
                    Icons.calendar_today_outlined,
                    size: FFTokens.iconSm,
                  ),
                  label: Text(
                    rangeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (hasDateRange) ...[
                const SizedBox(width: FFTokens.spacingSm),
                IconButton(
                  tooltip: context.tr('members.clear'),
                  onPressed: onClearRange,
                  icon: const Icon(Icons.close, size: FFTokens.iconSm),
                ),
              ],
            ],
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$total ${context.tr('members.totalCount')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckinRow extends StatelessWidget {
  const _CheckinRow({required this.checkin});

  final MemberCheckin checkin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.check_circle, color: theme.colorScheme.primary),
      title: Text(
        checkin.timestamp != null
            ? formatDateTime(context, checkin.timestamp!)
            : '—',
        style: theme.textTheme.labelLarge,
      ),
      subtitle: checkin.gymName != null
          ? Text(checkin.gymName!, style: theme.textTheme.bodySmall)
          : null,
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final MemberPayment payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        payment.requestedAt != null ? formatDate(payment.requestedAt!) : '—',
        style: theme.textTheme.labelLarge,
      ),
      subtitle: payment.tier != null
          ? Text(_cap(payment.tier!), style: theme.textTheme.bodySmall)
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatCurrency(payment.amountTzs),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          FFBadge(label: context.tr('members.paid'), tone: FFBadgeTone.success),
        ],
      ),
    );
  }

  static String _cap(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
}
