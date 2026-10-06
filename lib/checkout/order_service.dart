import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Поле заказа — как его настроили в Bitrix (свойство заказа).
class OrderPropField {
  final int id;
  final String code;
  final String name;
  final String type; // STRING, NUMBER, Y/N, ENUM, DATE
  final bool required;
  final bool multiple;
  final bool multiline;
  final bool asList; // ENUM: выпадающий список, иначе радио/чекбоксы
  final String description;
  final bool isPhone;
  final bool isEmail;
  final List<MapEntry<String, String>> variants; // value -> name

  OrderPropField.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        code = j['code']?.toString() ?? '',
        name = j['name']?.toString() ?? '',
        type = j['type']?.toString() ?? 'STRING',
        required = j['required'] == true,
        multiple = j['multiple'] == true,
        multiline = j['multiline'] == true,
        asList = j['as_list'] == true,
        description = j['description']?.toString() ?? '',
        isPhone = j['is_phone'] == true,
        isEmail = j['is_email'] == true,
        variants = ((j['variants'] as List?) ?? [])
            .map((v) => MapEntry(v['value'].toString(), v['name'].toString()))
            .toList();
}

/// Условие показа полей (как на сайте): props видны, если поле [when] = [equals].
class OrderShowRule {
  final List<int> props;
  final int when;
  final String equals;
  final bool required;

  OrderShowRule.fromJson(Map<String, dynamic> j)
      : props = ((j['props'] as List?) ?? []).map((e) => (e as num).toInt()).toList(),
        when = (j['when'] as num).toInt(),
        equals = j['equals']?.toString() ?? '',
        required = j['required'] == true;
}

class OrderBasketLine {
  final String name;
  final double quantity;
  final double price;
  final double basePrice;
  final double sum;
  final String measure;
  final String picture;
  final Map<String, String> props; // TINT_NAME, TINT_RGB, TINT_PRICE, TINT_DISCOUNT
  OrderBasketLine.fromJson(Map<String, dynamic> j)
      : name = j['name']?.toString() ?? '',
        quantity = (j['quantity'] as num?)?.toDouble() ?? 0,
        price = (j['price'] as num?)?.toDouble() ?? 0,
        basePrice = (j['base_price'] as num?)?.toDouble() ?? 0,
        sum = (j['sum'] as num?)?.toDouble() ?? 0,
        measure = j['measure']?.toString() ?? '',
        picture = j['picture']?.toString() ?? '',
        props = j['props'] is Map
            ? Map<String, dynamic>.from(j['props'] as Map).map((k, v) => MapEntry(k, v.toString()))
            : <String, String>{};
}

/// Форма оформления для конкретной корзины и типа плательщика.
class OrderForm {
  final int personType;
  final List<MapEntry<int, String>> personTypes;
  final List<OrderPropField> props;
  final Map<int, dynamic> values; // предзаполнено сервером (как сайт)
  final List<OrderShowRule> rules;
  final Set<int> hidden;
  /// Скрытые, но отправляемые поля (сайт прячет их и заполняет сам).
  final Set<int> auto;
  final String comment;
  final String paySystem;
  final String delivery;
  final List<OrderBasketLine> basket;
  final double total;
  final int partnerPropId;

  OrderForm.fromJson(Map<String, dynamic> j)
      : personType = (j['person_type'] as num).toInt(),
        personTypes = ((j['person_types'] as List?) ?? [])
            .map((e) => MapEntry((e['id'] as num).toInt(), e['name'].toString()))
            .toList(),
        props = ((j['props'] as List?) ?? [])
            .map((e) => OrderPropField.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        values = (j['values'] is Map ? Map<String, dynamic>.from(j['values'] as Map) : <String, dynamic>{})
            .map((k, v) => MapEntry(int.parse(k), v)),
        rules = (((j['rules'] as Map?)?['show_if'] as List?) ?? [])
            .map((e) => OrderShowRule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        hidden = (((j['rules'] as Map?)?['hidden'] as List?) ?? []).map((e) => (e as num).toInt()).toSet(),
        auto = (((j['rules'] as Map?)?['auto'] as List?) ?? []).map((e) => (e as num).toInt()).toSet(),
        comment = j['comment']?.toString() ?? '',
        paySystem = j['pay_system']?.toString() ?? '',
        delivery = j['delivery']?.toString() ?? '',
        basket = (((j['basket'] as Map?)?['items'] as List?) ?? [])
            .map((e) => OrderBasketLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        total = ((j['basket'] as Map?)?['total'] as num?)?.toDouble() ?? 0,
        partnerPropId = (j['partner_prop_id'] as num?)?.toInt() ?? 0;
}

class CreatedOrder {
  final int orderId;
  final String accountNumber;
  final String date;
  final double total;
  final String city;

  CreatedOrder.fromJson(Map<String, dynamic> j)
      : orderId = (j['order_id'] as num).toInt(),
        accountNumber = j['account_number']?.toString() ?? '',
        date = j['date']?.toString() ?? '',
        total = (j['total'] as num?)?.toDouble() ?? 0,
        city = j['city']?.toString() ?? 'almaty';
}

class OrderPartner {
  final String name;
  final String bin;
  OrderPartner(this.name, this.bin);
}

class OrderApiException implements Exception {
  final String message;
  OrderApiException(this.message);
  @override
  String toString() => message;
}

/// Оформление заказа через order.php — те же поля и автозаполнение, что
/// на странице оформления сайта offline.centr-krasok.kz.
class OrderService {
  OrderService({required this.dio});
  final Dio dio;
  static const _url = 'https://prons.kz/ajax/centrkrasok/order.php';

  /// personType: 6 — физлицо, 7 — юрлицо; null — по клиенту корзины.
  Future<OrderForm> form(String basketId, {int? personType}) async => OrderForm.fromJson(
      await _call('form', {'basket_id': basketId, if (personType != null) 'person_type': '$personType'}));

  Future<List<OrderPartner>> partners(String query, int personType) async {
    final r = await _call('partners', {'q': query, 'person_type': '$personType'});
    return ((r['partners'] as List?) ?? [])
        .map((e) => OrderPartner(e['name'].toString(), e['bin']?.toString() ?? ''))
        .toList();
  }

  Future<CreatedOrder> create({
    required String basketId,
    required int personType,
    required Map<int, dynamic> values,
    required String comment,
  }) async =>
      CreatedOrder.fromJson(await _call('create', {
        'basket_id': basketId,
        'person_type': '$personType',
        'props': jsonEncode(values.map((k, v) => MapEntry('$k', v))),
        'comment': comment,
      }, timeout: const Duration(seconds: 60)));

  /// kind: v1 — «КП», v2 — «КП НОВЫЕ». print: HTML-версия для печати (только v1).
  Future<String> kpLink(int orderId, {required String kind, required String city, required String lang, bool print = false}) async {
    final r = await _call('kp_link', {
      'order_id': '$orderId', 'kind': kind, 'city': city, 'lang': lang, if (print) 'print': 'y',
    });
    return r['url'].toString();
  }

  Future<Map<String, dynamic>> _call(String action, Map<String, String> params,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    if (token.isEmpty) throw OrderApiException('Сессия истекла, войдите заново');
    try {
      final response = await dio.post(
        _url,
        data: FormData.fromMap({'token': token, 'action': action, ...params}),
        options: Options(responseType: ResponseType.plain, validateStatus: (s) => s != null, receiveTimeout: timeout),
      );
      dynamic data = response.data;
      if (data is String) {
        try { data = jsonDecode(data); } catch (_) {}
      }
      if (data is Map && data['result'] is Map) return Map<String, dynamic>.from(data['result'] as Map);
      if (data is Map && data['error'] != null) {
        final debug = data['debug']?.toString();
        if (debug != null) debugPrint('order[$action]: ${response.statusCode} $debug');
        throw OrderApiException(debug != null ? '${data['error']}\n$debug' : data['error'].toString());
      }
      final raw = data?.toString() ?? '';
      debugPrint('order[$action]: ${response.statusCode} не JSON: ${raw.length > 500 ? raw.substring(0, 500) : raw}');
      throw OrderApiException('Сервер вернул неожиданный ответ (${response.statusCode})');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        throw OrderApiException('Нет подключения к интернету — оформление работает только онлайн');
      }
      throw OrderApiException('Ошибка сети при оформлении заказа');
    }
  }
}
