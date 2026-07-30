import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:centrkrasok/catalog/category/view/category_screen.dart';
import 'package:centrkrasok/catalog/widgets/category_thumbnail.dart';
import 'package:centrkrasok/repositories/products/products.dart';

class MenuScreen extends StatelessWidget {
  final List<Section> sections;
  final List<Product> products;

  const MenuScreen({
    super.key,
    required this.sections,
    required this.products,
  });

  void _goTo(BuildContext context, String route) {
    Navigator.pop(context);
    Navigator.pushNamed(context, route);
  }

  void _openCatalogSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (sheetCtx, ctrl) => Column(children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              const Text('Каталог',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(sheetCtx),
              ),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              controller: ctrl,
              itemCount: sections.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (ctx, i) {
                final section = sections[i];
                return ListTile(
                  leading: CategoryThumbnail(imageUrl: section.image, size: 36),
                  title: Text(section.name,
                    style: const TextStyle(fontSize: 15)),
                  trailing: const Icon(Icons.arrow_forward_ios,
                    size: 14, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(sheetCtx); // закрываем sheet
                    Navigator.pop(context);  // закрываем меню
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryScreen(
                          section: section,
                          allProducts: products,
                          allSections: sections,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Меню'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          _MenuItem(
            icon: Icons.home_outlined,
            label: 'На главную',
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(
                context, '/', (route) => false);
            },
          ),

          _divider(),

          _MenuItem(
            icon: Icons.storefront_outlined,
            label: 'Каталог',
            trailing: const Icon(Icons.arrow_forward_ios,
              size: 14, color: Colors.grey),
            onTap: () => _openCatalogSheet(context),
          ),

          _divider(),

          _MenuItem(
            svgAsset: 'assets/icons/heart.svg',
            label: 'Избранное',
            onTap: () => _goTo(context, '/favorites'),
          ),

          _divider(),

          _MenuItem(
            svgAsset: 'assets/icons/compare.svg',
            label: 'Сравнение',
            onTap: () => _goTo(context, '/compare'),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.grey.shade100, indent: 16, endIndent: 16);
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    this.svgAsset,
    this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  final String? svgAsset;
  final IconData? icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconWidget = svgAsset != null
        ? SvgPicture.asset(svgAsset!,
            width: 22, height: 22,
            colorFilter: const ColorFilter.mode(
              Colors.black54, BlendMode.srcIn))
        : Icon(icon, size: 22, color: Colors.black54);

    return ListTile(
      leading: iconWidget,
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
