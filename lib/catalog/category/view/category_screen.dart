import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:centrkrasok/repositories/products/products.dart';
import 'package:centrkrasok/catalog/filter/filter_screen.dart';
import 'package:centrkrasok/common/animated_search_bar.dart';
import 'package:centrkrasok/catalog/product_list/widgets/product_tile.dart';
import 'package:centrkrasok/common/menu/menu_screen.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:centrkrasok/catalog/favorites/favorites_screen.dart';
import 'package:centrkrasok/catalog/compare/compare_screen.dart';
import 'package:centrkrasok/catalog/widgets/category_thumbnail.dart';

class CategoryScreen extends StatefulWidget {
  final Section section;
  final List<Product> allProducts;
  final List<Section> allSections;

  const CategoryScreen({
    super.key,
    required this.section,
    required this.allProducts,
    required this.allSections,
  });

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final _repository = ProductsRepository(dio: Dio());
  final _scrollController = ScrollController();

  final List<Product> _products = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  static const int _limit = 50;

  // Фильтры
  List<FilterDef> _filterDefs = [];
  RangeValues _priceRange = const RangeValues(0, 100000000);
  ActiveFilters _activeFilters = const ActiveFilters();
  bool _filtersLoaded = false;
  final _filterDio = Dio();
  static const _baseUrl = 'https://prons.kz/ajax/centrkrasok';

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadFilters();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadProducts();
    }
  }

  Future<void> _loadProducts() async {
    if (_loading || !_hasMore) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _repository.getProducts(
        sectionId: int.parse(widget.section.id),
        page: _page,
        limit: _limit,
        section: widget.section, // передаём для офлайн-режима
      );

      if (!mounted) return;
      debugPrint('Секция ${widget.section.id} (${widget.section.name}): ${result.products.length} товаров, hasMore=${result.hasMore}');
      setState(() {
        _products.addAll(result.products);
        _hasMore = result.hasMore;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _menuOpen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          sections: widget.allSections,
          products: const [],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.section.name),
        centerTitle: true,
        actions: [
          const CatalogSearchBar(),
          IconButton(
            icon: const Icon(Icons.menu_outlined),
            onPressed: _menuOpen,
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Плашка фильтров
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                // Кнопка Фильтры
                GestureDetector(
                  onTap: _filtersLoaded ? _openFilter : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: !_filtersLoaded
                          ? Colors.grey.shade200
                          : _activeFilters.isEmpty
                              ? const Color(0xFFF3F2F7)
                              : const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!_filtersLoaded)
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.grey,
                          ),
                        )
                      else
                        Icon(Icons.tune,
                          size: 16,
                          color: _activeFilters.isEmpty ? Colors.black87 : Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        !_filtersLoaded
                            ? 'Загрузка...'
                            : _activeFilters.isEmpty
                                ? 'Фильтры'
                                : 'Фильтры (${_activeFilters.activeCount})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: !_filtersLoaded
                              ? Colors.grey
                              : _activeFilters.isEmpty ? Colors.black87 : Colors.white,
                        ),
                      ),
                    ]),
                  ),
                ),
                const Spacer(),
                // Избранное
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/favorites'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: SvgPicture.asset(
                      'assets/icons/heart.svg',
                      width: 22, height: 22,
                      colorFilter: const ColorFilter.mode(
                        Colors.black54, BlendMode.srcIn),
                    ),
                  ),
                ),
                // Сравнение
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/compare'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: SvgPicture.asset(
                      'assets/icons/compare.svg',
                      width: 22, height: 22,
                      colorFilter: const ColorFilter.mode(
                        Colors.black54, BlendMode.srcIn),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          // Подкатегории
          if (widget.section.children.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Подкатегории',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final child = widget.section.children[i];
                  return ListTile(
                    leading: CategoryThumbnail(imageUrl: child.image),
                    title: Text(child.name),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryScreen(
                          section: child,
                          allProducts: const [],
                          allSections: widget.allSections,
                        ),
                      ),
                    ),
                  );
                },
                childCount: widget.section.children.length,
              ),
            ),
            const SliverToBoxAdapter(child: Divider()),
          ],

          // Заголовок товаров
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '${_products.length}${_hasMore ? '+' : ''} товар${_suffix(_products.length)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),

          // Сетка товаров
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width >= 576 ? 3 : 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ProductTile(product: _products[i]),
                childCount: _products.length,
              ),
            ),
          ),

          // Лоадер / ошибка / конец
          SliverToBoxAdapter(child: _buildFooter()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.catalog),
    );
  }

  Future<void> _loadFilters() async {
    try {
      final response = await _filterDio.get(
        '$_baseUrl/get_filters.php',
        queryParameters: {'section_id': widget.section.id},
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data as String) as Map<String, dynamic>;
      final price = json['price'] as Map<String, dynamic>?;
      final filtersJson = json['filters'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _filterDefs = filtersJson
            .map((e) => FilterDef.fromJson(e as Map<String, dynamic>))
            .toList();
        if (price != null) {
          _priceRange = RangeValues(
            (price['min'] as num).toDouble(),
            (price['max'] as num).toDouble(),
          );
        }
        _filtersLoaded = true;
      });
    } catch (e, st) {
      debugPrint('_loadFilters ERROR: $e');
      debugPrint('$st');
      // Нет сети (или сервер недоступен) — строим варианты фильтра из
      // уже закэшированных товаров этого раздела вместо того, чтобы
      // просто оставить кнопку "Фильтры" неактивной навсегда.
      try {
        final offline = await _repository.buildOfflineFilterDefs(widget.section);
        if (!mounted) return;
        setState(() {
          _filterDefs = offline.filters;
          _priceRange = offline.priceRange;
          _filtersLoaded = true;
        });
      } catch (e2) {
        debugPrint('_loadFilters офлайн-фолбэк тоже не удался: $e2');
        if (mounted) setState(() => _filtersLoaded = true);
      }
    }
  }

  Future<void> _openFilter() async {
    final result = await Navigator.of(context).push<ActiveFilters>(
      MaterialPageRoute(
        builder: (_) => FilterScreen(
          filters: _filterDefs,
          priceRange: _priceRange,
          initial: _activeFilters,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _activeFilters = result;
        _products.clear();
        _hasMore = true;
        _page = 1;
      });
      if (_activeFilters.isEmpty) {
        _loadProducts();
      } else {
        _applyFilters();
      }
    }
  }

  Future<void> _applyFilters() async {
    setState(() { _loading = true; _error = null; });
    try {
      final payload = {
        'section_id': int.tryParse(widget.section.id) ?? 0,
        'page': 1,
        'limit': 50,
        'filters': _activeFilters.toRequestPayload(),
      };
      debugPrint('FILTER PAYLOAD: ' + jsonEncode(payload));
      final response = await _filterDio.post(
        '$_baseUrl/get_products_filtered.php',
        data: jsonEncode(payload),
        options: Options(contentType: 'application/json', responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data as String) as Map<String, dynamic>;
      final rawList = json['products'];
      final list = (rawList is List ? rawList : <dynamic>[])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = json['meta'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(list);
        _hasMore = meta['has_more'] == true;
        _loading = false;
      });
    } catch (e) {
      // Нет сети (или сервер недоступен) — применяем те же фильтры локально
      // к уже закэшированным товарам раздела, вместо того чтобы просто
      // показать ошибку.
      debugPrint('_applyFilters: сеть не удалась ($e), пробуем офлайн-фильтрацию');
      try {
        final list = await _repository.applyFiltersOffline(widget.section, _activeFilters);
        if (!mounted) return;
        setState(() {
          _products
            ..clear()
            ..addAll(list);
          _hasMore = false; // офлайн — сразу все подходящие товары, без пагинации
          _loading = false;
        });
      } catch (e2) {
        if (mounted) setState(() { _error = e2.toString(); _loading = false; });
      }
    }
  }

  Widget _buildFooter() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          TextButton(onPressed: _loadProducts, child: const Text('Повторить')),
        ]),
      );
    }
    if (!_hasMore && _products.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('Все товары загружены: ${_products.length}',
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String _suffix(int n) {
    final l = n % 10;
    final l2 = n % 100;
    if (l2 >= 11 && l2 <= 14) return 'ов';
    if (l == 1) return '';
    if (l >= 2 && l <= 4) return 'а';
    return 'ов';
  }
}
