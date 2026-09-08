import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum AppBottomTab { profile, scanner, mic, catalog, cart }

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentTab,
    this.onCartTap,
  });

  final AppBottomTab? currentTab;
  final VoidCallback? onCartTap; // если передан — используется вместо стандартного перехода

  void _goTo(BuildContext context, AppBottomTab tab) {
    if (currentTab == tab) return;
    switch (tab) {
      case AppBottomTab.profile:
        Navigator.of(context).pushReplacementNamed('/profile');
      case AppBottomTab.scanner:
        Navigator.of(context).pushReplacementNamed('/scanner');
      case AppBottomTab.mic:
        break; // заглушка
      case AppBottomTab.catalog:
        Navigator.of(context).pushReplacementNamed('/products-list');
      case AppBottomTab.cart:
        if (onCartTap != null) {
          onCartTap!();
        } else {
          Navigator.of(context).pushReplacementNamed('/cart');
        }
    }
  }

  void _goToCatalog(BuildContext context) => _goTo(context, AppBottomTab.catalog);
  void _goToCart(BuildContext context) => _goTo(context, AppBottomTab.cart);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 1. Профиль
              _NavIcon(
                svgAsset: 'assets/icons/document.svg',
                selected: currentTab == AppBottomTab.profile,
                onTap: () => _goTo(context, AppBottomTab.profile),
              ),
              // 2. Сканер
              _NavIcon(
                svgAsset: 'assets/icons/shtrihcode.svg',
                selected: currentTab == AppBottomTab.scanner,
                onTap: () => _goTo(context, AppBottomTab.scanner),
              ),
              // 3. Микрофон — центральная зелёная кнопка
              GestureDetector(
                onTap: () {},
                child: Container(
                  width: 48, height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 24),
                ),
              ),
              // 4. Каталог
              _NavIcon(
                svgAsset: 'assets/icons/shop.svg',
                selected: currentTab == AppBottomTab.catalog,
                onTap: () => _goToCatalog(context),
              ),
              // Корзина — без бейджа синхронизации (нет очереди без корзины)
              _NavIcon(
                svgAsset: 'assets/icons/shopping-cart.svg',
                selected: currentTab == AppBottomTab.cart,
                onTap: () => _goToCart(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.svgAsset,
    required this.selected,
    required this.onTap,
  });

  final String svgAsset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SvgPicture.asset(
          svgAsset,
          width: 26,
          height: 26,
          colorFilter: ColorFilter.mode(
            selected ? const Color(0xFF4CAF50) : Colors.grey.shade500,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
