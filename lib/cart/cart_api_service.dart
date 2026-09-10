import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:centrkrasok/bitrix/bitrix_service.dart' show NoInternetException;
import 'package:centrkrasok/cart/models/cart_model.dart';
import 'package:centrkrasok/customer/models/customer_model.dart';

/// Тот же базовый URL, что и у остальных кастомных эндпоинтов на prons.kz
/// (ProductsRepository, PronsApiService), но своя папка centrkrasok.
const String _pronsBaseUrl = 'https://prons.kz/ajax/centrkrasok';

/// Маркер "параметр coupons не передан вовсе" — отличаем от [] (снять все
/// купоны явно). Object() с identical() вместо enum, чтобы не тащить лишний
/// публичный тип ради одного приватного параметра.
const Object _unsetCoupons = Object();

/// Сервис интеграции с cart_save.php / cart_load.php — корзина здесь это
/// Bitrix\Sale\Order (STATUS_ID=BS), НЕ HL-блок Multibaskets (это отличает
/// centrkrasok от offlinesvet — корзины двух приложений в разных хранилищах
/// и никогда не пересекаются).
class CartApiService {
  CartApiService({required this.dio});

  final Dio dio;

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> _requireInternet() async {
    if (!await _hasInternet()) {
      throw NoInternetException();
    }
  }

  /// Создаёт новую корзину-заказ для клиента/компании. Вызывается каждый
  /// раз при выборе/создании контакта или компании — даже если у клиента
  /// уже есть корзины, создаётся НОВАЯ запись (как и на сайте, и в
  /// offlinesvet). Возвращает ID нового заказа.
  Future<String> createCart({
    required int managerId,
    required Customer customer,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_pronsBaseUrl/cart_save.php',
        data: {
          'action': 'create',
          'manager_id': managerId.toString(),
          'is_company': customer.isCompany ? 'Y' : 'N',
          'title': customer.fullName,
          'client_info': jsonEncode(customer.toMultibasketsClientInfo()),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final data = _ensureMap(response.data);
      if (data['error'] != null) {
        throw CartApiException(data['error'].toString());
      }

      final result = data['result'] as Map<String, dynamic>?;
      final id = result?['id']?.toString();
      if (id == null) {
        throw CartApiException('Сервер не вернул ID новой корзины');
      }
      return id;
    } on DioException catch (e) {
      debugPrint('createCart: ошибка сети: ${e.message}, ответ сервера: ${e.response?.data}');
      throw CartApiException('Не удалось создать корзину');
    }
  }

  /// Загружает список активных ("в работе", STATUS_ID=BS) корзин-заказов
  /// менеджера на сайте centrkrasok.
  Future<List<Cart>> loadCarts({required int managerId}) async {
    await _requireInternet();

    try {
      final response = await dio.get(
        '$_pronsBaseUrl/cart_load.php',
        queryParameters: {'manager_id': managerId.toString()},
      );

      final data = _ensureMap(response.data);
      if (data['error'] != null) {
        throw CartApiException(data['error'].toString());
      }

      final result = data['result'] as List<dynamic>? ?? [];
      final carts = <Cart>[];
      for (final e in result) {
        try {
          carts.add(Cart.fromJson(e as Map<String, dynamic>));
        } catch (parseError) {
          // Один "плохой" заказ (например, неожиданный формат даты или
          // COMMENTS не в JSON) не должен ронять загрузку ВСЕГО списка —
          // раньше именно это приводило к тому, что вся синхронизация
          // падала и приложение молча откатывалось на устаревший
          // локальный кэш навсегда, включая уже удалённые на сайте корзины.
          debugPrint('loadCarts: пропускаю заказ, не удалось распарсить: $parseError, данные: $e');
        }
      }
      return carts;
    } on DioException catch (e) {
      debugPrint('loadCarts: ошибка сети: ${e.message}, ответ сервера: ${e.response?.data}');
      throw CartApiException('Не удалось загрузить корзины');
    }
  }

  /// Перезаписывает состав корзины целиком (все товары разом). Сервер
  /// проверяет, что заказ принадлежит этому manager_id и сайту centrkrasok,
  /// и что он ещё в статусе "в работе" — при несовпадении вернёт ошибку.
  /// [coupons]: не передавайте, чтобы оставить текущие купоны как есть;
  /// передайте пустой список, чтобы снять все купоны; передайте список
  /// кодов, чтобы применить/сменить набор купонов сразу (можно несколько —
  /// общая скидка и купон на конкретный товар не исключают друг друга;
  /// сервер проверит каждый на существование и активность в Bitrix).
  Future<void> updateCartItems({
    required String basketId,
    required int managerId,
    required List<CartItem> items,
    Object? coupons = _unsetCoupons,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_pronsBaseUrl/cart_save.php',
        data: {
          'action': 'update_products',
          'basket_id': basketId,
          'manager_id': managerId.toString(),
          'products_info': encodeCartItems(items),
          if (!identical(coupons, _unsetCoupons))
            'coupons': jsonEncode((coupons as List<String>?) ?? []),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final data = _ensureMap(response.data);
      if (data['error'] != null) {
        throw CartApiException(data['error'].toString());
      }
    } on DioException catch (e) {
      debugPrint('updateCartItems: ошибка сети: ${e.message}, ответ сервера: ${e.response?.data}');
      throw CartApiException('Не удалось сохранить товары корзины');
    }
  }

  /// Завершает корзину — статус "оформлена" или "удалена". Разрешено
  /// только из статуса "в работе" — сервер отклонит повторную смену.
  Future<void> setCartStatus({
    required String basketId,
    required int managerId,
    required CartStatus status,
  }) async {
    if (status == CartStatus.inProgress) {
      throw ArgumentError('setCartStatus поддерживает только completed/deleted');
    }

    await _requireInternet();

    try {
      final response = await dio.post(
        '$_pronsBaseUrl/cart_save.php',
        data: {
          'action': 'set_status',
          'basket_id': basketId,
          'manager_id': managerId.toString(),
          'status': status.label,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final data = _ensureMap(response.data);
      if (data['error'] != null) {
        throw CartApiException(data['error'].toString());
      }
    } on DioException catch (e) {
      debugPrint('setCartStatus: ошибка сети: ${e.message}, ответ сервера: ${e.response?.data}');
      throw CartApiException('Не удалось изменить статус корзины');
    }
  }

  Map<String, dynamic> _ensureMap(dynamic data) {
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // падает ниже в общий случай ошибки формата
      }
    }
    if (data is Map<String, dynamic>) return data;
    throw CartApiException('Некорректный формат ответа сервера');
  }
}

class CartApiException implements Exception {
  final String message;
  CartApiException(this.message);

  @override
  String toString() => message;
}
