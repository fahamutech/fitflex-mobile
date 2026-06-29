// Members list screen (Gym Owner > Members tab). Pixel-aligned to the
// "Members Management Flow" design. UI only — all data/logic lives in
// [MemberListController] + [MemberRepository].

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../owner_shell.dart';
import 'data/member_models.dart';
import 'data/member_repository.dart';
import 'member_controller.dart';
import 'widgets/add_member_sheet.dart';
import 'widgets/filter_members_sheet.dart';
import 'widgets/member_list_tile.dart';

class OwnerMembersPage extends StatefulWidget {
  const OwnerMembersPage({super.key});

  @override
  State<OwnerMembersPage> createState() => _OwnerMembersPageState();
}

class _OwnerMembersPageState extends State<OwnerMembersPage> {
  MemberListController? _controller;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _controller = MemberListController(
      MemberRepository(AppScope.of(context).api),
    );
    _controller!.load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _controller?.setSearch(value);
    });
  }

  Future<void> _openFilters() async {
    final c = _controller!;
    final result = await openFilterMembersSheet(
      context,
      type: c.typeFilter,
      status: c.statusFilter,
    );
    if (result != null) {
      c.applyFilters(type: result.type, status: result.status);
    }
  }

  Future<void> _addMember() async {
    final gyms = OwnerDataScope.of(context).ownerGyms;
    final payload = await openAddMemberSheet(context, gyms: gyms);
    if (payload == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _controller!.repository.createMember(payload);
      await _controller!.refresh();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('owner.memberAdded'))),
      );
    } on ApiException {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('owner.errorGeneric'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: FFSpinner());
    }
    return Stack(
      children: [
        SafeArea(
          child: Column(
            children: [
              const _MembersHeader(),
              Expanded(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: _buildBody(context, controller),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: FFTokens.spacingLg,
          bottom: FFTokens.spacingLg,
          child: _ScanQrButton(onTap: () => context.push('/owner/scan')),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, MemberListController c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        0,
        FFTokens.spacingLg,
        96,
      ),
      children: [
        Text(
          context.tr('members.title'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(
          context.tr('members.subtitle'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton.icon(
          onPressed: _addMember,
          icon: const Icon(Icons.add, size: FFTokens.iconMd),
          label: Text(context.tr('members.addMember')),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        _StatsRow(stats: c.stats),
        const SizedBox(height: FFTokens.spacingMd),
        Row(
          children: [
            Expanded(
              child: FFTextField(
                controller: _searchCtrl,
                hint: context.tr('members.searchHint'),
                prefixIcon: const Icon(Icons.search, size: FFTokens.iconMd),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            _FilterButton(active: c.hasActiveFilters, onTap: _openFilters),
          ],
        ),
        const SizedBox(height: FFTokens.spacingMd),
        _QuickFilterChips(controller: c),
        const SizedBox(height: FFTokens.spacingMd),
        if (c.loading && c.members.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: FFTokens.spacing2xl),
            child: Center(child: FFSpinner()),
          )
        else if (c.error != null)
          _ErrorState(onRetry: c.refresh)
        else if (c.isEmpty)
          _EmptyMembers(
            onAdd: _addMember,
            onScan: () => context.push('/owner/scan'),
          )
        else
          ...c.members.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: MemberListTile(
                member: m,
                onTap: () => context.push('/owner/members/${m.id}'),
              ),
            ),
          ),
      ],
    );
  }
}

class _MembersHeader extends StatelessWidget {
  const _MembersHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = OwnerDataScope.of(context);
    final gyms = data.ownerGyms;
    final selectedName = gyms.isNotEmpty
        ? (gyms.first['name']?.toString() ?? context.tr('owner.gym'))
        : context.tr('owner.gym');
    final name = data.displayName;
    final initials = _initials(name);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingSm,
        FFTokens.spacingLg,
        FFTokens.spacingMd,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: FFTokens.brand500,
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                ),
                child: const Icon(
                  Icons.fitness_center,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    context.tr('members.headerSubtitle'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              const ThemeToggleButton(),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => context.push('/owner/profile'),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: FFTokens.brand500,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'O';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final MemberStats stats;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FFStatTile(
              icon: Icons.groups_outlined,
              value: '${stats.totalMembers}',
              label: context.tr('members.totalMembers'),
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: FFStatTile(
              icon: Icons.trending_up,
              value: '${stats.activeToday}',
              label: context.tr('members.activeToday'),
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: FFStatTile(
              icon: Icons.schedule,
              value: '${stats.expiringSoon}',
              label: context.tr('members.expiringSoon'),
              accent: FFTokens.warning500,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surface,
          border: Border.all(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        child: Icon(
          Icons.tune,
          size: FFTokens.iconMd,
          color: active
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _QuickFilterChips extends StatelessWidget {
  const _QuickFilterChips({required this.controller});

  final MemberListController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final chips = <(_QuickFilter, String)>[
      (_QuickFilter.all, context.tr('members.filterAll')),
      (_QuickFilter.direct, context.tr('members.tabDirect')),
      (_QuickFilter.fitflex, context.tr('members.tabFitflex')),
      (_QuickFilter.active, context.tr('status.active')),
      (_QuickFilter.expired, context.tr('status.expired')),
    ];
    final selected = _resolveSelected(c);

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: FFTokens.spacingSm),
        itemBuilder: (context, i) {
          final chip = chips[i];
          return _Chip(
            label: chip.$2,
            selected: selected == chip.$1,
            onTap: () => _apply(c, chip.$1),
          );
        },
      ),
    );
  }

  _QuickFilter _resolveSelected(MemberListController c) {
    if (c.statusFilter == OwnerMemberStatus.active) return _QuickFilter.active;
    if (c.statusFilter == OwnerMemberStatus.expired) {
      return _QuickFilter.expired;
    }
    return switch (c.typeFilter) {
      MemberTypeFilter.direct => _QuickFilter.direct,
      MemberTypeFilter.fitflex => _QuickFilter.fitflex,
      MemberTypeFilter.all => _QuickFilter.all,
    };
  }

  void _apply(MemberListController c, _QuickFilter f) {
    switch (f) {
      case _QuickFilter.all:
        c.applyFilters(type: MemberTypeFilter.all, status: null);
      case _QuickFilter.direct:
        c.applyFilters(type: MemberTypeFilter.direct, status: null);
      case _QuickFilter.fitflex:
        c.applyFilters(type: MemberTypeFilter.fitflex, status: null);
      case _QuickFilter.active:
        c.applyFilters(
          type: MemberTypeFilter.all,
          status: OwnerMemberStatus.active,
        );
      case _QuickFilter.expired:
        c.applyFilters(
          type: MemberTypeFilter.all,
          status: OwnerMemberStatus.expired,
        );
    }
  }
}

enum _QuickFilter { all, direct, fitflex, active, expired }

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: FFTokens.motionFast,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingMd),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surface,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(FFTokens.radiusFull),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ScanQrButton extends StatelessWidget {
  const _ScanQrButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 64,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.qr_code_scanner,
                color: theme.colorScheme.onPrimary,
                size: FFTokens.iconLg,
              ),
              const SizedBox(height: 2),
              Text(
                context.tr('members.scanQrShort'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMembers extends StatelessWidget {
  const _EmptyMembers({required this.onAdd, required this.onScan});

  final VoidCallback onAdd;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXl),
      child: FFEmptyState(
        title: context.tr('members.noMembersTitle'),
        body: context.tr('members.noMembersBody'),
        action: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAdd,
                child: Text(context.tr('members.addMember')),
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.qr_code_scanner, size: FFTokens.iconMd),
                label: Text(context.tr('members.scanQr')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXl),
      child: FFEmptyState(
        title: context.tr('members.errorLoading'),
        action: OutlinedButton(
          onPressed: onRetry,
          child: Text(context.tr('members.retry')),
        ),
      ),
    );
  }
}
