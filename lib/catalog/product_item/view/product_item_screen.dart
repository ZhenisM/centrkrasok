import 'package:flutter/material.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';

class ProductItemScreen extends StatefulWidget {
  const ProductItemScreen({super.key});

  @override
  State<ProductItemScreen> createState() => _ProductItemScreenState();
}

class _ProductItemScreenState extends State<ProductItemScreen> {
  Product? product;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Product) {
      product = args;
      setState(() {});
    }
  }


  @override
  Widget build(BuildContext context) {
    if (product == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(product!.name)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text('ID: ${product!.id}', style: const TextStyle(fontSize: 20)),
            if (product!.brend != null)
              Text('Бренд: ${product!.brend}',
                  style: const TextStyle(fontSize: 20)),
            if (product!.article != null)
              Text('Артикул: ${product!.article}',
                  style: const TextStyle(fontSize: 20)),
            Text('Название: ${product!.name}',
                style: const TextStyle(fontSize: 20)),
            Text('Фасовка: ${product!.fasovka}',
                style: const TextStyle(fontSize: 20)),
            Text('Категория: ${product!.section}',
                style: const TextStyle(fontSize: 20)),
            Text('ID категории: ${product!.sectionId}',
                style: const TextStyle(fontSize: 20)),

            const SizedBox(height: 20),
            const Text('Цены:',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),

            ...product!.prices.map((price) =>
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Тип: ${price.typeName}',
                        style: const TextStyle(fontSize: 20)),
                    Text('Цена: ${price.price} ${price.currency}',
                        style: const TextStyle(fontSize: 20)),
                    const Divider(),
                  ],
                )),
          ],
        ),
      ),
    );
  }
}



