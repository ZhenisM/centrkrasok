import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:centrkrasok/catalog/compare/compare_store.dart';
import 'package:centrkrasok/common/animated_search_bar.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  List<Product> _items = [];
  bool _loading = true;
  bool _showDiff = false;

  static const double _cardWidth = 180.0;

  @override
  void initState() {
    super.initState();
    _load();
    CompareState.instance.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    CompareState.instance.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() { if (mounted) _load(); }

  Future<void> _load() async {
    final items = await CompareStore.instance.getAll();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _remove(Product p) async =>
      CompareStore.instance.remove(int.tryParse(p.id) ?? 0);

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить сравнение?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) await CompareStore.instance.clear();
  }

  Set<String> _diffKeys() {
    if (_items.length < 2) return {};
    final diffKeys = <String>{};
    for (final (_, key) in kCompareProps) {
      final values = _items.map((p) => CompareStore.getPropValue(p, key)).toSet();
      if (values.length > 1) diffKeys.add(key);
    }
    return diffKeys;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Сравнение'),
        centerTitle: false,
        actions: const [CatalogSearchBar(), SizedBox(width: 8)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : _items.isEmpty ? _buildEmpty() : _buildContent(),
      bottomNavigationBar: const AppBottomNavBar(currentTab: null),
    );
  }

  Widget _buildEmpty() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.compare_arrows, size: 64, color: Colors.grey.shade300),
    const SizedBox(height: 16),
    Text('Нет товаров для сравнения',
      style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
    const SizedBox(height: 8),
    Text('Нажмите на иконку сравнения в карточке товара',
      style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      textAlign: TextAlign.center),
  ]));

  Widget _buildContent() {
    final diffKeys = _showDiff ? _diffKeys() : null;
    final visibleProps = kCompareProps.where((e) {
      if (!_showDiff) return true;
      return diffKeys!.contains(e.$2);
    }).toList();

    return Column(children: [
      // Переключатель Все / Различающиеся
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(children: [
            _TabBtn(label: 'Все',           selected: !_showDiff, onTap: () => setState(() => _showDiff = false)),
            _TabBtn(label: 'Различающиеся', selected: _showDiff,  onTap: () => setState(() => _showDiff = true)),
          ]),
        ),
      ),
      // Счётчик + удалить всё
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Text('${_items.length} товаров',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton(
            onPressed: _clearAll,
            child: Text('Удалить всё',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
        ]),
      ),
      // Горизонтальный скролл
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _items.map((p) => _CompareCard(
                  product: p,
                  visibleProps: visibleProps,
                  cardWidth: _cardWidth,
                  onRemove: () => _remove(p),
                )).toList(),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({required this.label, required this.selected, required this.onTap});
  final String label; final bool selected; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4CAF50) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? Colors.white : Colors.black54,
        )),
      ),
    ),
  );
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.product, required this.visibleProps,
      required this.cardWidth, required this.onRemove});
  final Product product;
  final List<(String, String)> visibleProps;
  final double cardWidth;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: cardWidth,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Картинка + иконка удаления
        Stack(children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: SizedBox(width: cardWidth, height: cardWidth,
              child: product.image != null && product.image!.isNotEmpty
                  ? CachedNetworkImage(imageUrl: product.image!, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey.shade100),
                      errorWidget: (_, __, ___) => Container(color: Colors.grey.shade100,
                        child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey)))
                  : Container(color: Colors.grey.shade100,
                      child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey))),
          ),
          Positioned(
            top: 6, right: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(6),
                child: SvgPicture.asset('assets/icons/trash.svg',
                  colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcIn)),
              ),
            ),
          ),
        ]),
        // Название
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(product.name,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
        // Свойства
        ...visibleProps.map((e) => _PropRow(
          label: e.$1,
          value: CompareStore.getPropValue(product, e.$2),
        )),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _PropRow extends StatelessWidget {
  const _PropRow({required this.label, required this.value});
  final String label; final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
      const SizedBox(height: 1),
      Text(value, style: const TextStyle(fontSize: 11, color: Colors.black87),
        maxLines: 2, overflow: TextOverflow.ellipsis),
    ]),
  );
}
