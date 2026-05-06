import 'package:centrkrasok/repositories/products/products.dart';
import 'package:dio/dio.dart';
/*
class ProductsRepository  {

  ProductsRepository({
    required this.dio,
  });

  final Dio dio;

  @override
  Future<List<Product>> getProductsList() async {
    final response = await dio.get('https://min-api.cryptocompare.com/data/pricemultifull?fsyms=BTC,ETH,BNB,SOL,AID,CAG,DOV&tsyms=USD');

    final data = response.data as Map<String, dynamic>;
    final dataRaw = data['RAW'] as Map<String, dynamic>;
    final productsList = dataRaw.entries.map((e) {
      final usdData = (e.value as Map<String, dynamic>)['USD'] as Map<String, dynamic>;
      final price = usdData['PRICE'];
      final imageUrl = usdData['IMAGEURL'];
      return Product(
        name: e.key,
        price: price,
        imageUrl: 'https://www.cryptocompare.com/$imageUrl',
      );}).toList();
    return productsList;
  }
}
*/