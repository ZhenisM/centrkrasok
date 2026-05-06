import 'package:centrkrasok/repositories/products/products.dart';
import 'package:dio/dio.dart';

class ProductsRepository  {

  ProductsRepository({
    required this.dio,
  });

  final Dio dio;

  @override
  Future<(List<Product>, List<Section>)> getProductsList() async {
    final response = await dio.get('https://prons.kz/ajax/get_catalog_list.php');

    final data = response.data as Map<String, dynamic>;
    final productsJson = data['products'] as List<dynamic>;
    final sectionsJson = data['sections'] as List<dynamic>;
    final productsList = productsJson.map((e) => Product.fromJson(e)).toList();
    final sections = sectionsJson.map((e) => Section.fromJson(e)).toList();
    return (productsList, sections);
  }

}