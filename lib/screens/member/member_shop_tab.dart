import 'package:flutter/material.dart';

import '../../router.dart';
import '../../shared/shop_home.dart';
import '../../shared/widgets/shop_browse_page.dart';

/// D1 — live shop module: browse products, build a cart, place orders.
class MemberShopTab extends StatelessWidget {
  const MemberShopTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const ShopBrowseBody(
      mode: ShopHomeMode.member,
      routePath: AppRoutes.memberShop,
      showHero: true,
    );
  }
}
