// Vendor tools · S4: the POS customer picker (spec §3.2) and its quick-add
// (name + phone). Server search, 300 ms debounce. Staff with `sales` only
// get names and phone endings, never amounts (the server omits them).
// Archived customers are never offered. Offline: nothing selectable (no
// customer data is kept on the device).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_options.dart';
import 'customer_models.dart';
import 'customers_widgets.dart';

/// A customer chosen for a sale. [owedTzs] / [overdueTzs] only for
/// people with `customers` (null otherwise).
class PickedCustomer {
  const PickedCustomer({
    required this.id,
    required this.name,
    this.owedTzs,
    this.overdueTzs,
  });

  final String id;
  final String name;
  final int? owedTzs;
  final int? overdueTzs;
}

/// Opens the picker; answers the chosen customer, or null.
Future<PickedCustomer?> pickCustomer(BuildContext context) =>
    showFFSheet<PickedCustomer>(
      context,
      title: context.tr('vendor.pos.customer.pick'),
      child: const CustomerPicker(),
    );

class CustomerPicker extends StatefulWidget {
  const CustomerPicker({super.key});

  @override
  State<CustomerPicker> createState() => _CustomerPickerState();
}

enum _State { loading, ready, offline, failed }

class _CustomerPickerState extends State<CustomerPicker> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [];
  _State _state = _State.loading;
  bool _adding = false;
  bool _saving = false;
  String? _nameError;
  String? _phoneError;
  String? _addProblem;
  int _ask = 0;
  late final String _addRef = newCustomerClientRef('cus');

  bool get _seesMoney => canVendor(context, 'customers');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    final ask = ++_ask;
    setState(() => _state = _State.loading);
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorCustomers(q: _search.text, limit: 30);
      if (!mounted || ask != _ask) return;
      setState(() {
        _rows = [
          for (final r in (res['customers'] as List? ?? []).whereType<Map>())
            // Never offered, even if a server sent one.
            if (r['archived'] != true) Map<String, dynamic>.from(r),
        ];
        _state = _State.ready;
      });
    } on ApiException {
      if (mounted && ask == _ask) setState(() => _state = _State.failed);
    } catch (_) {
      if (mounted && ask == _ask) setState(() => _state = _State.offline);
    }
  }

  void _choose(Map<String, dynamic> c) {
    final name = customerDisplayName(c, context.tr);
    final id = c['id'].toString();
    CustomerRepository.remember(context, id, name);
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(
      PickedCustomer(
        id: id,
        name: name,
        owedTzs: _seesMoney ? intOf(c['owedTzs']) : null,
        overdueTzs: _seesMoney ? intOf(c['overdueTzs']) : null,
      ),
    );
  }

  Future<void> _quickAdd() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    String? nameError;
    String? phoneError;
    if (name.isEmpty) {
      nameError = context.tr('vendor.customers.nameRequired');
    } else if (name.length < customerNameMin || name.length > customerNameMax) {
      nameError = context.tr('vendor.customers.nameLength');
    }
    if (phone.isNotEmpty && normaliseTzPhone(phone) == null) {
      phoneError = context.tr('vendor.customers.phoneInvalid');
    }
    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
      _addProblem = null;
    });
    if (nameError != null || phoneError != null || _saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      final res = await AppScope.of(context).api.vendorCreateCustomer({
        'clientRef': _addRef,
        'name': name,
        if (phone.isNotEmpty) 'phone': normaliseTzPhone(phone),
      });
      if (!mounted) return;
      final c = res['customer'];
      if (c is! Map) throw StateError('no customer');
      final dup = res['phoneDuplicate'];
      if (dup is Map) {
        FFSnack.warning(
          context,
          fillIn(context.tr('vendor.customers.phoneDuplicate'), {
            'name': customerDisplayName(dup, context.tr),
          }),
        );
      }
      _choose({...Map<String, dynamic>.from(c), 'owedTzs': 0});
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'name_invalid':
            _nameError = context.tr('vendor.customers.nameLength');
          case 'phone_invalid':
            _phoneError = context.tr('vendor.customers.phoneInvalid');
          default:
            _addProblem = isRateLimited(e)
                ? rateLimitedText(context, e)
                : context.tr(e.status == 403
                  ? 'vendor.customers.noAccess'
                  : 'vendor.saveFailed');
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _addProblem = context.tr('vendor.customers.saveOffline'),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_adding) return _addForm();
    final web = MediaQuery.sizeOf(context).width >= 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFTextField(
          key: const Key('picker-search'),
          controller: _search,
          label: context.tr('vendor.customers.search'),
          hint: context.tr('vendor.customers.searchHint'),
          prefixIcon: const Icon(Icons.search),
          autofocus: web,
          onChanged: _onSearch,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        if (_state == _State.offline)
          FFAlert(
            key: const Key('picker-offline'),
            message: context.tr('vendor.pos.customer.offline'),
            tone: FFAlertTone.warning,
          )
        else ...[
          _tile(
            key: const Key('picker-new'),
            icon: Icons.person_add_alt,
            title: context.tr('vendor.pos.customer.new'),
            onTap: () => setState(() => _adding = true),
          ),
          if (_state == _State.loading)
            FFSkeletonList(
              semanticLabel: context.tr('vendor.customers.loading'),
            )
          else if (_state == _State.failed)
            FFErrorState(
              message: context.tr('vendor.customers.failed'),
              onRetry: _load,
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              child: Text(
                _search.text.trim().isEmpty
                    ? context.tr('vendor.customers.empty')
                    : fillIn(context.tr('vendor.customers.noMatch'), {
                        'q': _search.text.trim(),
                      }),
                key: const Key('picker-empty'),
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final c in _rows) _row(c),
        ],
      ],
    );
  }

  Widget _tile({
    Key? key,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? extra,
    required VoidCallback onTap,
    String? semantics,
  }) => Semantics(
    button: true,
    label: semantics,
    excludeSemantics: semantics != null,
    child: ListTile(
      key: key,
      minTileHeight: 56,
      leading: Icon(icon),
      title: Text(title),
      // Money and badges go under the name (they wrap at large text),
      // never in a fixed-height trailing slot.
      subtitle: subtitle == null && extra == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [?(subtitle == null ? null : Text(subtitle)), ?extra],
            ),
      onTap: onTap,
    ),
  );

  Widget _row(Map<String, dynamic> c) {
    final name = customerDisplayName(c, context.tr);
    final ending = phoneEnding(c);
    final source = context.tr(
      c['source'] == 'marketplace'
          ? 'vendor.customers.badge.app'
          : 'vendor.customers.badge.shop',
    );
    final owed = _seesMoney ? intOf(c['owedTzs']) : 0;
    final overdue = _seesMoney && intOf(c['overdueTzs']) > 0;
    final theme = Theme.of(context);
    return _tile(
      key: Key('picker-row-${c['id']}'),
      icon: Icons.person_outline,
      title: name,
      subtitle: [source, ?ending].join(' · '),
      semantics: [
        name,
        source,
        ?ending,
        if (owed > 0)
          fillIn(context.tr('vendor.sales.owesBadge'), {
            'amount': formatCurrency(owed),
          }),
        if (overdue) context.tr('vendor.customers.overdueBadge'),
      ].join(', '),
      extra: owed > 0
          ? Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Wrap(
                spacing: FFTokens.spacingXs,
                runSpacing: FFTokens.spacingXs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    fillIn(context.tr('vendor.sales.owesBadge'), {
                      'amount': formatCurrency(owed),
                    }),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (overdue) overdueBadge(context),
                ],
              ),
            )
          : null,
      onTap: () => _choose(c),
    );
  }

  Widget _addForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('vendor.pos.customer.new'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFTextField(
        key: const Key('picker-add-name'),
        controller: _name,
        label: context.tr('vendor.customers.name'),
        maxLength: customerNameMax,
        errorText: _nameError,
        enabled: !_saving,
        autofocus: true,
      ),
      FFTextField(
        key: const Key('picker-add-phone'),
        controller: _phone,
        label: context.tr('vendor.customers.phone'),
        keyboardType: TextInputType.phone,
        errorText: _phoneError,
        enabled: !_saving,
      ),
      const SizedBox(height: FFTokens.spacingSm),
      Text(
        context.tr('vendor.customers.consent'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (_addProblem != null) ...[
        const SizedBox(height: FFTokens.spacingSm),
        Semantics(
          liveRegion: true,
          child: FFAlert(
            key: const Key('picker-add-problem'),
            message: _addProblem!,
            tone: FFAlertTone.error,
          ),
        ),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      FFButton(
        key: const Key('picker-add-save'),
        label: context.tr('vendor.customers.save'),
        fullWidth: true,
        visualDensity: VisualDensity.standard,
        loading: _saving,
        onPressed: _quickAdd,
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFButton(
        label: context.tr('common.cancel'),
        variant: FFButtonVariant.ghost,
        fullWidth: true,
        visualDensity: VisualDensity.standard,
        onPressed: _saving ? null : () => setState(() => _adding = false),
      ),
    ],
  );
}
