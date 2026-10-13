import 'package:flutter/material.dart';

import '../../shared/widgets/shop_browse_page.dart';

/// B6/D1 — live shop module for gym owners. A bottom-nav tab: the shell
/// supplies the app bar, so this is just the body.
class OwnerShopPage extends StatelessWidget {
  const OwnerShopPage({super.key});

  @override
  Widget build(BuildContext context) => const ShopBrowseBody();
}
