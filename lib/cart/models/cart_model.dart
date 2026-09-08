import 'dart:convert';

/// Статус корзины — соответствует STATUS_ID заказа на сервере (BS/BO/BD,
/// те же коды, что и в smultibasket/class.php на сайте). В отличие от
/// offlinesvet (HL-блок), здесь корзина — это Bitrix\Sale\Order.
enum CartStatus {
  inProgress, // BS, "в работе"
  completed, // BO, "оформлена"
  deleted; // BD, "удалена"

  static CartStatus fromLabel(String label) {
    switch (label) {
      case 'оформлена':
        return CartStatus.completed;
      case 'удалена':
        return CartStatus.deleted;
      case 'в работе':
      default:
        return CartStatus.inProgress;
    }
  }

  String get label {
    switch (this) {
      case CartStatus.inProgress:
        return 'в работе';
      case CartStatus.completed:
        return 'оформлена';
      case CartStatus.deleted:
        return 'удалена';
    }
  }
}

/// Один товар в корзине-заказе. В отличие от offlinesvet, свойства не
/// фиксированы (SELECT_ROOM/_RASPRODAZHA) — здесь произвольный набор
/// PROPS (для красок это SELECT_ROOM + ROOM_SQUARE, в перспективе могут
/// добавиться другие, например колеровка), поэтому PROPS — обычная карта.
class CartItem {
  final int productId;
  final String name;
  final double quantity;
  final double price;
  final bool customPrice;
  final Map<String, String> props;

  const CartItem({
    required this.productId,
    this.name = '',
    required this.quantity,
    this.price = 0,
    this.customPrice = false,
    this.props = const {},
  });

  CartItem copyWith({
    int? productId,
    String? name,
    double? quantity,
    double? price,
    bool? customPrice,
    Map<String, String>? props,
  }) {
    return CartItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      customPrice: customPrice ?? this.customPrice,
      props: props ?? this.props,
    );
  }

  Map<String, dynamic> toJson() => {
        'PRODUCT_ID': productId,
        'NAME': name,
        'QUANTITY': quantity,
        if (customPrice) 'PRICE': price,
        if (customPrice) 'CUSTOM_PRICE': 'Y',
        'PROPS': props,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final rawProps = json['PROPS'] as Map<String, dynamic>? ?? {};
    return CartItem(
      productId: _toInt(json['PRODUCT_ID']) ?? 0,
      name: json['NAME']?.toString() ?? '',
      quantity: _toDouble(json['QUANTITY']) ?? 0,
      price: _toDouble(json['PRICE']) ?? 0,
      customPrice: json['CUSTOM_PRICE']?.toString() == 'Y',
      props: rawProps.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
  }
}

/// Сервер (cart_load.php) не всегда отдаёт числовые поля одинаковым типом
/// (например PRODUCT_ID уходит строкой) — разбираем терпимо к обоим
/// вариантам вместо жёсткого `as num?`, который однажды уже уронил разбор
/// ЛЮБОЙ непустой корзины молча (см. историю правок).
int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Сериализует список товаров в JSON-массив (обычный, не " / "-разделённая
/// строка, как в offlinesvet) — именно так его ожидает cart_save.php
/// (action=update_products, products_info).
String encodeCartItems(List<CartItem> items) {
  return jsonEncode(items.map((item) => item.toJson()).toList());
}

/// Корзина — соответствует одному заказу (Bitrix\Sale\Order, STATUS_ID=BS)
/// на сервере centrkrasok. Каждый выбор/создание клиента порождает новую
/// корзину — корзины не переиспользуются (как и в offlinesvet).
class Cart {
  final String id;
  final String title;
  final CartStatus status;
  final DateTime dateCreate;
  final Map<String, dynamic>? clientInfo;
  final List<CartItem> items;

  const Cart({
    required this.id,
    required this.title,
    required this.status,
    required this.dateCreate,
    this.clientInfo,
    this.items = const [],
  });

  double get itemsCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice =>
      items.fold(0, (sum, item) => sum + item.price * item.quantity);

  Cart copyWith({
    String? id,
    String? title,
    CartStatus? status,
    DateTime? dateCreate,
    Map<String, dynamic>? clientInfo,
    List<CartItem>? items,
  }) {
    return Cart(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      dateCreate: dateCreate ?? this.dateCreate,
      clientInfo: clientInfo ?? this.clientInfo,
      items: items ?? this.items,
    );
  }

  factory Cart.fromJson(Map<String, dynamic> json) {
    final rawItems = json['productsInfo'] as List<dynamic>? ?? [];
    return Cart(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      status: CartStatus.fromLabel(json['status']?.toString() ?? ''),
      dateCreate: _parseDate(json['dateCreate']?.toString() ?? ''),
      clientInfo: json['clientInfo'] as Map<String, dynamic>?,
      items: rawItems
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static DateTime _parseDate(String raw) {
    // Формат от сервера: "04.09.2026 12:53:24"
    try {
      final parts = raw.split(' ');
      final dateParts = parts[0].split('.');
      final timeParts =
          parts.length > 1 ? parts[1].split(':') : ['0', '0', '0'];
      return DateTime(
        int.parse(dateParts[2]),
        int.parse(dateParts[1]),
        int.parse(dateParts[0]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        timeParts.length > 2 ? int.parse(timeParts[2]) : 0,
      );
    } catch (_) {
      return DateTime.now();
    }
  }
}
