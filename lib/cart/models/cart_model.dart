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
  final double basePrice; // цена "было" (до скидки купона) — для зачёркнутого показа
  final bool customPrice;
  final Map<String, String> props;

  const CartItem({
    required this.productId,
    this.name = '',
    required this.quantity,
    this.price = 0,
    double? basePrice,
    this.customPrice = false,
    this.props = const {},
  }) : basePrice = basePrice ?? price;

  /// Скидка есть, если "было" заметно больше "сейчас" (с запасом на
  /// погрешность округления копеек).
  bool get hasDiscount => basePrice - price > 0.01;

  double get discountPercent =>
      hasDiscount && basePrice > 0 ? ((basePrice - price) / basePrice) * 100 : 0;

  CartItem copyWith({
    int? productId,
    String? name,
    double? quantity,
    double? price,
    double? basePrice,
    bool? customPrice,
    Map<String, String>? props,
  }) {
    return CartItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      basePrice: basePrice ?? this.basePrice,
      customPrice: customPrice ?? this.customPrice,
      props: props ?? this.props,
    );
  }

  Map<String, dynamic> toJson() => {
        'PRODUCT_ID': productId,
        'NAME': name,
        'QUANTITY': quantity,
        // ВСЕГДА включаем PRICE/CUSTOM_PRICE (а не только когда
        // customPrice==true) — эта функция используется и для отправки на
        // сервер (там PRICE применяется только если CUSTOM_PRICE=='Y', так
        // что 'N' безопасно игнорируется), и для локального кэша
        // (CartLocalStore) — а в кэше условное исключение PRICE стирало
        // цену при перечитывании и показывало 0 до первого ручного выбора
        // корзины в шторке "Лиды". BASE_PRICE по той же причине —
        // всегда, иначе зачёркнутая цена пропадала бы при перезагрузке.
        'PRICE': price,
        'BASE_PRICE': basePrice,
        'CUSTOM_PRICE': customPrice ? 'Y' : 'N',
        'PROPS': props,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final rawProps = json['PROPS'] as Map<String, dynamic>? ?? {};
    final price = _toDouble(json['PRICE']) ?? 0;
    return CartItem(
      productId: _toInt(json['PRODUCT_ID']) ?? 0,
      name: json['NAME']?.toString() ?? '',
      quantity: _toDouble(json['QUANTITY']) ?? 0,
      price: price,
      basePrice: _toDouble(json['BASE_PRICE']) ?? price,
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
  final List<String> coupons;
  final List<CartItem> items;

  const Cart({
    required this.id,
    required this.title,
    required this.status,
    required this.dateCreate,
    this.clientInfo,
    this.coupons = const [],
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
    List<String>? coupons,
    List<CartItem>? items,
  }) {
    return Cart(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      dateCreate: dateCreate ?? this.dateCreate,
      clientInfo: clientInfo ?? this.clientInfo,
      coupons: coupons ?? this.coupons,
      items: items ?? this.items,
    );
  }

  factory Cart.fromJson(Map<String, dynamic> json) {
    final rawItems = json['productsInfo'] as List<dynamic>? ?? [];
    final rawCoupons = json['coupons'] as List<dynamic>? ?? [];
    return Cart(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      status: CartStatus.fromLabel(json['status']?.toString() ?? ''),
      dateCreate: _parseDate(json['dateCreate']?.toString() ?? ''),
      clientInfo: json['clientInfo'] as Map<String, dynamic>?,
      coupons: rawCoupons.map((e) => e.toString()).toList(),
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
