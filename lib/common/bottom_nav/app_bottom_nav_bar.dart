import 'package:flutter/material.dart';

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
                icon: Icons.insert_chart_outlined,
                selected: currentTab == AppBottomTab.profile,
                onTap: () => _goTo(context, AppBottomTab.profile),
              ),
              // 2. Сканер
              _ScannerNavIcon(
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
                icon: Icons.storefront_outlined,
                selected: currentTab == AppBottomTab.catalog,
                onTap: () => _goToCatalog(context),
              ),
              // Корзина — без бейджа синхронизации (нет очереди без корзины)
              _NavIcon(
                icon: Icons.shopping_cart_outlined,
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
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          icon,
          color: selected ? const Color(0xFF4CAF50) : Colors.grey.shade500,
          size: 26,
        ),
      ),
    );
  }
}


// -------------------------------------------------------
// Кастомная иконка сканера QR с уголками
// -------------------------------------------------------
class _ScannerNavIcon extends StatelessWidget {
  const _ScannerNavIcon({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF4CAF50) : Colors.grey.shade500;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: CustomPaint(
          size: const Size(26, 26),
          painter: _QrCornersPainter(color: color),
        ),
      ),
    );
  }
}

class _QrCornersPainter extends CustomPainter {
  const _QrCornersPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    const r = 3.0;
    const L = 7.0;

    canvas.drawPath(Path()
      ..moveTo(0, L)..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: const Radius.circular(r))
      ..lineTo(L, 0), paint);

    canvas.drawPath(Path()
      ..moveTo(w - L, 0)..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
      ..lineTo(w, L), paint);

    canvas.drawPath(Path()
      ..moveTo(w, h - L)..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r))
      ..lineTo(w - L, h), paint);

    canvas.drawPath(Path()
      ..moveTo(L, h)..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r))
      ..lineTo(0, h - L), paint);

    canvas.drawLine(Offset(r + 2, h / 2), Offset(w - r - 2, h / 2),
        paint..strokeWidth = 1.8);
  }

  @override
  bool shouldRepaint(_QrCornersPainter old) => old.color != color;
}
