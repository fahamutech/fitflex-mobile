// Communication history pages: a member's communications from this gym
// (from the member detail page's Messages section) and who a campaign went
// to (from the campaign detail page). Both filter by channel and status,
// page with "Load more", and open any message in full.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'data/communication_models.dart';
import 'data/communication_repository.dart';
import 'data/history_models.dart';
import 'widgets/comms_format.dart';
import 'widgets/history_widgets.dart';

typedef HistoryLoader<T> =
    Future<HistoryPage<T>> Function(HistoryFilter filter, String? cursor);

/// A filtered, paged history list.
class HistoryListController<T> extends ChangeNotifier {
  HistoryListController(this._load);

  final HistoryLoader<T> _load;
  HistoryFilter _filter = const HistoryFilter();
  final List<T> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _started = false;
  Object? _error;
  int _generation = 0;

  HistoryFilter get filter => _filter;
  List<T> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get hasMore => _cursor != null;
  bool get started => _started;
  Object? get error => _error;

  Future<void> refresh() async {
    final gen = ++_generation;
    _items.clear();
    _cursor = null;
    _started = true;
    await _fetch(gen, null);
  }

  Future<void> loadMore() async {
    if (_loading || _cursor == null) return;
    await _fetch(_generation, _cursor);
  }

  Future<void> _fetch(int gen, String? cursor) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _load(_filter, cursor);
      if (gen != _generation) return; // a newer filter replaced this load
      _items.addAll(page.items);
      _cursor = page.nextCursor;
    } catch (e) {
      if (gen == _generation) _error = e;
    } finally {
      if (gen == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void setFilter(HistoryFilter f) {
    _filter = f;
    refresh();
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.onChanged,
    this.withCategory = false,
    this.withDates = false,
  });

  final HistoryFilter filter;
  final ValueChanged<HistoryFilter> onChanged;
  final bool withCategory;
  final bool withDates;

  Widget _row(List<Widget> children) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final c in children)
          Padding(
            padding: const EdgeInsets.only(right: FFTokens.spacingXs),
            child: c,
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final range = filter.from != null && filter.to != null
        ? '${formatDay(filter.from!)} – ${formatDay(filter.to!)}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row([
          FFPill(
            key: const Key('hist-channel-all'),
            label: context.tr('comms.filter.allChannels'),
            filled: filter.channel == null,
            onTap: () => onChanged(filter.copyWith(channel: () => null)),
          ),
          for (final ch in CommChannel.values)
            FFPill(
              key: Key('hist-channel-${ch.wire}'),
              label: channelLabel(context, ch),
              filled: filter.channel == ch,
              onTap: () => onChanged(filter.copyWith(channel: () => ch)),
            ),
        ]),
        const SizedBox(height: FFTokens.spacingXs),
        _row([
          FFPill(
            key: const Key('hist-status-all'),
            label: context.tr('comms.filter.all'),
            filled: filter.status == null,
            onTap: () => onChanged(filter.copyWith(status: () => null)),
          ),
          for (final s in kHistoryStatusFilters)
            FFPill(
              key: Key('hist-status-$s'),
              label: context.tr('comms.historyFilter.$s'),
              filled: filter.status == s,
              onTap: () => onChanged(filter.copyWith(status: () => s)),
            ),
        ]),
        if (withCategory || withDates) ...[
          const SizedBox(height: FFTokens.spacingXs),
          _row([
            if (withCategory) ...[
              for (final c in const [null, 'transactional', 'marketing'])
                FFPill(
                  key: Key('hist-category-${c ?? 'all'}'),
                  label: context.tr(
                    c == null ? 'comms.filter.allTypes' : 'comms.category.$c',
                  ),
                  filled: filter.category == c,
                  onTap: () => onChanged(filter.copyWith(category: () => c)),
                ),
            ],
            if (withDates)
              FFPill(
                key: const Key('hist-dates'),
                label: range ?? context.tr('comms.history.anyDate'),
                filled: range != null,
                onTap: () async {
                  if (range != null) {
                    onChanged(
                      filter.copyWith(from: () => null, to: () => null),
                    );
                    return;
                  }
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year - 3),
                    lastDate: now,
                  );
                  if (picked != null) {
                    onChanged(
                      filter.copyWith(
                        from: () => picked.start,
                        to: () => picked.end,
                      ),
                    );
                  }
                },
              ),
          ]),
        ],
      ],
    );
  }
}

/// The list body shared by both pages: items, empty and error states, and
/// "Load more".
class _HistoryList<T> extends StatelessWidget {
  const _HistoryList({
    required this.controller,
    required this.header,
    required this.itemBuilder,
    required this.emptyKey,
  });

  final HistoryListController<T> controller;
  final Widget header;
  final Widget Function(T item) itemBuilder;
  final String emptyKey;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          header,
          const SizedBox(height: FFTokens.spacingMd),
          if (c.error != null && c.items.isEmpty)
            FFEmptyState(
              title: context.tr('comms.loadFailed'),
              body: errorMessage(FFLocaleScope.of(context), c.error!),
              action: FilledButton(
                onPressed: c.refresh,
                child: Text(context.tr('comms.retry')),
              ),
            )
          else if (c.items.isEmpty && (c.loading || !c.started))
            const Padding(
              padding: EdgeInsets.all(FFTokens.spacingXl),
              child: Center(child: FFSpinner()),
            )
          else if (c.items.isEmpty)
            FFEmptyState(
              key: const Key('history-empty'),
              title: context.tr(emptyKey),
              body: c.filter.isEmpty
                  ? null
                  : context.tr('comms.history.tryOtherFilters'),
            )
          else ...[
            for (final item in c.items) itemBuilder(item),
            if (c.hasMore)
              Center(
                child: c.loading
                    ? const FFSpinner()
                    : OutlinedButton(
                        key: const Key('history-more'),
                        onPressed: c.loadMore,
                        child: Text(context.tr('comms.history.loadMore')),
                      ),
              ),
          ],
        ],
      );
    },
  );
}

/// A member's communications from this gym, newest first.
class MemberCommunicationsPage extends StatefulWidget {
  const MemberCommunicationsPage({
    super.key,
    required this.memberId,
    this.repository,
  });

  final String memberId;
  final CommunicationRepository? repository;

  @override
  State<MemberCommunicationsPage> createState() =>
      _MemberCommunicationsPageState();
}

class _MemberCommunicationsPageState extends State<MemberCommunicationsPage> {
  late CommunicationRepository _repo;
  HistoryListController<CommunicationItem>? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    _repo =
        widget.repository ?? CommunicationRepository(AppScope.of(context).api);
    _c = HistoryListController(
      (f, cursor) => _repo.memberCommunications(
        widget.memberId,
        filter: f,
        cursor: cursor,
      ),
    )..refresh();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('comms.history.memberTitle'))),
    body: _HistoryList<CommunicationItem>(
      controller: _c!,
      emptyKey: 'comms.history.noneYet',
      header: AnimatedBuilder(
        animation: _c!,
        builder: (context, _) => _FilterBar(
          filter: _c!.filter,
          onChanged: _c!.setFilter,
          withCategory: true,
          withDates: true,
        ),
      ),
      itemBuilder: (item) => CommunicationTile(
        item: item,
        onOpen: (m) =>
            showMessageDetail(context, repository: _repo, messageId: m.id),
      ),
    ),
  );
}

/// Who a campaign went to, one row per member.
class CampaignRecipientsPage extends StatefulWidget {
  const CampaignRecipientsPage({
    super.key,
    required this.campaignId,
    this.repository,
  });

  final String campaignId;
  final CommunicationRepository? repository;

  @override
  State<CampaignRecipientsPage> createState() => _CampaignRecipientsPageState();
}

class _CampaignRecipientsPageState extends State<CampaignRecipientsPage> {
  late CommunicationRepository _repo;
  HistoryListController<Recipient>? _c;
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    _repo =
        widget.repository ?? CommunicationRepository(AppScope.of(context).api);
    _c = HistoryListController(
      (f, cursor) =>
          _repo.recipients(widget.campaignId, filter: f, cursor: cursor),
    )..refresh();
  }

  @override
  void dispose() {
    _c?.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('comms.history.recipientsTitle'))),
    body: _HistoryList<Recipient>(
      controller: _c!,
      emptyKey: 'comms.history.noRecipients',
      header: AnimatedBuilder(
        animation: _c!,
        builder: (context, _) => Column(
          children: [
            FFTextField(
              key: const Key('recipients-search'),
              controller: _search,
              hint: context.tr('comms.history.searchMember'),
              prefixIcon: const Icon(Icons.search),
              textInputAction: TextInputAction.search,
              onFieldSubmitted: (v) =>
                  _c!.setFilter(_c!.filter.copyWith(search: () => v)),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            _FilterBar(filter: _c!.filter, onChanged: _c!.setFilter),
          ],
        ),
      ),
      itemBuilder: (r) => RecipientTile(
        recipient: r,
        onOpen: (m) =>
            showMessageDetail(context, repository: _repo, messageId: m.id),
        onOpenMember: () => context.push('/owner/members/${r.memberId}'),
      ),
    ),
  );
}
