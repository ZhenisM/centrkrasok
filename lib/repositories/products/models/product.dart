class Price {
  final String typeId;
  final String typeName;
  final double price;
  final String currency;

  Price({
    required this.typeId,
    required this.typeName,
    required this.price,
    required this.currency,
  });

  factory Price.fromJson(Map<String, dynamic> json) {
    return Price(
      typeId: json['type_id'].toString(),
      typeName: json['type_name'].toString(),
      price: double.parse(json['price'].toString()),
      currency: json['currency'].toString(),
    );
  }
}

class Prop {
  final String name;
  final String code;
  final String value;

  Prop({
    required this.name,
    required this.code,
    required this.value,
  });

  factory Prop.fromJson(Map<String, dynamic> json) {
    return Prop(
      name: json['NAME'].toString(),
      code: json['CODE'].toString(),
      value: json['VALUE'].toString(),
    );
  }
}

class Product {
  final String id;
  final String? brend;
  final String? article;
  final String name;
  final String sectionId;
  final String? image;
  final List<Price> prices;
  final Map<String, Prop> props;

  Product({
    required this.id,
    required this.brend,
    required this.article,
    required this.name,
    required this.sectionId,
    required this.image,
    required this.prices,
    required this.props,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final pricesList = (json['prices'] as List<dynamic>)
        .map((e) => Price.fromJson(e as Map<String, dynamic>))
        .toList();

    final propsMap = <String, Prop>{};
    if (json['props'] is Map) {
      (json['props'] as Map<String, dynamic>).forEach((code, value) {
        if (value is Map<String, dynamic>) {
          propsMap[code] = Prop.fromJson(value);
        }
      });
    }

    return Product(
      id: json['id'].toString(),
      brend: json['brend']?.toString(),
      article: json['article']?.toString(),
      name: json['name'].toString(),
      sectionId: json['sectionId'].toString(),
      image: json['image']?.toString(),
      prices: pricesList,
      props: propsMap,
    );
  }
}
