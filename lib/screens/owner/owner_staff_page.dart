import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/staff_form_page.dart';
import 'owner_shell.dart';

String _staffApiErrorMessage(BuildContext context, ApiException e) {
  final code = (e.body is Map) ? (e.body as Map)['error']?.toString() : null;
  switch (code) {
    case 'email_already_in_use':
      return context.tr('owner.errorEmailAlreadyInUse');
    case 'must_assign_to_at_least_one_owned_gym':
      return context.tr('staff.selectAtLeastOneGym');
    default:
      return context.tr('owner.errorGeneric');
  }
}

/// Owner — gym staff roster (receptionists etc.) with per-feature RBAC.
/// Owner-only: staff cannot manage other staff.
class OwnerStaffPage extends StatefulWidget {
  const OwnerStaffPage({super.key});

  @override
  State<OwnerStaffPage> createState() => _OwnerStaffPageState();
}

class _OwnerStaffPageState extends State<OwnerStaffPage> {
  List<Map<String, dynamic>> _staff = [];
  // B8: this route lives outside the owner shell, so the gyms must be
  // fetched here — otherwise the add-staff form shows no gyms to assign.
  List<Map<String, dynamic>> _fetchedGyms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final api = AppScope.of(context).api;
    try {
      final res = await api.ownerStaff();
      if (mounted) setState(() => _staff = res.cast<Map<String, dynamic>>());
    } on ApiException {
      // ignore
    }
    if (!mounted) return;
    try {
      final gyms = await api.ownerGyms();
      if (mounted) {
        setState(() => _fetchedGyms = gyms.cast<Map<String, dynamic>>());
      }
    } on ApiException {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _ownerGyms {
    final data = OwnerDataScope.maybeOf(context);
    final scoped = data?.ownerGyms ?? const [];
    return scoped.isNotEmpty ? scoped : _fetchedGyms;
  }

  Future<void> _showAddStaffDialog() async {
    // B8: the owner must see (and pick from) their available gyms before
    // saving a staff account.
    if (_ownerGyms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('staff.noGymsToAssign'))),
      );
      return;
    }
    final payload = await openStaffForm(
      context,
      title: context.tr('staff.addStaff'),
      ownerGyms: _ownerGyms,
    );
    if (payload == null) return;
    if (!mounted) return;
    final api = AppScope.of(context).api;
    try {
      await api.ownerCreateStaff(payload);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('staff.staffAdded'))));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_staffApiErrorMessage(context, e))),
      );
    }
  }

  Future<void> _showEditStaffDialog(Map<String, dynamic> staff) async {
    final payload = await openStaffForm(
      context,
      title: context.tr('staff.editStaff'),
      initial: staff,
      ownerGyms: _ownerGyms,
    );
    if (payload == null) return;
    if (!mounted) return;
    final api = AppScope.of(context).api;
    try {
      await api.ownerUpdateStaff(staff['id'].toString(), payload);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('staff.staffUpdated'))));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_staffApiErrorMessage(context, e))),
      );
    }
  }

  void _confirmRemoveStaff(Map<String, dynamic> staff) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('staff.removeStaff')),
        content: Text(context.tr('staff.confirmRemoveStaff')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final api = AppScope.of(context).api;
              try {
                await api.ownerRemoveStaff(staff['id'].toString());
                if (!mounted) return;
                await _refresh();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('staff.staffRemoved'))),
                );
              } on ApiException catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_staffApiErrorMessage(context, e))),
                );
              }
            },
            child: Text(context.tr('staff.removeStaff')),
          ),
        ],
      ),
    );
  }

  String _scopeLabel(String scope) {
    switch (scope) {
      case 'members':
        return context.tr('owner.members');
      case 'checkins':
        return context.tr('owner.checkin');
      case 'payments':
        return context.tr('owner.earnings');
      case 'trainers':
        return context.tr('owner.trainers');
      case 'gyms':
        return context.tr('owner.manageGyms');
      case 'shop':
        return context.tr('owner.shop');
      default:
        return scope;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/owner/home');
            }
          },
        ),
        title: Text(context.tr('staff.title')),
        actions: const [ThemeToggleButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStaffDialog,
        icon: const Icon(Icons.person_add_alt),
        label: Text(context.tr('staff.addStaff')),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _staff.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  FFEmptyState(
                    title: context.tr('staff.noStaffTitle'),
                    body: context.tr('staff.noStaffBody'),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                itemCount: _staff.length,
                itemBuilder: (ctx, i) {
                  final staff = _staff[i];
                  final permissions = (staff['aclPermissions'] as List? ?? [])
                      .map((e) => _scopeLabel(e.toString()))
                      .join(', ');
                  final suspended = staff['accountStatus'] == 'suspended';
                  return FFCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    staff['displayName']?.toString() ?? '',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (suspended) ...[
                                    const SizedBox(width: 6),
                                    FFBadge(
                                      label: context.tr('staff.suspended'),
                                      tone: FFBadgeTone.warning,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                staff['email']?.toString() ?? '',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                permissions.isEmpty
                                    ? context.tr('staff.noPermissions')
                                    : permissions,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: context.tr('staff.editStaff'),
                          onPressed: () => _showEditStaffDialog(staff),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.person_remove,
                            size: 18,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          tooltip: context.tr('staff.removeStaff'),
                          onPressed: () => _confirmRemoveStaff(staff),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
