import 'package:flutter/material.dart';
import '../../shared/file-export.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/ff_photo_picker_field.dart';

class VendorHomePage extends StatefulWidget {
  const VendorHomePage({super.key});

  @override
  State<VendorHomePage> createState() => _VendorHomePageState();
}

class _VendorHomePageState extends State<VendorHomePage> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _enquiries = [];
  List<Map<String, dynamic>> _staff = [];
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _payments = {};
  bool _loading = true;
  bool _busy = false;
  int _tab = 0;

  bool _can(String permission) {
    final user = AppScope.of(context).auth.user;
    if (user?['userType'] != 'vendor_staff') return true;
    return (user?['vendorPermissions'] as List? ?? []).contains(permission);
  }

  List<int> get _sections {
    final sections = <int>[
      if (_can('products')) 0,
      if (_can('orders')) 1,
      if (_can('payments') || _can('reports')) 2,
      if (_can('customers')) 3,
      if (_can('staff') ||
          AppScope.of(context).auth.user?['userType'] != 'vendor_staff')
        4,
    ];
    return sections.isEmpty ? [5] : sections;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _can('products')
            ? AppScope.of(context).api.vendorProducts()
            : Future<List<dynamic>>.value([]),
        _can('orders')
            ? AppScope.of(context).api.vendorOrders()
            : Future<List<dynamic>>.value([]),
        AppScope.of(context).api.vendorProfile(),
        _can('payments')
            ? AppScope.of(context).api.vendorPayments()
            : Future<Map<String, dynamic>>.value({}),
        _can('customers')
            ? AppScope.of(context).api.vendorEnquiries()
            : Future<List<dynamic>>.value([]),
        _can('staff')
            ? AppScope.of(context).api.vendorStaff()
            : Future<List<dynamic>>.value([]),
      ]);
      if (!mounted) return;
      setState(() {
        _products = (results[0] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        _orders = (results[1] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        _profile = results[2] as Map<String, dynamic>;
        if (_profile['status'] != 'published' &&
            AppScope.of(context).auth.user?['userType'] != 'vendor_staff') {
          _tab = 4;
        }
        _payments = results[3] as Map<String, dynamic>;
        _enquiries = (results[4] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        _staff = (results[5] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('vendor.loadFailed'))));
    }
  }

  Future<void> _editProduct([Map<String, dynamic>? product]) async {
    final draft = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VendorProductForm(product: product),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(
        context,
      ).api.vendorSaveProduct(draft, productId: product?['id']?.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('vendor.productSaved'))),
      );
      await _refresh();
    } on ApiException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('vendor.saveFailed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveProduct(Map<String, dynamic> product) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.vendorSaveProduct({
        'status': product['status'] == 'paused' ? 'active' : 'paused',
      }, productId: product['id']?.toString());
      await _refresh();
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('vendor.saveFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _duplicateProduct(Map<String, dynamic> product) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(
        context,
      ).api.vendorDuplicateProduct(product['id'].toString());
      await _refresh();
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('vendor.saveFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(
        context,
      ).api.vendorDeleteProduct(product['id'].toString());
      await _refresh();
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('vendor.saveFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateOrder(String id, String status) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.vendorUpdateOrderStatus(id, status);
      await _refresh();
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('vendor.saveFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await AppScope.of(context).auth.signOut();
    if (mounted) context.go(AppRoutes.language);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('vendor.title')),
        actions: [
          IconButton(
            key: const Key('vendor-sign-out'),
            tooltip: context.tr('home.signout'),
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: FFSpinner())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: switch (_tab) {
                0 => _productsTab(),
                1 => _ordersTab(),
                2 => _paymentsTab(),
                3 => _enquiriesTab(),
                4 => _businessTab(),
                _ => _restrictedTab(),
              },
            ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              key: const Key('vendor-add-product'),
              onPressed: _busy ? null : () => _editProduct(),
              icon: const Icon(Icons.add),
              label: Text(context.tr('vendor.addProduct')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _sections.indexOf(_tab).clamp(0, _sections.length - 1),
        onDestinationSelected: (index) =>
            setState(() => _tab = _sections[index]),
        destinations: [
          if (_sections.contains(0))
            NavigationDestination(
              key: const Key('vendor-nav-products'),
              icon: const Icon(Icons.inventory_2_outlined),
              selectedIcon: const Icon(Icons.inventory_2),
              label: context.tr('vendor.products'),
            ),
          if (_sections.contains(1))
            NavigationDestination(
              key: const Key('vendor-nav-orders'),
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: context.tr('vendor.orders'),
            ),
          if (_sections.contains(2))
            NavigationDestination(
              key: const Key('vendor-nav-payments'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: const Icon(Icons.account_balance_wallet),
              label: context.tr('vendor.payments'),
            ),
          if (_sections.contains(3))
            NavigationDestination(
              key: const Key('vendor-nav-enquiries'),
              icon: const Icon(Icons.forum_outlined),
              selectedIcon: const Icon(Icons.forum),
              label: context.tr('vendor.enquiries'),
            ),
          if (_sections.contains(4))
            NavigationDestination(
              key: const Key('vendor-nav-business'),
              icon: const Icon(Icons.store_outlined),
              selectedIcon: const Icon(Icons.store),
              label: context.tr('vendor.business'),
            ),
          if (_sections.contains(5))
            NavigationDestination(
              icon: const Icon(Icons.lock_outline),
              label: context.tr('vendor.noAccess'),
            ),
        ],
      ),
    );
  }

  Widget _productsTab() {
    if (_products.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [FFEmptyState(title: context.tr('vendor.noProducts'))],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        final paused = product['status'] == 'paused';
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFCard(
            child: ListTile(
              key: Key('vendor-product-${product['id']}'),
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                child: Icon(Icons.shopping_bag_outlined),
              ),
              title: Text(product['name']?.toString() ?? ''),
              subtitle: Text(
                '${formatCurrency(product['priceTzs'] as num? ?? 0)} · ${product['stock'] ?? 0} ${context.tr('vendor.inStock')}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _editProduct(product);
                  if (value == 'archive') _archiveProduct(product);
                  if (value == 'duplicate') _duplicateProduct(product);
                  if (value == 'delete') _deleteProduct(product);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(context.tr('vendor.edit')),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(
                      paused
                          ? context.tr('vendor.restore')
                          : context.tr('vendor.pause'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'duplicate',
                    child: Text(context.tr('vendor.duplicate')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(context.tr('vendor.delete')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ordersTab() {
    if (_orders.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [FFEmptyState(title: context.tr('vendor.noOrders'))],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final order = _orders[index];
        final status = order['status']?.toString() ?? 'pending';
        final items = (order['items'] as List? ?? [])
            .whereType<Map>()
            .map((item) => '${item['qty']}× ${item['name']}')
            .join(', ');
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(items, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '${formatCurrency(order['totalTzs'] as num? ?? 0)} · ${context.tr('vendor.status')}: $status',
                ),
                Text(
                  '${context.tr('vendor.payment')}: ${order['paymentStatus'] ?? '-'} · ${order['paymentMethod'] ?? '-'}',
                ),
                Text(
                  order['deliveryMethod'] == 'gym_pickup'
                      ? '${context.tr('vendor.pickupGym')}: ${order['pickupGymId'] ?? '-'}'
                      : '${context.tr('vendor.deliveryAddress')}: ${order['deliveryAddress'] ?? '-'}',
                ),
                if (!['delivered', 'cancelled'].contains(status)) ...[
                  const SizedBox(height: FFTokens.spacingSm),
                  Wrap(
                    spacing: FFTokens.spacingSm,
                    children: [
                      FilledButton.tonal(
                        key: Key('vendor-next-${order['id']}'),
                        onPressed: _busy
                            ? null
                            : () => _updateOrder(
                                order['id'].toString(),
                                _nextOrderStatus(order),
                              ),
                        child: Text(
                          '${context.tr('vendor.mark')} ${_nextOrderStatus(order).replaceAll('_', ' ')}',
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _updateOrder(
                                order['id'].toString(),
                                'cancelled',
                              ),
                        child: Text(context.tr('vendor.cancel')),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _nextOrderStatus(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? 'pending';
    if (status == 'pending' || status == 'confirmed') return 'accepted';
    if (status == 'accepted') return 'processing';
    if (status == 'processing') return 'packed';
    if (status == 'packed') {
      return order['deliveryMethod'] == 'gym_pickup'
          ? 'ready_for_pickup'
          : 'dispatched';
    }
    return 'delivered';
  }

  Widget _paymentsTab() {
    final cards = <(String, num)>[
      (
        context.tr('vendor.todaySales'),
        _payments['todaySalesTzs'] as num? ?? 0,
      ),
      (
        context.tr('vendor.weeklySales'),
        _payments['weeklySalesTzs'] as num? ?? 0,
      ),
      (
        context.tr('vendor.monthlySales'),
        _payments['monthlySalesTzs'] as num? ?? 0,
      ),
      (
        context.tr('vendor.pendingSettlement'),
        _payments['pendingSettlementTzs'] as num? ?? 0,
      ),
      (
        context.tr('vendor.settledPayments'),
        _payments['settledPaymentsTzs'] as num? ?? 0,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFCard(
              child: ListTile(
                title: Text(card.$1),
                trailing: Text(
                  formatCurrency(card.$2),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        OutlinedButton.icon(
          key: const Key('vendor-download-statement'),
          onPressed: () async {
            try {
              final statement = await AppScope.of(
                context,
              ).api.vendorStatement();
              await saveTextExport(
                filename: 'fitflex-vendor-statement.csv',
                content: statement,
                mimeType: 'text/csv',
              );
            } catch (_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('shop.exportFailed'))),
              );
            }
          },
          icon: const Icon(Icons.download_outlined),
          label: Text(context.tr('vendor.downloadStatement')),
        ),
      ],
    );
  }

  Widget _enquiriesTab() {
    if (_enquiries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [FFEmptyState(title: context.tr('vendor.noEnquiries'))],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      itemCount: _enquiries.length,
      itemBuilder: (context, index) {
        final enquiry = _enquiries[index];
        final messages = (enquiry['messages'] as List? ?? [])
            .whereType<Map>()
            .toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  messages.isEmpty ? '' : messages.first['message'].toString(),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text('${context.tr('vendor.status')}: ${enquiry['status']}'),
                if (messages.length > 1)
                  Text(
                    '${context.tr('vendor.reply')}: ${messages.last['message']}',
                  ),
                Wrap(
                  children: [
                    TextButton(
                      key: Key('vendor-reply-${enquiry['id']}'),
                      onPressed: () => _replyEnquiry(enquiry),
                      child: Text(context.tr('vendor.reply')),
                    ),
                    if (enquiry['status'] != 'resolved')
                      TextButton(
                        onPressed: () async {
                          await AppScope.of(
                            context,
                          ).api.vendorResolveEnquiry(enquiry['id'].toString());
                          await _refresh();
                        },
                        child: Text(context.tr('vendor.resolve')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _replyEnquiry(Map<String, dynamic> enquiry) async {
    final controller = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('vendor.reply')),
        content: TextField(
          key: const Key('vendor-reply-message'),
          controller: controller,
          maxLines: 3,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('shop.send')),
          ),
        ],
      ),
    );
    if (send == true && controller.text.trim().isNotEmpty && mounted) {
      await AppScope.of(context).api.vendorReplyEnquiry(
        enquiry['id'].toString(),
        controller.text.trim(),
      );
      await _refresh();
    }
    controller.dispose();
  }

  Widget _businessTab() {
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _profile['businessName']?.toString() ??
                    context.tr('vendor.profileIncomplete'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${context.tr('vendor.status')}: ${_profile['status'] ?? 'draft'}',
              ),
              Text(_profile['description']?.toString() ?? ''),
              const SizedBox(height: FFTokens.spacingSm),
              if (AppScope.of(context).auth.user?['userType'] != 'vendor_staff')
                Wrap(
                  spacing: FFTokens.spacingSm,
                  runSpacing: FFTokens.spacingSm,
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('vendor-edit-profile'),
                      onPressed: _editProfile,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(context.tr('vendor.editProfile')),
                    ),
                    OutlinedButton.icon(
                      key: const Key('vendor-verification'),
                      onPressed: () => context.push('/verification'),
                      icon: const Icon(Icons.verified_user_outlined),
                      label: Text(context.tr('kyc.entry.title')),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: FFTokens.spacingLg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.tr('vendor.staff'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton.icon(
              key: const Key('vendor-add-staff'),
              onPressed: _addStaff,
              icon: const Icon(Icons.person_add_alt),
              label: Text(context.tr('vendor.addStaff')),
            ),
          ],
        ),
        for (final staff in _staff)
          FFCard(
            child: ListTile(
              title: Text(staff['displayName']?.toString() ?? ''),
              subtitle: Text('${staff['vendorRole']} · ${staff['email']}'),
              trailing: staff['accountStatus'] == 'suspended'
                  ? Text(context.tr('vendor.disabled'))
                  : TextButton(
                      onPressed: () async {
                        await AppScope.of(
                          context,
                        ).api.vendorDisableStaff(staff['id'].toString());
                        await _refresh();
                      },
                      child: Text(context.tr('vendor.disable')),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _restrictedTab() {
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [FFEmptyState(title: context.tr('vendor.noAccess'))],
    );
  }

  Future<void> _editProfile() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VendorProfileForm(profile: _profile),
    );
    if (result == null || !mounted) return;
    await AppScope.of(context).api.vendorSaveProfile(result);
    await _refresh();
  }

  Future<void> _addStaff() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const VendorStaffForm(),
    );
    if (result == null || !mounted) return;
    await AppScope.of(context).api.vendorCreateStaff(result);
    await _refresh();
  }
}

class VendorProductForm extends StatefulWidget {
  const VendorProductForm({super.key, this.product});

  final Map<String, dynamic>? product;

  @override
  State<VendorProductForm> createState() => _VendorProductFormState();
}

class _VendorProductFormState extends State<VendorProductForm> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _brand;
  late final TextEditingController _price;
  late final TextEditingController _discountPrice;
  late final TextEditingController _stock;
  late final TextEditingController _sku;
  late final TextEditingController _weight;
  late final TextEditingController _variants;
  String? _image;
  String? _secondImage;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?['name']?.toString());
    _description = TextEditingController(
      text: product?['description']?.toString(),
    );
    _category = TextEditingController(text: product?['category']?.toString());
    _brand = TextEditingController(text: product?['brand']?.toString());
    _price = TextEditingController(text: product?['priceTzs']?.toString());
    _discountPrice = TextEditingController(
      text: product?['discountPriceTzs']?.toString(),
    );
    _stock = TextEditingController(text: product?['stock']?.toString());
    _sku = TextEditingController(text: product?['sku']?.toString());
    _weight = TextEditingController(text: product?['weightKg']?.toString());
    _variants = TextEditingController(
      text: (product?['variants'] as List? ?? [])
          .whereType<Map>()
          .map((item) => item['name'])
          .join(', '),
    );
    final images = (product?['images'] as List?)?.whereType<String>().toList();
    _image = images?.firstOrNull;
    _secondImage = images != null && images.length > 1 ? images[1] : null;
    _visible = product?['visibility'] != 'hidden';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _category.dispose();
    _brand.dispose();
    _price.dispose();
    _discountPrice.dispose();
    _stock.dispose();
    _sku.dispose();
    _weight.dispose();
    _variants.dispose();
    super.dispose();
  }

  void _submit() {
    final price = num.tryParse(_price.text.trim());
    if (_name.text.trim().isEmpty || price == null || price <= 0) return;
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category': _category.text.trim(),
      'brand': _brand.text.trim(),
      'priceTzs': price,
      'discountPriceTzs': num.tryParse(_discountPrice.text.trim()),
      'stock': int.tryParse(_stock.text.trim()) ?? 0,
      'sku': _sku.text.trim(),
      'weightKg': num.tryParse(_weight.text.trim()),
      'variants': _variants.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .map((value) => {'name': value})
          .toList(),
      'visibility': _visible ? 'visible' : 'hidden',
      'images': [
        if (_image != null) _image,
        if (_secondImage != null) _secondImage,
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: FFTokens.spacingLg,
          right: FFTokens.spacingLg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + FFTokens.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.product == null
                    ? context.tr('vendor.addProduct')
                    : context.tr('vendor.editProduct'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FFPhotoPickerField(
                      value: _image,
                      onChanged: (value) => setState(() => _image = value),
                    ),
                    const SizedBox(width: FFTokens.spacingMd),
                    FFPhotoPickerField(
                      value: _secondImage,
                      onChanged: (value) =>
                          setState(() => _secondImage = value),
                    ),
                  ],
                ),
              ),
              TextField(
                key: const Key('vendor-product-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.name'),
                ),
              ),
              TextField(
                key: const Key('vendor-product-brand'),
                controller: _brand,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.brand'),
                ),
              ),
              TextField(
                key: const Key('vendor-product-description'),
                controller: _description,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.description'),
                ),
              ),
              TextField(
                key: const Key('vendor-product-category'),
                controller: _category,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.category'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('vendor-product-price'),
                      controller: _price,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('vendor.price'),
                      ),
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingMd),
                  Expanded(
                    child: TextField(
                      key: const Key('vendor-product-stock'),
                      controller: _stock,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('vendor.stock'),
                      ),
                    ),
                  ),
                ],
              ),
              TextField(
                key: const Key('vendor-product-discount-price'),
                controller: _discountPrice,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.discountPrice'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('vendor-product-sku'),
                      controller: _sku,
                      decoration: InputDecoration(
                        labelText: context.tr('vendor.sku'),
                      ),
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingMd),
                  Expanded(
                    child: TextField(
                      key: const Key('vendor-product-weight'),
                      controller: _weight,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('vendor.weight'),
                      ),
                    ),
                  ),
                ],
              ),
              TextField(
                key: const Key('vendor-product-variants'),
                controller: _variants,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.variants'),
                  hintText: context.tr('vendor.variantsHint'),
                ),
              ),
              SwitchListTile(
                key: const Key('vendor-product-visibility'),
                contentPadding: EdgeInsets.zero,
                value: _visible,
                onChanged: (value) => setState(() => _visible = value),
                title: Text(context.tr('vendor.visible')),
              ),
              const SizedBox(height: FFTokens.spacingLg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('vendor-product-save'),
                  onPressed: _submit,
                  child: Text(context.tr('vendor.save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VendorProfileForm extends StatefulWidget {
  const VendorProfileForm({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<VendorProfileForm> createState() => _VendorProfileFormState();
}

class _VendorProfileFormState extends State<VendorProfileForm> {
  late final Map<String, TextEditingController> _fields;
  String? _logo;
  String? _banner;

  @override
  void initState() {
    super.initState();
    String value(String key) {
      final raw = widget.profile[key];
      if (raw is List) return raw.join(', ');
      if (raw is Map) return raw.values.join(', ');
      return raw?.toString() ?? '';
    }

    _fields = {
      for (final key in [
        'businessName',
        'description',
        'businessCategory',
        'contactNumber',
        'email',
        'address',
        'deliveryRegions',
        'businessHours',
        'settlementAccount',
      ])
        key: TextEditingController(text: value(key)),
    };
    _logo = widget.profile['logo']?.toString();
    _banner = widget.profile['banner']?.toString();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_logo == null || _banner == null) return;
    if (_fields.values.any((controller) => controller.text.trim().isEmpty)) {
      return;
    }
    Navigator.pop(context, {
      'businessName': _fields['businessName']!.text.trim(),
      'logo': _logo,
      'banner': _banner,
      'description': _fields['description']!.text.trim(),
      'businessCategory': _fields['businessCategory']!.text.trim(),
      'contactNumber': _fields['contactNumber']!.text.trim(),
      'email': _fields['email']!.text.trim(),
      'address': _fields['address']!.text.trim(),
      'deliveryRegions': _fields['deliveryRegions']!.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      'businessHours': {'summary': _fields['businessHours']!.text.trim()},
      'settlementAccount': {
        'account': _fields['settlementAccount']!.text.trim(),
      },
      'publish': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    final labels = {
      'businessName': context.tr('vendor.businessName'),
      'description': context.tr('vendor.businessDescription'),
      'businessCategory': context.tr('vendor.businessCategory'),
      'contactNumber': context.tr('vendor.contactNumber'),
      'email': context.tr('vendor.email'),
      'address': context.tr('vendor.address'),
      'deliveryRegions': context.tr('vendor.deliveryRegions'),
      'businessHours': context.tr('vendor.businessHours'),
      'settlementAccount': context.tr('vendor.settlementAccount'),
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          MediaQuery.viewInsetsOf(context).bottom + FFTokens.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('vendor.editProfile'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Text(context.tr('vendor.logo')),
                      FFPhotoPickerField(
                        value: _logo,
                        onChanged: (value) => setState(() => _logo = value),
                      ),
                    ],
                  ),
                  const SizedBox(width: FFTokens.spacingMd),
                  Column(
                    children: [
                      Text(context.tr('vendor.banner')),
                      FFPhotoPickerField(
                        value: _banner,
                        onChanged: (value) => setState(() => _banner = value),
                      ),
                    ],
                  ),
                ],
              ),
              for (final entry in _fields.entries)
                TextField(
                  key: Key('vendor-profile-${entry.key}'),
                  controller: entry.value,
                  decoration: InputDecoration(labelText: labels[entry.key]),
                ),
              const SizedBox(height: FFTokens.spacingLg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('vendor-profile-publish'),
                  onPressed: _submit,
                  child: Text(context.tr('vendor.publishProfile')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VendorStaffForm extends StatefulWidget {
  const VendorStaffForm({super.key});

  @override
  State<VendorStaffForm> createState() => _VendorStaffFormState();
}

class _VendorStaffFormState extends State<VendorStaffForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'inventory_manager';
  final Set<String> _permissions = {'products'};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if ([
      _name,
      _email,
      _phone,
      _password,
    ].any((controller) => controller.text.trim().isEmpty)) {
      return;
    }
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'password': _password.text,
      'role': _role,
      'permissions': _permissions.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    const permissions = [
      'products',
      'orders',
      'customers',
      'reports',
      'payments',
      'staff',
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          MediaQuery.viewInsetsOf(context).bottom + FFTokens.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('vendor.addStaff'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextField(
                key: const Key('vendor-staff-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.staffName'),
                ),
              ),
              TextField(
                key: const Key('vendor-staff-email'),
                controller: _email,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.email'),
                ),
              ),
              TextField(
                key: const Key('vendor-staff-phone'),
                controller: _phone,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.phone'),
                ),
              ),
              TextField(
                key: const Key('vendor-staff-password'),
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.password'),
                ),
              ),
              DropdownButtonFormField<String>(
                key: const Key('vendor-staff-role'),
                initialValue: _role,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.role'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text(context.tr('vendor.roleAdmin')),
                  ),
                  DropdownMenuItem(
                    value: 'inventory_manager',
                    child: Text(context.tr('vendor.roleInventory')),
                  ),
                  DropdownMenuItem(
                    value: 'orders_manager',
                    child: Text(context.tr('vendor.roleOrders')),
                  ),
                  DropdownMenuItem(
                    value: 'sales',
                    child: Text(context.tr('vendor.roleSales')),
                  ),
                  DropdownMenuItem(
                    value: 'customer_care',
                    child: Text(context.tr('vendor.roleCare')),
                  ),
                ],
                onChanged: (value) => setState(() => _role = value ?? _role),
              ),
              for (final permission in permissions)
                CheckboxListTile(
                  dense: true,
                  value: _permissions.contains(permission),
                  title: Text(context.tr('vendor.permission.$permission')),
                  onChanged: (selected) => setState(() {
                    if (selected == true) {
                      _permissions.add(permission);
                    } else {
                      _permissions.remove(permission);
                    }
                  }),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('vendor-staff-save'),
                  onPressed: _submit,
                  child: Text(context.tr('vendor.saveStaff')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
