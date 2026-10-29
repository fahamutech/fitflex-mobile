import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/staff_form_page.dart';
import 'owner_shell.dart';
import '../../shared/widgets/invitations.dart';

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

/// Message for a refused staff PIN reset (fitflex-functions#260).
String staffPinResetErrorMessage(BuildContext context, Object error) {
  final code = error is ApiException ? error.code : null;
  final key = switch (code) {
    'pin_must_be_4_digits' => 'auth.pinExactlyFour',
    'staff_identity_shared' => 'staff.errIdentityShared',
    'credentials_not_accepted' => 'staff.errCredentialsNotAccepted',
    'feature_disabled' => 'staff.errResetOff',
    'staff_not_at_your_gym' => 'staff.errNotYourStaff',
    'staff_not_found' => 'staff.errStaffNotFound',
    'firebase_update_failed' => 'staff.errResetNotSaved',
    _ => null,
  };
  return key != null
      ? context.tr(key)
      : errorMessage(FFLocaleScope.of(context), error);
}

/// True when the server reports PIN holds on staff rows, which it does only
/// while STAFF_PIN_CHANGE_REQUIRED is on (fitflex-functions#260). With the
/// field absent the page stays as it was.
bool staffPinResetAvailable(Map<String, dynamic> staff) =>
    staff.containsKey('passwordChangeRequired');

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
    // AppScope is read in _refresh: not from initState itself.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
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
      FFSnack.info(context, context.tr('staff.noGymsToAssign'));
      return;
    }
    // Identity V2: staff are invited and sign in with their own account.
    if (AppScope.of(context).auth.invitesEnabled) {
      final gymId =
          OwnerDataScope.maybeOf(context)?.activeGymId ??
          _ownerGyms.first['id'].toString();
      await openInvitePersonSheet(context, gymId: gymId, role: 'staff');
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
      FFSnack.error(context, _staffApiErrorMessage(context, e));
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
      FFSnack.error(context, _staffApiErrorMessage(context, e));
    }
  }

  /// The owner gives a staff member a new starting PIN; the staff member is
  /// signed out and must choose their own at the next sign-in.
  Future<void> _resetStaffPin(Map<String, dynamic> staff) async {
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ResetStaffPinDialog(staff: staff),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _staff = [
        for (final s in _staff) s['id'] == staff['id'] ? {...s, ...updated} : s,
      ];
    });
    FFSnack.success(
      context,
      context
          .tr('staff.resetPinDone')
          .replaceAll('{name}', staff['displayName']?.toString() ?? ''),
    );
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
                FFSnack.success(context, context.tr('staff.staffRemoved'));
              } on ApiException catch (e) {
                if (!mounted) return;
                FFSnack.error(context, _staffApiErrorMessage(context, e));
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
          tooltip: context.tr('a11y.back'),
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
        actions: const [AppPrefsButtons()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStaffDialog,
        icon: const Icon(Icons.person_add_alt),
        label: Text(context.tr('staff.addStaff')),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: FFSpinner(size: 32))
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
                  final mustChangePin = staff['passwordChangeRequired'] == true;
                  final canResetPin =
                      staffPinResetAvailable(staff) &&
                      !AppScope.of(context).auth.invitesEnabled;
                  return FFCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    staff['displayName']?.toString() ?? '',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (suspended)
                                    FFBadge(
                                      label: context.tr('staff.suspended'),
                                      tone: FFBadgeTone.warning,
                                    ),
                                  if (mustChangePin)
                                    FFBadge(
                                      key: Key(
                                        'staff-must-change-pin-${staff['id']}',
                                      ),
                                      label: context.tr('staff.mustChangePin'),
                                      tone: FFBadgeTone.brand,
                                      wrap: true,
                                    ),
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
                        if (canResetPin)
                          IconButton(
                            key: Key('staff-reset-pin-${staff['id']}'),
                            icon: const Icon(Icons.lock_reset, size: 18),
                            tooltip: context.tr('staff.resetPin'),
                            onPressed: () => _resetStaffPin(staff),
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

/// Owner sets a new starting PIN for a staff member (they forgot theirs).
/// Says what happens next, takes the PIN twice and sends it; the dialog
/// stays open with the reason when the server refuses.
class _ResetStaffPinDialog extends StatefulWidget {
  const _ResetStaffPinDialog({required this.staff});

  final Map<String, dynamic> staff;

  @override
  State<_ResetStaffPinDialog> createState() => _ResetStaffPinDialogState();
}

class _ResetStaffPinDialogState extends State<_ResetStaffPinDialog> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) {
      setState(() => _error = context.tr('auth.pinExactlyFour'));
      return;
    }
    if (_pin.text != _again.text) {
      setState(() => _error = context.tr('auth.pinMismatch'));
      return;
    }
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await api.ownerResetStaffPin(
        widget.staff['id'].toString(),
        _pin.text,
      );
      navigator.pop(Map<String, dynamic>.from(row));
    } catch (e) {
      if (mounted) {
        setState(() => _error = staffPinResetErrorMessage(context, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, TextEditingController c, String label) => TextField(
    key: Key(key),
    controller: c,
    obscureText: true,
    enabled: !_busy,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    maxLength: 4,
    decoration: InputDecoration(labelText: label, counterText: ''),
  );

  @override
  Widget build(BuildContext context) {
    final name = widget.staff['displayName']?.toString() ?? '';
    return AlertDialog(
      key: const Key('staff-reset-pin-dialog'),
      title: Text(context.tr('staff.resetPin')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('staff.resetPinBody').replaceAll('{name}', name),
              key: const Key('staff-reset-pin-body'),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            _field(
              'staff-reset-pin-new',
              _pin,
              context.tr('staff.newStartPin'),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            _field(
              'staff-reset-pin-again',
              _again,
              context.tr('pin.confirmTitle'),
            ),
            if (_error != null) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                _error!,
                key: const Key('staff-reset-pin-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('member.cancel')),
        ),
        FilledButton(
          key: const Key('staff-reset-pin-save'),
          onPressed: _busy ? null : _save,
          child: Text(context.tr('staff.resetPin')),
        ),
      ],
    );
  }
}
