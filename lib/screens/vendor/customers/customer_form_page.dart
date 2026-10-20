// Vendor tools · S4: add / edit a customer (spec §4). Walk-in (manual)
// customers are the vendor's own and fully editable. An app (marketplace)
// customer is a name snapshot only (A-02): no phone, email or address
// fields at all; only Note and Archive / Restore.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_options.dart' show fillIn;
import 'customer_models.dart';
import 'customers_widgets.dart';

class CustomerFormPage extends StatefulWidget {
  const CustomerFormPage({super.key, this.customerId});

  /// Null: a new walk-in customer.
  final String? customerId;

  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  Map<String, dynamic>? _customer;
  bool _ready = false;
  bool _saving = false;
  bool _dirty = false;
  CustomerLoadProblem _problem = CustomerLoadProblem.none;
  String? _alert;
  bool _changedElsewhere = false;
  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _archiveError;
  late final String _clientRef = newCustomerClientRef('cus');

  bool get _isNew => widget.customerId == null;
  bool get _app => _customer?['source'] == 'marketplace';
  bool get _archived => _customer?['archived'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final tools = await enterCustomersRoute(context);
    if (tools == null || !mounted) return;
    if (_isNew) {
      setState(() => _ready = true);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _ready = false;
      _problem = CustomerLoadProblem.none;
      _changedElsewhere = false;
      _alert = null;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorCustomer(widget.customerId!);
      final c = res['customer'];
      if (c is! Map) throw ApiException(404, null);
      if (!mounted) return;
      final customer = Map<String, dynamic>.from(c);
      _name.text = customerDisplayName(customer, context.tr);
      _phone.text = customer['phone']?.toString() ?? '';
      _email.text = customer['email']?.toString() ?? '';
      _address.text = customer['address']?.toString() ?? '';
      _note.text = customer['note']?.toString() ?? '';
      setState(() {
        _customer = customer;
        _dirty = false;
        _ready = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _problem = problemOf(e);
          _ready = true;
        });
      }
    }
  }

  void _edited() {
    if (!_dirty || _alert != null) {
      setState(() {
        _dirty = true;
        _alert = null;
      });
    }
  }

  bool _validate() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    setState(() {
      _nameError = _app
          ? null
          : name.isEmpty
          ? context.tr('vendor.customers.nameRequired')
          : name.length < customerNameMin || name.length > customerNameMax
          ? context.tr('vendor.customers.nameLength')
          : null;
      _phoneError = !_app && phone.isNotEmpty && normaliseTzPhone(phone) == null
          ? context.tr('vendor.customers.phoneInvalid')
          : null;
      _emailError = !_app && email.isNotEmpty && !validEmail(email)
          ? context.tr('vendor.customers.emailInvalid')
          : null;
    });
    return _nameError == null && _phoneError == null && _emailError == null;
  }

  Map<String, dynamic> _body() {
    String? v(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    if (_app) return {'note': v(_note)};
    final phone = v(_phone);
    return {
      'name': _name.text.trim(),
      if (_isNew) ...{
        'phone': ?(phone == null ? null : normaliseTzPhone(phone)),
        'email': ?v(_email),
        'address': ?v(_address),
        'note': ?v(_note),
      } else ...{
        'phone': phone == null ? null : normaliseTzPhone(phone),
        'email': v(_email),
        'address': v(_address),
        'note': v(_note),
      },
    };
  }

  Future<void> _save({bool? archived}) async {
    if (_saving) return;
    if (archived == null && !_validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _alert = null;
      _archiveError = null;
    });
    final api = AppScope.of(context).api;
    try {
      final Map<String, dynamic> res;
      if (_isNew) {
        res = await api.vendorCreateCustomer({
          'clientRef': _clientRef,
          ..._body(),
        });
      } else {
        res = await api.vendorUpdateCustomer(widget.customerId!, {
          if (archived == null) ..._body() else 'archived': archived,
          'updatedAt': ?_customer?['updatedAt'],
        });
      }
      if (!mounted) return;
      final c = res['customer'];
      final id = c is Map ? c['id']?.toString() : widget.customerId;
      final dup = res['phoneDuplicate'] is Map
          ? Map<String, dynamic>.from(res['phoneDuplicate'] as Map)
          : null;
      if (c is Map && id != null) {
        CustomerRepository.remember(
          context,
          id,
          customerDisplayName(c, context.tr),
        );
      }
      if (archived != null) {
        setState(() {
          _customer = c is Map ? Map<String, dynamic>.from(c) : _customer;
          _saving = false;
        });
        return;
      }
      FFSnack.success(context, context.tr('vendor.customers.saved'));
      _dirty = false;
      if (_isNew) {
        if (id != null && customerIdPattern.hasMatch(id)) {
          context.pushReplacement(
            customerRoute(id),
            extra: {'phoneDuplicate': ?dup},
          );
        } else {
          context.go(customersHomeRoute);
        }
      } else {
        context.pop({'phoneDuplicate': ?dup});
      }
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      final b = e.body is Map ? e.body as Map : const {};
      setState(() {
        switch (e.code) {
          case 'customer_changed':
            _changedElsewhere = true;
            _alert = context.tr('vendor.customers.changedElsewhere');
          case 'customer_has_balance':
            _archiveError = fillIn(
              context.tr('vendor.customers.archiveHasBalance'),
              {'amount': formatCurrency(intOf(b['owedTzs']))},
            );
          case 'name_invalid':
            _nameError = context.tr('vendor.customers.nameLength');
          case 'address_too_long':
            _alert = fillIn(context.tr('vendor.customers.addressTooLong'), {
              'max': intOf(b['max']) > 0 ? intOf(b['max']) : customerAddressMax,
            });
          case 'note_too_long':
            _alert = fillIn(context.tr('vendor.customers.noteTooLong'), {
              'max': intOf(b['max']) > 0 ? intOf(b['max']) : customerNoteMax,
            });
          case 'field_not_editable':
            _alert = context.tr('vendor.customers.fieldNotEditable');
          case 'phone_invalid':
            _phoneError = context.tr('vendor.customers.phoneInvalid');
          case 'email_invalid':
            _emailError = context.tr('vendor.customers.emailInvalid');
          default:
            _alert = isRateLimited(e)
                ? rateLimitedText(context, e)
                : context.tr(e.status == 403
                  ? 'vendor.customers.noAccess'
                  : 'vendor.saveFailed');
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _alert = context.tr('vendor.customers.saveOffline'));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _archive() async {
    final owed = intOf(_customer?['owedTzs']);
    if (owed > 0) {
      setState(
        () => _archiveError = fillIn(
          context.tr('vendor.customers.archiveHasBalance'),
          {'amount': formatCurrency(owed)},
        ),
      );
      return;
    }
    final ok = await showFFConfirmDialog(
      context,
      title: fillIn(context.tr('vendor.customers.archiveTitle'), {
        'name': customerDisplayName(_customer, context.tr),
      }),
      message: context.tr('vendor.customers.archiveBody'),
      confirmLabel: context.tr('vendor.customers.archive'),
      destructive: true,
      confirmKey: const Key('customer-archive-confirm'),
    );
    if (ok && mounted) await _save(archived: true);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty || _saving) return !_saving;
    return showFFConfirmDialog(
      context,
      title: context.tr('vendor.customers.discardTitle'),
      confirmLabel: context.tr('vendor.sync.discard'),
      destructive: true,
      confirmKey: const Key('customer-discard-confirm'),
    );
  }

  Future<void> _back() async {
    if (!await _confirmDiscard() || !mounted) return;
    _dirty = false;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        _isNew ? customersHomeRoute : customerRoute(widget.customerId!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
          title: Text(
            context.tr(
              _isNew
                  ? 'vendor.customers.newTitle'
                  : 'vendor.customers.editTitle',
            ),
          ),
        ),
        body: !_ready
            ? const Center(child: FFSpinner())
            : _problem != CustomerLoadProblem.none
            ? ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  customerErrorState(
                    context,
                    _problem,
                    failedKey: 'vendor.customers.failed',
                    onRetry: _load,
                  ),
                ],
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.all(FFTokens.spacingLg),
                    children: _fields(),
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _fields() {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return [
      if (_alert != null) ...[
        Semantics(
          liveRegion: true,
          child: FFAlert(
            key: const Key('customer-form-alert'),
            message: _alert!,
            tone: _changedElsewhere ? FFAlertTone.warning : FFAlertTone.error,
          ),
        ),
        if (_changedElsewhere)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FFButton(
              key: const Key('customer-reload'),
              label: context.tr('vendor.customers.reload'),
              variant: FFButtonVariant.ghost,
              visualDensity: VisualDensity.standard,
              onPressed: _load,
            ),
          ),
        const SizedBox(height: FFTokens.spacingSm),
      ],
      if (_archived)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FFBadge(
              label: context.tr('vendor.customers.badge.archived'),
              tone: FFBadgeTone.gray,
            ),
          ),
        ),
      FFTextField(
        key: const Key('customer-name'),
        controller: _name,
        label: context.tr('vendor.customers.name'),
        readOnly: _app,
        enabled: !_saving && !_app,
        maxLength: _app ? null : customerNameMax,
        errorText: _nameError,
        helperText: _app ? context.tr('vendor.customers.appNameHint') : null,
        onChanged: (_) => _edited(),
      ),
      // A-02: an app customer has no contact fields here, not even empty.
      if (!_app) ...[
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: const Key('customer-phone'),
          controller: _phone,
          label: context.tr('vendor.customers.phone'),
          keyboardType: TextInputType.phone,
          enabled: !_saving,
          errorText: _phoneError,
          onChanged: (_) => _edited(),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: const Key('customer-email'),
          controller: _email,
          label: context.tr('vendor.customers.email'),
          keyboardType: TextInputType.emailAddress,
          enabled: !_saving,
          errorText: _emailError,
          onChanged: (_) => _edited(),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: const Key('customer-address'),
          controller: _address,
          label: context.tr('vendor.customers.address'),
          maxLength: customerAddressMax,
          enabled: !_saving,
          onChanged: (_) => _edited(),
        ),
      ] else
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingSm),
          child: Text(
            context.tr('vendor.customers.appContactHint'),
            key: const Key('customer-app-contact-hint'),
            style: muted,
          ),
        ),
      const SizedBox(height: FFTokens.spacingSm),
      FFTextField(
        key: const Key('customer-note'),
        controller: _note,
        label: context.tr('vendor.customers.note'),
        helperText: context.tr('vendor.customers.noteHint'),
        maxLength: customerNoteMax,
        maxLines: 4,
        minLines: 2,
        enabled: !_saving,
        onChanged: (_) => _edited(),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      Text(context.tr('vendor.customers.consent'), style: muted),
      const SizedBox(height: FFTokens.spacingMd),
      FFButton(
        key: const Key('customer-save'),
        label: context.tr('vendor.customers.save'),
        fullWidth: true,
        visualDensity: VisualDensity.standard,
        loading: _saving,
        onPressed: _saving ? null : () => _save(),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFButton(
        label: context.tr('common.cancel'),
        variant: FFButtonVariant.ghost,
        fullWidth: true,
        visualDensity: VisualDensity.standard,
        onPressed: _saving ? null : _back,
      ),
      if (!_isNew) ...[
        const Divider(height: FFTokens.spacingXl),
        if (_archiveError != null)
          Semantics(
            liveRegion: true,
            child: FFAlert(
              key: const Key('customer-archive-error'),
              message: _archiveError!,
              tone: FFAlertTone.warning,
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FFButton(
            key: Key(_archived ? 'customer-restore' : 'customer-archive'),
            label: context.tr(
              _archived
                  ? 'vendor.customers.restore'
                  : 'vendor.customers.archive',
            ),
            icon: _archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            variant: _archived
                ? FFButtonVariant.secondary
                : FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _saving
                ? null
                : _archived
                ? () => _save(archived: false)
                : _archive,
          ),
        ),
      ],
    ];
  }
}
