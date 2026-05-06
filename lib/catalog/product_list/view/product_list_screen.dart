import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:centrkrasok/repositories/products/products.dart';
import 'package:centrkrasok/catalog/category/view/category_screen.dart';
import 'package:centrkrasok/common/menu/menu_screen.dart';




class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {

  List<Product>? _productsList;
  List<Section>? _sectionsList;
  final _productsRepository = ProductsRepository(dio: Dio());

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final (products, sections) = await _productsRepository.getProductsList();

    _productsList = products;
    _sectionsList = sections;

    setState(() {});
  }

  void _menuOpen() {
    if (_sectionsList == null || _productsList == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          sections: _sectionsList!,
          products: _productsList!,
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
          IconButton(
            icon: const Icon(Icons.menu_outlined),
            onPressed: _menuOpen,
          ),
        ],
      ),
      body: (_productsList == null || _sectionsList == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Блок категорий
          Text(
            'Категории',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _sectionsList!.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final section = _sectionsList![i];

              return ListTile(
                title: Text(section.name),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CategoryScreen(
                        section: section,
                        allProducts: _productsList!,
                        allSections: _sectionsList!,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

