import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:centrkrasok/repositories/products/local_db.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';

const String _baseUrl = 'https://prons.kz/ajax/centrkrasok';

/// Полная фоновая синхронизация каталога в LocalDb — чтобы офлайн был
/// доступен ВЕСЬ каталог (~50 000 товаров), а не только разделы, которые
/// уже открывали вручную.
///
/// Решение по стратегии (обсуждено с заказчиком): делаем полную
/// пересинхронизацию каждый раз, БЕЗ попытки тянуть только "изменённое"
/// через 'since' — потому что обмен с 1С трогает TIMESTAMP_X у товаров
/// пачками независимо от того, менялось ли реально что-то, поэтому
/// инкрементальная синхронизация по дате не даёт настоящей экономии.
/// Данные текстовые (без картинок, ~50-100 МБ на полный обход),
/// синхронизация разрешена всегда (не только по Wi-Fi) — сотрудники в
/// основном работают по Wi-Fi.
class CatalogSyncService {
  CatalogSyncService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _lastSyncAtKey = 'catalog_full_sync_last_at';
  static const _lastSyncCountKey = 'catalog_full_sync_last_count';
  static const _pageLimit = 1000;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  /// Сколько товаров уже получено в текущем запуске синхронизации —
  /// можно подписаться в UI, если понадобится показать прогресс.
  final ValueNotifier<int> fetchedCount = ValueNotifier<int>(0);

  Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastSyncAtKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<int?> lastSyncCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastSyncCountKey);
  }

  /// Стоит ли сейчас запускать синхронизацию — если её ещё не было, либо
  /// прошло больше [maxAge] с последнего успешного полного обхода.
  Future<bool> shouldSync({Duration maxAge = const Duration(hours: 24)}) async {
    final last = await lastSyncAt();
    if (last == null) return true;
    return DateTime.now().difference(last) > maxAge;
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  /// Полный обход каталога постранично через get_products_full.php.
  /// Безопасно вызывать многократно — если синхронизация уже идёт,
  /// повторный вызов просто ничего не делает (не запускает вторую параллельно).
  Future<void> syncFullCatalog() async {
    if (_isSyncing) return;
    if (!await _hasInternet()) {
      debugPrint('CatalogSyncService: нет сети, синхронизация отложена');
      return;
    }

    _isSyncing = true;
    fetchedCount.value = 0;
    final runStartedAt = DateTime.now().millisecondsSinceEpoch;

    try {
      int page = 1;
      bool hasMore = true;

      while (hasMore) {
        final response = await _dio.get(
          '$_baseUrl/get_products_full.php',
          queryParameters: {'page': page, 'limit': _pageLimit},
          options: Options(responseType: ResponseType.plain),
        );

        final json = jsonDecode(response.data as String) as Map<String, dynamic>;
        final meta = json['meta'] as Map<String, dynamic>;
        final productsJson = json['products'] as List<dynamic>;

        final products = productsJson
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();

        await LocalDb.saveProducts(products, savedAt: runStartedAt);

        fetchedCount.value += products.length;
        hasMore = meta['has_more'] == true;
        debugPrint('CatalogSyncService: страница $page, всего ${fetchedCount.value} товаров');
        page++;
      }

      // Обход завершился без ошибок от первой до последней страницы —
      // теперь безопасно вычистить товары, не подтверждённые этим обходом
      // (сняты с продажи и т.п.). Если бы синхронизация прервалась на
      // середине (см. catch ниже), до этой строки выполнение бы не дошло —
      // и мы бы не удалили ещё активные товары, до которых не успели дойти.
      final removed = await LocalDb.deleteStaleProducts(before: runStartedAt);
      if (removed > 0) {
        debugPrint('CatalogSyncService: убрано $removed товаров, снятых с продажи');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSyncAtKey, runStartedAt);
      await prefs.setInt(_lastSyncCountKey, fetchedCount.value);
      debugPrint('CatalogSyncService: полная синхронизация завершена, ${fetchedCount.value} товаров');
    } catch (e) {
      debugPrint('CatalogSyncService: ошибка синхронизации на странице, прогресс сохранён частично: $e');
      // Ничего не удаляем и не запоминаем как "успешно завершено" —
      // то, что уже сохранили постранично до сбоя, остаётся в кэше
      // (это всё равно свежее, чем было), но каталог не считается
      // полностью синхронизированным, и уборка устаревших не выполняется.
    } finally {
      _isSyncing = false;
    }
  }
}
