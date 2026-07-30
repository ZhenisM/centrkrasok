import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:centrkrasok/repositories/products/products.dart';
import 'package:centrkrasok/repositories/products/local_db.dart';
import 'package:centrkrasok/catalog/filter/filter_screen.dart';

const String _baseUrl = 'https://prons.kz/ajax/centrkrasok';

class ProductsRepository {
  ProductsRepository({required this.dio});

  final Dio dio;

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // Собирает все ID секции и её дочерних секций рекурсивно
  List<String> _collectSectionIds(Section section) {
    final ids = <String>[section.id];
    for (final child in section.children) {
      ids.addAll(_collectSectionIds(child));
    }
    return ids;
  }

  // -------------------------------------------------------
  // Секции
  // -------------------------------------------------------
  Future<List<Section>> getSections() async {
    final online = await _hasInternet();

    if (!online) {
      debugPrint('getSections: offline, читаем из кэша');
      return LocalDb.loadSections();
    }

    try {
      final response = await dio.get('$_baseUrl/get_sections.php');
      final data = response.data as Map<String, dynamic>;
      final sectionsJson = data['sections'] as List<dynamic>;
      final sections = sectionsJson
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList();

      LocalDb.saveSections(sections).then((_) {
        debugPrint('getSections: сохранено ${sections.length} разделов');
      });

      return sections;
    } catch (e) {
      debugPrint('getSections: ошибка сети, читаем из кэша: $e');
      return LocalDb.loadSections();
    }
  }

  // -------------------------------------------------------
  // -------------------------------------------------------
  // Товары по списку ID (для отображения в мультикорзине)
  // Кэшируются в SharedPreferences по productId — работает offline
  // -------------------------------------------------------
  static const _cacheKey = 'products_by_id_cache';

  Future<void> _cacheRawProducts(List<dynamic> rawProducts) async {
    if (rawProducts.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_cacheKey);
      final Map<String, dynamic> cache = existing != null
          ? jsonDecode(existing) as Map<String, dynamic>
          : {};
      for (final raw in rawProducts) {
        final map = raw as Map<String, dynamic>;
        final id = map['id']?.toString();
        if (id != null) cache[id] = jsonEncode(map);
      }
      await prefs.setString(_cacheKey, jsonEncode(cache));
    } catch (e) {
      debugPrint('_cacheRawProducts: ошибка: $e');
    }
  }

  Future<List<Product>> _loadFromCache(List<String> ids) async {
    // Источник 1: узкий кэш "товары по ID" (SharedPreferences) — заполняется
    // только когда товар уже показывался именно в корзине при интернете.
    final found = <String, Product>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_cacheKey);
      if (existing != null) {
        final cache = jsonDecode(existing) as Map<String, dynamic>;
        for (final id in ids) {
          if (cache.containsKey(id)) {
            final map = jsonDecode(cache[id] as String) as Map<String, dynamic>;
            found[id] = Product.fromJson(map);
          }
        }
      }
    } catch (e) {
      debugPrint('_loadFromCache: ошибка чтения products_by_id_cache: $e');
    }

    // Источник 2: общий кэш каталога (LocalDb/sqflite) — наполняется при
    // обычном офлайн-просмотре разделов. Раньше сюда не заглядывали вообще,
    // из-за чего товары, добавленные в корзину офлайн, но ни разу не
    // показанные именно в корзине при интернете, оставались без
    // названия/цены/картинки, даже если реально лежали в кэше каталога.
    final missing = ids.where((id) => !found.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final fromCatalog = await LocalDb.loadProductsByIds(missing);
      for (final p in fromCatalog) {
        found[p.id] = p;
      }
    }

    final result = ids.where(found.containsKey).map((id) => found[id]!).toList();
    debugPrint('_loadFromCache: найдено ${result.length}/${ids.length} товаров (id-кэш + каталог)');
    return result;
  }

  Future<List<Product>> getProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];

    final online = await _hasInternet();

    if (!online) {
      debugPrint('getProductsByIds: offline — читаем из кэша');
      return _loadFromCache(ids);
    }

    try {
      final response = await dio.get(
        '$_baseUrl/get_products_by_ids.php',
        queryParameters: {'ids': ids.join(',')},
        options: Options(responseType: ResponseType.plain),
      );

      final raw = response.data as String;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final productsJson = decoded['products'] as List<dynamic>;

      debugPrint('getProductsByIds: получили ${productsJson.length} товаров');

      final products = productsJson
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();

      // Кэшируем для offline (не ждём)
      _cacheRawProducts(productsJson);

      return products;
    } catch (e) {
      debugPrint('getProductsByIds: ошибка ($e), читаем из кэша');
      return _loadFromCache(ids);
    }
  }


  // -------------------------------------------------------
  // собрать товары из всех дочерних секций
  // -------------------------------------------------------
  // ВАЖНО: раньше грузило ВСЕ товары раздела разом (Future.wait по
  // каждой подсекции без ограничения) — для маленьких разделов это было
  // незаметно, но после полной синхронизации каталога некоторые разделы
  // (например, "Люстры") содержат тысячи товаров, и такой единоразовый
  // запрос ронял приложение с OutOfMemoryError на границе Flutter/Android.
  // Теперь поддерживает limit/offset через один комбинированный SQL-запрос.
  Future<List<Product>> _loadCachedProductsForSection(
    int sectionId,
    Section? section, {
    int? limit,
    int? offset,
  }) async {
    final sectionIds = (section != null && section.children.isNotEmpty)
        ? _collectSectionIds(section)
        : [sectionId.toString()];
    debugPrint('_loadCachedProductsForSection: секции ${sectionIds.length}, limit=$limit offset=$offset');
    return LocalDb.loadProductsForSections(sectionIds, limit: limit, offset: offset);
  }

  Future<({List<Product> products, bool hasMore})> getProducts({
    required int sectionId,
    int page = 1,
    int limit = 50,
    Section? section, // передаём для офлайн-режима
  }) async {
    final online = await _hasInternet();

    if (!online) {
      debugPrint('getProducts: offline, читаем из кэша sectionId=$sectionId page=$page');
      final cached = await _loadCachedProductsForSection(
        sectionId, section,
        limit: limit, offset: (page - 1) * limit,
      );
      // Как и на сервере: если пришла полная страница — считаем, что
      // дальше может быть ещё (без лишнего COUNT(*) по всем подсекциям).
      return (products: cached, hasMore: cached.length == limit);
    }

    try {
      final response = await dio.get(
        '$_baseUrl/get_products.php',
        queryParameters: {
          'section_id': sectionId,
          'page': page,
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final meta = data['meta'] as Map<String, dynamic>?;
      final productsJson = data['products'] as List<dynamic>;

      final products = productsJson
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();

      debugPrint('getProducts sectionId=$sectionId page=$page: ${products.length} товаров');

      if (products.isNotEmpty) {
        LocalDb.saveProducts(products).then((_) {
          debugPrint('getProducts: сохранено ${products.length} товаров в кэш');
        });
      }

      return (
      products: products,
      hasMore: meta?['has_more'] == true,
      );
    } catch (e) {
      debugPrint('getProducts: ошибка сети, читаем из кэша: $e');
      final cached = await _loadCachedProductsForSection(
        sectionId, section,
        limit: limit, offset: (page - 1) * limit,
      );
      return (products: cached, hasMore: cached.length == limit);
    }
  }

  // -------------------------------------------------------
  // Фильтры — офлайн-замена get_filters.php / get_products_filtered.php
  // -------------------------------------------------------

  // В отличие от каталога света, где фильтр строился из ВСЕХ свойств за
  // вычетом служебных, для красок сайт показывает конкретный, заранее
  // заданный набор — сверено напрямую со скриншотом сайта и админкой
  // свойств инфоблока ID=87. Порядок ниже совпадает с порядком на сайте.
  // Среди них нет ни одного числового диапазона (кроме цены, которая
  // обрабатывается отдельно) — все они списки с чекбоксами.
  // ПОДТВЕРЖДЕНО диагностикой: для каталога красок реальная розничная
  // цена лежит под CATALOG_GROUP_ID=30 ("Розничная ИСПОЛЬЗОВАТЬ"), а не
  // под ID=1 ("rozn"), как для каталога света — в этом каталоге накопилось
  // много разных типов цен от партнёров/площадок (KASPI, АНД и т.п.).
  static const _retailPriceTypeId = '30';

  static const _filterAllowedCodes = [
    'BREND',
    'SEGMENT',
    'AKCIYA',
    'INTERER',
    'TIP_RABOT',
    'MATERIAL_RABOCHEY_POVERKHNOSTI',
    'TIP_POKRYTIYA',
    'TIPE_PAINT',
    'FASOVKA',
    'color_da',
    'SHIRINA_VALIKA',
    'NAZNACHENIYE_INSTR',
    'STEPEN_BLESKA',
    'UKHOD_ZA_OKRASHENNOY_POVERKHNOSTYU',
    'SERTIFITSIROVANO_DLYA_DETSKIKH_I_LECHEBNYKH_UCHREZ',
    'baza',
    'KUPIT_V_KREDIT',
    'SHIRINA_RABOCHEY_POVERKHNOSTI',
    'TOLSHCHINA_1',
    'DLINA_IZDELIYA',
    'MATERIAL_IZDELIYA',
    'VYSOTA_PO_STENE_SM',
    'SHIRINA_PO_POTOLKU_SM',
    'SHIRINA_PO_POLU_SM',
  ];

  /// Строит определения фильтров (диапазон цены + список вариантов по
  /// каждому свойству) из уже закэшированных офлайн товаров раздела —
  /// офлайн-замена get_filters.php. Работает только с тем, что уже есть
  /// в LocalDb (полная синхронизация каталога / просмотренные разделы).
  Future<({RangeValues priceRange, List<FilterDef> filters})> buildOfflineFilterDefs(Section section) async {
    final sectionIds = section.children.isNotEmpty
        ? _collectSectionIds(section)
        : [section.id];
    final products = await LocalDb.loadAllProductsForSectionsBatched(sectionIds);

    double priceMin = 0, priceMax = 0;
    bool priceSet = false;
    final listValues = <String, Set<String>>{};
    final propNames = <String, String>{};

    for (final p in products) {
      for (final price in p.prices) {
        if (price.typeId != _retailPriceTypeId) continue;
        final v = price.price;
        if (v <= 0) continue;
        if (!priceSet || v < priceMin) priceMin = v;
        if (!priceSet || v > priceMax) priceMax = v;
        priceSet = true;
      }

      for (final entry in p.props.entries) {
        final code = entry.key;
        if (!_filterAllowedCodes.contains(code)) continue;
        final value = entry.value.value.trim();
        if (value.isEmpty) continue;
        propNames.putIfAbsent(code, () => entry.value.name);
        (listValues[code] ??= <String>{}).add(value);
      }
    }

    final filters = <FilterDef>[];
    listValues.forEach((code, values) {
      if (values.isEmpty) return;
      final sorted = values.toList()..sort();
      filters.add(FilterDef(code: code, name: propNames[code] ?? code, type: 'list', values: sorted));
    });

    // Сортировка — строго в порядке, как на сайте (_filterAllowedCodes).
    filters.sort((a, b) =>
        _filterAllowedCodes.indexOf(a.code).compareTo(_filterAllowedCodes.indexOf(b.code)));

    debugPrint('buildOfflineFilterDefs: ${filters.length} фильтров из ${products.length} товаров');

    return (
      priceRange: RangeValues(priceSet ? priceMin : 0, priceSet ? priceMax : 0),
      filters: filters,
    );
  }

  /// Применяет уже выбранные фильтры локально к товарам раздела — офлайн-
  /// замена get_products_filtered.php. Возвращает сразу все подходящие
  /// товары (без серверной пагинации — офлайн-датасет на раздел разумного
  /// размера, догружать постранично не требуется).
  Future<List<Product>> applyFiltersOffline(Section section, ActiveFilters filters) async {
    final sectionIds = section.children.isNotEmpty
        ? _collectSectionIds(section)
        : [section.id];
    final products = await LocalDb.loadAllProductsForSectionsBatched(sectionIds);

    return products.where((p) {
      if (filters.price != null) {
        final hasMatchingPrice = p.prices.any((price) =>
            price.typeId == _retailPriceTypeId &&
            price.price >= filters.price!.start &&
            price.price <= filters.price!.end);
        if (!hasMatchingPrice) return false;
      }

      for (final entry in filters.ranges.entries) {
        final propValue = p.props[entry.key]?.value;
        final n = propValue == null ? null : double.tryParse(propValue);
        if (n == null || n < entry.value.start || n > entry.value.end) return false;
      }

      for (final entry in filters.props.entries) {
        if (entry.value.isEmpty) continue;
        final propValue = p.props[entry.key]?.value;
        if (propValue == null || !entry.value.contains(propValue)) return false;
      }

      return true;
    }).toList();
  }
}
