import 'package:flutter/material.dart';
import 'package:centrkrasok/repositories/products/products.dart';
import 'package:centrkrasok/catalog/product_list/widgets/product_tile.dart';
import 'package:centrkrasok/common/menu/menu_screen.dart';

class CategoryScreen extends StatelessWidget {
  final Section section;
  final List<Product> allProducts;
  final List<Section> allSections;

  const CategoryScreen({
    super.key,
    required this.section,
    required this.allProducts,
    required this.allSections,
  });

  void _menuOpen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          sections: allSections,
          products: allProducts,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final products = _filterProducts(section);

    return Scaffold(
      appBar: AppBar(
        title: Text(section.name),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_outlined),
            onPressed: () => _menuOpen(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          /// 🔹 Подкатегории
          if (section.children.isNotEmpty) ...[
            Text(
              'Подкатегории',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),

            ...section.children.map((child) {
              return ListTile(
                title: Text(child.name),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CategoryScreen(
                        section: child,
                        allProducts: allProducts,
                        allSections: allSections,
                      ),
                    ),
                  );
                },
              );
            }),

            const SizedBox(height: 16),
          ],

          /// 🔹 Товары
          Text(
            'Товары',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),

          ...products.map((p) => ProductTile(product: p)),
        ],
      ),
    );
  }

  /// 🔥 Фильтрация товаров по категории
  List<Product> _filterProducts(Section section) {
    // ВАЖНО: тут зависит от структуры твоего Product
    // предположим есть product.sectionId

    final ids = _collectIds(section);

    return allProducts.where((p) => ids.contains(p.sectionId)).toList();
  }

  /// собираем все вложенные id
  List<String> _collectIds(Section section) {
    final result = <String>[];

    void traverse(Section s) {
      result.add(s.id);
      for (final c in s.children) {
        traverse(c);
      }
    }

    traverse(section);
    return result;
  }
}