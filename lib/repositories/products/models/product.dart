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

/// Скидка каталога сайта (как «Скидка 20%» на offline.centr-krasok.kz).
/// Приходит с сервера полем `discount`: base — цена до скидки, price —
/// цена со скидкой, percent — процент.
class ProductDiscount {
  final double base;
  final double price;
  final double percent;

  const ProductDiscount({required this.base, required this.price, required this.percent});

  static ProductDiscount? fromJson(dynamic json) {
    if (json is! Map) return null;
    final base = double.tryParse(json['base'].toString()) ?? 0;
    final price = double.tryParse(json['price'].toString()) ?? 0;
    if (base <= 0 || price <= 0 || base - price < 0.5) return null;
    return ProductDiscount(
      base: base,
      price: price,
      percent: double.tryParse(json['percent'].toString()) ?? ((base - price) / base * 100),
    );
  }

  /// «-20%» / «-7.5%».
  String get label {
    final p = percent.roundToDouble() == percent ? percent.toStringAsFixed(0) : percent.toStringAsFixed(1);
    return '-$p%';
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
  final ProductDiscount? discount;

  Product({
    required this.id,
    required this.brend,
    required this.article,
    required this.name,
    required this.sectionId,
    required this.image,
    required this.prices,
    required this.props,
    this.discount,
  });

  /// Розничная цена без скидки: группа 30 («Розничная ИСПОЛЬЗОВАТЬ»), если
  /// она есть у товара, иначе минимальная из имеющихся.
  double get retailPrice {
    if (prices.isEmpty) return 0;
    final retail = prices.where((p) => p.typeId == '30').toList();
    final source = retail.isNotEmpty ? retail : prices;
    return source.map((p) => p.price).reduce((a, b) => a < b ? a : b);
  }

  /// Цена, по которой товар продаётся: со скидкой каталога, если она есть.
  double get finalPrice => discount?.price ?? retailPrice;

  Product withDiscount(ProductDiscount? d) => Product(
        id: id,
        brend: brend,
        article: article,
        name: name,
        sectionId: sectionId,
        image: image,
        prices: prices,
        props: props,
        discount: d,
      );

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
      discount: ProductDiscount.fromJson(json['discount']),
    );
  }
}
