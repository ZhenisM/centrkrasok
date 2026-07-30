import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:centrkrasok/repositories/products/products.dart';
import 'package:centrkrasok/catalog/widgets/category_thumbnail.dart';
import 'package:centrkrasok/catalog/category/view/category_screen.dart';
import 'package:centrkrasok/common/menu/menu_screen.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:centrkrasok/common/animated_search_bar.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  List<Section>? _sectionsList;
  String? _error;

  final _productsRepository = ProductsRepository(dio: Dio());

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    try {
      final sections = await _productsRepository.getSections();
      if (!mounted) return;
      setState(() {
        _sectionsList = sections;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _menuOpen() {
    if (_sectionsList == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          sections: _sectionsList!,
          products: const [], // меню без товаров — только разделы
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Каталог'),
        centerTitle: true,
        actions: [
          const CatalogSearchBar(),
          IconButton(
            icon: const Icon(Icons.menu_outlined),
            onPressed: _menuOpen,
          ),
        ],
      ),
      body: switch ((_sectionsList, _error)) {
        (null, null) => const Center(child: CircularProgressIndicator()),
        (_, String err) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 8),
              Text(err, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadSections,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
        (List<Section> sections, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Категории',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sections.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (context, i) {
                  final section = sections[i];
                  return ListTile(
                    leading: CategoryThumbnail(imageUrl: section.image),
                    title: Text(section.name),
                    trailing: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CategoryScreen(
                            section: section,
                            allProducts: const [], // товары грузятся внутри CategoryScreen
                            allSections: sections,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        _ => const SizedBox.shrink(),
      },
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.catalog),
    );
  }
}
