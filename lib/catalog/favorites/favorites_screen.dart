import 'package:flutter/material.dart';
import 'package:centrkrasok/catalog/favorites/favorites_service.dart';
import 'package:centrkrasok/catalog/product_list/widgets/product_tile.dart';
import 'package:centrkrasok/common/animated_search_bar.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Product> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Обновляем список когда меняется состояние избранного (удаление через иконку)
    FavoritesState.instance.addListener(_onFavoritesChanged);
  }

  @override
  void dispose() {
    FavoritesState.instance.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    // Убираем из списка товары которые были удалены из избранного
    if (!mounted) return;
    setState(() {
      _items = _items
          .where((p) => FavoritesState.instance.isFavorite(int.tryParse(p.id) ?? 0))
          .toList();
    });
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await FavoritesService.instance.loadFavorites();
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Избранное'),
        centerTitle: false,
        actions: const [CatalogSearchBar(), SizedBox(width: 8)],
      ),
      body: _buildBody(),
      bottomNavigationBar: const AppBottomNavBar(currentTab: null),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)));
    }

    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 48),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: _load, child: const Text('Повторить')),
      ]));
    }

    if (_items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.favorite_border, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text('Нет отложенных товаров',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        const SizedBox(height: 8),
        Text('Нажмите ♥ на карточке товара чтобы добавить',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          textAlign: TextAlign.center),
      ]));
    }

    return RefreshIndicator(
      color: const Color(0xFF4CAF50),
      onRefresh: _load,
      child: Column(children: [
        // Счётчик
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Text('${_items.length} товаров',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
              onPressed: _confirmClearAll,
              child: Text('Удалить всё',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ),
          ]),
        ),
        // Сетка товаров — такие же карточки как в каталоге
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.62,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _items.length,
            itemBuilder: (_, i) => ProductTile(product: _items[i]),
          ),
        ),
      ]),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить всё избранное?'),
        content: const Text('Все отложенные товары будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (final item in List.from(_items)) {
        await FavoritesService.instance.toggle(int.tryParse(item.id) ?? 0);
      }
    }
  }
}
