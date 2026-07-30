import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';
import 'package:centrkrasok/repositories/products/local_db.dart';
import 'package:centrkrasok/catalog/product_list/widgets/product_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});
  final String initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _baseUrl = 'https://prons.kz/ajax/centrkrasok';
  final _dio = Dio();
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  List<Product> _results = [];
  bool _loading = false;
  String? _error;
  String _lastQuery = '';

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      _ctrl.text = widget.initialQuery;
      _search(widget.initialQuery);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.length < 2 || q == _lastQuery) return;
    _lastQuery = q;

    setState(() { _loading = true; _error = null; });

    if (!await _hasInternet()) {
      // Нет сети — сразу ищем в закэшированном офлайн-каталоге, не тратя
      // время на заведомо обречённый сетевой запрос.
      final list = await LocalDb.searchProducts(q, limit: 30);
      if (!mounted) return;
      setState(() { _results = list; _loading = false; });
      return;
    }

    try {
      final response = await _dio.get(
        '$_baseUrl/search_products.php',
        queryParameters: {'q': q, 'limit': 30},
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data as String) as Map<String, dynamic>;
      final list = (json['products'] as List<dynamic>)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() { _results = list; _loading = false; });
    } catch (e) {
      // Сеть была, но запрос не удался (обрыв связи посреди запроса,
      // сервер недоступен и т.п.) — тоже пробуем офлайн-каталог вместо
      // того, чтобы просто показать ошибку.
      debugPrint('_search: сетевой поиск не удался ($e), пробуем офлайн-каталог');
      try {
        final list = await LocalDb.searchProducts(q, limit: 30);
        if (!mounted) return;
        setState(() { _results = list; _loading = false; });
      } catch (_) {
        if (!mounted) return;
        setState(() { _error = 'Не удалось выполнить поиск'; _loading = false; });
      }
    }
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0).split('');
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₸';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _ctrl,
          focusNode: _focus,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          cursorColor: Colors.white,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'Название или артикул...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                setState(() { _results = []; _lastQuery = ''; });
              },
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.catalog),
    );
  }

  Widget _buildBody() {
    if (_ctrl.text.trim().length < 2) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('Введите минимум 2 символа',
            style: TextStyle(color: Colors.grey, fontSize: 15)),
        ]),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, style: const TextStyle(color: Colors.red)),
        TextButton(onPressed: () => _search(_ctrl.text),
          child: const Text('Повторить')),
      ]),
    );
    if (_results.isEmpty) return const Center(
      child: Text('Ничего не найдено',
        style: TextStyle(color: Colors.grey, fontSize: 15)),
    );

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width >= 576 ? 3 : 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.62,
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) => ProductTile(product: _results[i]),
    );
  }
}
