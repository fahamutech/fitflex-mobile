import 'package:flutter/material.dart';

import '../../shared/i18n.dart';
import '../../shared/widgets/shop_browse_page.dart';

/// B6/D1 — live shop module for gym owners.
class OwnerShopPage extends StatelessWidget {
  const OwnerShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('owner.shop'))),
      body: const ShopBrowseBody(),
    );
  }
}
