import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:centrkrasok/customer/customer_storage.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';

/// Глобальное состояние избранного.
/// Хранит Set product_id отложенных товаров — для мгновенной подсветки иконок.
/// Данные синхронизируются с сервером при каждом toggle и при загрузке экрана.
class FavoritesState {
  FavoritesState._();
  static final FavoritesState instance = FavoritesState._();

  // ID товаров в избранном (быстрая проверка без запроса к серверу)
  final Set<int> _ids = {};

  bool isFavorite(int productId) => _ids.contains(productId);

  void _setIds(List<int> ids) {
    _ids
      ..clear()
      ..addAll(ids);
    _notifyListeners();
  }

  void _toggle(int productId, bool isFavorite) {
    if (isFavorite) {
      _ids.add(productId);
    } else {
      _ids.remove(productId);
    }
    _notifyListeners();
  }

  // Слушатели для обновления UI (ProductTile)
  final List<void Function()> _listeners = [];
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void _notifyListeners() {
    for (final l in _listeners) {
      l();
    }
  }
}

/// Сервис для работы с избранным через сервер (prons.kz/ajax/centrkrasok).
class FavoritesService {
  static const _baseUrl = 'https://prons.kz/ajax/centrkrasok';
  final _dio = Dio();

  static final FavoritesService instance = FavoritesService._();
  FavoritesService._();

  /// Загружает список отложенных товаров с сервера.
  /// Обновляет FavoritesState._ids для подсветки иконок.
  Future<List<Product>> loadFavorites() async {
    final managerId = await CustomerStorage.currentManagerId();
    if (managerId == null) return [];

    try {
      final resp = await _dio.get(
        '$_baseUrl/favorites_get.php',
        queryParameters: {'manager_id': managerId},
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(resp.data as String) as Map<String, dynamic>;
      if (json['success'] != true) return [];

      // Обновляем глобальное состояние
      final ids = (json['product_ids'] as List? ?? [])
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((id) => id > 0)
          .toList();
      FavoritesState.instance._setIds(ids);

      // Возвращаем полные данные товаров
      return (json['items'] as List? ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Добавляет или удаляет товар из избранного.
  /// Мгновенно обновляет локальное состояние, затем синхронизирует с сервером.
  Future<bool> toggle(int productId) async {
    debugPrint('FAVORITES toggle: productId=$productId');
    final managerId = await CustomerStorage.currentManagerId();
    debugPrint('FAVORITES toggle: managerId=$managerId');
    if (managerId == null) {
      debugPrint('FAVORITES toggle: managerId is null — прерываем');
      return false;
    }

    // Оптимистичное обновление UI — сразу меняем иконку
    final wasFavorite = FavoritesState.instance.isFavorite(productId);
    FavoritesState.instance._toggle(productId, !wasFavorite);
    debugPrint('FAVORITES toggle: wasFavorite=$wasFavorite → toggled to ${!wasFavorite}');

    try {
      debugPrint('FAVORITES toggle: отправляем POST на favorites_toggle.php');
      final resp = await _dio.post(
        '$_baseUrl/favorites_toggle.php',
        data: jsonEncode({
          'manager_id': managerId,
          'product_id': productId,
        }),
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.plain,
          // Не бросаем исключение при 500 — читаем тело ответа
          validateStatus: (status) => true,
        ),
      );
      debugPrint('FAVORITES toggle: статус=${resp.statusCode} ответ=${resp.data}');
      final json = jsonDecode(resp.data as String) as Map<String, dynamic>;
      if (json['success'] == true) {
        final isFav = json['is_favorite'] as bool? ?? !wasFavorite;
        debugPrint('FAVORITES toggle: success! is_favorite=$isFav');
        FavoritesState.instance._toggle(productId, isFav);
        if (isFav) {
          FavoritesState.instance._ids.add(productId);
        } else {
          FavoritesState.instance._ids.remove(productId);
        }
        FavoritesState.instance._notifyListeners();
        return true;
      } else {
        debugPrint('FAVORITES toggle: сервер вернул success=false: $json');
        FavoritesState.instance._toggle(productId, wasFavorite);
        return false;
      }
    } catch (e) {
      debugPrint('FAVORITES toggle: ОШИБКА — $e');
      FavoritesState.instance._toggle(productId, wasFavorite);
      return false;
    }
  }

  /// Загружает только ID отложенных товаров (для инициализации при старте).
  Future<void> preloadIds() async {
    await loadFavorites();
  }
}
