import 'package:flutter/material.dart';
import 'package:centrkrasok/catalog/category/view/category_screen.dart';
import 'package:centrkrasok/repositories/products/products.dart';

class MenuScreen extends StatelessWidget {
  final List<Section> sections;
  final List<Product> products;

  const MenuScreen({
    super.key,
    required this.sections,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Меню'),
        centerTitle: true,
      ),
      body: ListView.separated(
        itemCount: sections.length + 1,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          /// 🔹 Главная
          if (index == 0) {
            return ListTile(
              leading: const Icon(Icons.home),
              title: const Text('На главную'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/',
                      (route) => false,
                );
              },
            );
          }

          /// 🔹 Категории
          final section = sections[index - 1];

          return ListTile(
            title: Text(section.name),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
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
    );
  }
}