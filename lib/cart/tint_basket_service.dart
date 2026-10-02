import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

/// Позиция заявки на колеровку (как её видит/оценил колеровщик).
class TintRequestProduct {
  final int productId;
  final String name;
  final double quantity;
  final String tintName;
  final String tintRgb;
  final double tintPrice;
  final bool active;

  TintRequestProduct.fromJson(Map<String, dynamic> j)
      : productId = (j['product_id'] as num?)?.toInt() ?? 0,
        name = j['name']?.toString() ?? '',
        quantity = (j['quantity'] as num?)?.toDouble() ?? 0,
        tintName = j['tint_name']?.toString() ?? '',
        tintRgb = j['tint_rgb']?.toString() ?? '',
        tintPrice = (j['tint_price'] as num?)?.toDouble() ?? 0,
        active = j['active'] != false;
}

/// Заявка на колеровку (HL-блок колеровок сайта).
class TintRequest {
  final int id;
  final String statusCode; // in_process / price_set / ... (XML_ID статуса)
  final String statusName; // как на сайте: «проставить цены», «цены проставлены»…
  final String date;
  final String priceSetter;
  final List<TintRequestProduct> products;
  final double total;
  final bool canApply;
  final bool isActive; // ждёт расчёта или рассчитана, но ещё не в корзине
  final bool inBasket; // колеровка уже добавлена в корзину

  TintRequest.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num?)?.toInt() ?? 0,
        statusCode = (j['status'] as Map?)?['code']?.toString() ?? '',
        statusName = (j['status'] as Map?)?['name']?.toString() ?? '',
        date = j['date']?.toString() ?? '',
        priceSetter = j['price_setter']?.toString() ?? '',
        products = ((j['products'] as List?) ?? [])
            .map((e) => TintRequestProduct.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        total = (j['total'] as num?)?.toDouble() ?? 0,
        canApply = j['can_apply'] == true,
        isActive = j['is_active'] == true,
        inBasket = j['in_basket'] == true;
}

/// Состояние колеровки корзины.
class TintState {
  final TintRequest? tint;
  final int pendingItems; // колерованные позиции без цены колеровки
  final bool canSend;

  const TintState({this.tint, this.pendingItems = 0, this.canSend = false});

  TintState.fromJson(Map<String, dynamic> j)
      : tint = j['tint'] is Map ? TintRequest.fromJson(Map<String, dynamic>.from(j['tint'] as Map)) : null,
        pendingItems = (j['pending_items'] as num?)?.toInt() ?? 0,
        canSend = j['can_send'] == true;

  /// Пока заявка в работе, колерованные позиции без цены менять нельзя —
  /// иначе расчёт колеровщика разойдётся с корзиной.
  bool get locksTintedItems => tint?.isActive == true;
}


/// Строка списка «Мои колеровки».
class TintListItem {
  final int id;
  final String statusCode;
  final String statusName;
  final String date;
  final String client;
  final String priceSetter;
  final int appBasketId;

  TintListItem.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num?)?.toInt() ?? 0,
        statusCode = (j['status'] as Map?)?['code']?.toString() ?? '',
        statusName = (j['status'] as Map?)?['name']?.toString() ?? '',
        date = j['date']?.toString() ?? '',
        client = j['client']?.toString() ?? '',
        priceSetter = j['price_setter']?.toString() ?? '',
        appBasketId = (j['app_basket_id'] as num?)?.toInt() ?? 0;
}

/// Позиция на странице колеровки.
class TintDetailProduct {
  final int itemId;
  final int productId;
  final String name;
  final String picture;
  final String brand;
  final String base;
  final String volume;
  final double quantity;
  final String tintName;
  final String tintCollection;
  final String tintRgb;
  final double? tintPrice;
  final int catalogTintProductId;
  final bool active;

  TintDetailProduct.fromJson(Map<String, dynamic> j)
      : itemId = (j['item_id'] as num?)?.toInt() ?? 0,
        productId = (j['product_id'] as num?)?.toInt() ?? 0,
        name = j['name']?.toString() ?? '',
        picture = j['picture']?.toString() ?? '',
        brand = j['brand']?.toString() ?? '',
        base = j['base']?.toString() ?? '',
        volume = j['volume']?.toString() ?? '',
        quantity = (j['quantity'] as num?)?.toDouble() ?? 0,
        tintName = j['tint_name']?.toString() ?? '',
        tintCollection = j['tint_collection']?.toString() ?? '',
        tintRgb = j['tint_rgb']?.toString() ?? '',
        tintPrice = (j['tint_price'] as num?)?.toDouble(),
        catalogTintProductId = (j['catalog_tint_product_id'] as num?)?.toInt() ?? 0,
        active = j['active'] != false;
}

/// Заявка целиком — аналог /tint/detail.php?ID=… на сайте.
class TintDetail {
  final int id;
  final String statusCode;
  final String statusName;
  final String date;
  final String client;
  final String priceSetter;
  final List<TintDetailProduct> products;
  final double total;
  final List<MapEntry<int, String>> tintProducts; // «Товар колеровки»: id -> бренд
  final int appBasketId;
  final bool canSetPrices;
  final bool canChange;
  final bool canApply;
  final bool canCancel;
  final bool canDeactivate;

  TintDetail.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num?)?.toInt() ?? 0,
        statusCode = (j['status'] as Map?)?['code']?.toString() ?? '',
        statusName = (j['status'] as Map?)?['name']?.toString() ?? '',
        date = j['date']?.toString() ?? '',
        client = j['client']?.toString() ?? '',
        priceSetter = j['price_setter']?.toString() ?? '',
        products = ((j['products'] as List?) ?? [])
            .map((e) => TintDetailProduct.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        total = (j['total'] as num?)?.toDouble() ?? 0,
        tintProducts = ((j['tint_products'] as List?) ?? [])
            .map((e) => MapEntry((e['id'] as num).toInt(), e['name'].toString()))
            .toList(),
        appBasketId = (j['app_basket_id'] as num?)?.toInt() ?? 0,
        canSetPrices = j['can_set_prices'] == true,
        canChange = j['can_change'] == true,
        canApply = j['can_apply'] == true,
        canCancel = j['can_cancel'] == true,
        canDeactivate = j['can_deactivate'] == true;
}

/// Ответ «Проставить цену из базы».
class TintBasePrice {
  final double price;
  final String targetBase;
  TintBasePrice(this.price, this.targetBase);
}

class TintBasketException implements Exception {
  final String message;
  TintBasketException(this.message);
  @override
  String toString() => message;
}

/// Колеровка корзины через tint_basket.php — тот же процесс, что на сайте:
/// отправка колеровщику, статус, добавление рассчитанной колеровки в
/// корзину, скидка на колеровку. Колеровщик работает на сайте (/tint/).
class TintBasketService {
  TintBasketService({required this.dio});
  final Dio dio;

  static const _url = 'https://prons.kz/ajax/centrkrasok/tint_basket.php';

  Future<TintState> status(String basketId) => _call('status', basketId);
  Future<TintState> send(String basketId) => _call('send', basketId);
  Future<TintState> apply(String basketId, int tintId) =>
      _call('apply', basketId, {'tint_id': tintId.toString()});

  /// percent: 10 или 20; 0 — снять скидку.
  Future<TintState> discount(String basketId, int percent) =>
      _call('discount', basketId, {'percent': percent.toString()});

  // --- Страница колеровки (без корзины) ---
  Future<List<TintListItem>> list() async {
    final r = await _raw('list', {});
    return ((r['tints'] as List?) ?? [])
        .map((e) => TintListItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<TintDetail> detail(int tintId) async =>
      TintDetail.fromJson(await _raw('detail', {'tint_id': '$tintId'}));

  Future<TintBasePrice> priceFromBase(int tintId, int itemId) async {
    final r = await _raw('get_price', {'tint_id': '$tintId', 'item_id': '$itemId'});
    return TintBasePrice((r['price'] as num?)?.toDouble() ?? 0, r['target_base']?.toString() ?? '');
  }

  Future<TintDetail> setPrices(int tintId, Map<int, double> prices, Map<int, int> tintProducts) async =>
      TintDetail.fromJson(await _raw('set_prices', {
        'tint_id': '$tintId',
        'prices': jsonEncode(prices.map((k, v) => MapEntry('$k', v))),
        'tint_products': jsonEncode(tintProducts.map((k, v) => MapEntry('$k', v))),
      }));

  Future<TintDetail> change(int tintId) async =>
      TintDetail.fromJson(await _raw('change', {'tint_id': '$tintId'}));

  /// «Отменить»: если колеровка уже в корзине — сервер убирает из корзины
  /// услугу колеровки и «Цену колеровки» у позиций.
  Future<TintDetail> cancel(int tintId) async =>
      TintDetail.fromJson(await _raw('cancel', {'tint_id': '$tintId'}));

  Future<TintDetail> deactivate(int tintId, int itemId) async =>
      TintDetail.fromJson(await _raw('deactivate', {'tint_id': '$tintId', 'item_id': '$itemId'}));

  Future<TintState> _call(String action, String basketId, [Map<String, String> extra = const {}]) async =>
      TintState.fromJson(await _raw(action, {'basket_id': basketId, ...extra}));

  Future<Map<String, dynamic>> _raw(String action, Map<String, String> params) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    if (token.isEmpty) throw TintBasketException('Сессия истекла, войдите заново');

    try {
      final response = await dio.post(
        _url,
        data: FormData.fromMap({'token': token, 'action': action, ...params}),
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null,
          receiveTimeout: const Duration(seconds: 40),
        ),
      );
      dynamic data = response.data;
      if (data is String) {
        try { data = jsonDecode(data); } catch (_) {}
      }
      if (data is Map && data['result'] is Map) {
        return Map<String, dynamic>.from(data['result'] as Map);
      }
      if (data is Map && data['error'] != null) {
        final debug = data['debug']?.toString();
        if (debug != null) debugPrint('tint_basket[$action]: ${response.statusCode} $debug');
        throw TintBasketException(debug != null ? '${data['error']}\n$debug' : data['error'].toString());
      }
      final raw = data?.toString() ?? '';
      debugPrint('tint_basket[$action]: ${response.statusCode} не JSON: ${raw.length > 500 ? raw.substring(0, 500) : raw}');
      throw TintBasketException('Сервер колеровки вернул неожиданный ответ (${response.statusCode})');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        throw TintBasketException('Нет подключения к интернету — колеровка работает только онлайн');
      }
      throw TintBasketException('Ошибка сети при обращении к колеровке');
    }
  }
}

/// Цвета статусов колеровки — те же, что на сайте (/tint/, style.css).
Color tintStatusColor(String code) {
  switch (code) {
    case 'in_process':
      return const Color(0xFFFF5900); // проставить цены
    case 'price_set':
      return const Color(0xFFF0970A); // цены проставлены
    case 'added_to_cart':
      return const Color(0xFFACD1EC); // в корзине
    case 'order_made':
      return const Color(0xFFFFAFAF); // заказ оформлен
    case 'order_paid':
      return const Color(0xFFFF5757); // оплачен
    case 'done':
      return const Color(0xFFEBEAE0); // выполнен
    case 'canceled':
      return const Color(0xFF909090);
    default:
      return const Color(0xFF909090);
  }
}
