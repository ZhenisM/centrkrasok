class Price {
  final String typeId;
  final String typeName;
  final String price;
  final String currency;

  Price({
    required this.typeId,
    required this.typeName,
    required this.price,
    required this.currency,
  });

  factory Price.fromJson(Map<String, dynamic> json) {
    return Price(
      typeId: json['type_id'],
      typeName: json['type_name'],
      price: json['price'],
      currency: json['currency'],
    );
  }
}

class Product {
  final String id;
  final String? brend;
  final String? fasovka;
  final String? article;
  final String name;
  final String section;
  final String sectionId;
  final String? image;
  final List<Price> prices;

  Product({
    required this.id,
    required this.brend,
    required this.fasovka,
    required this.article,
    required this.name,
    required this.section,
    required this.sectionId,
    required this.image,
    required this.prices,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final pricesJson = json['prices'] as List<dynamic>;
    final pricesList = pricesJson.map((e) => Price.fromJson(e)).toList();

    return Product(
      id: json['id'],
      brend: json['brend'],
      fasovka: json['fasovka'],
      article: json['article'],
      name: json['name'],
      section: json['section'],
      sectionId: json['sectionId'],
      image: json['image'],
      prices: pricesList,
    );
  }
}