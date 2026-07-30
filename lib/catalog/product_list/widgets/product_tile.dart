import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:centrkrasok/catalog/favorites/favorites_service.dart';
import 'package:centrkrasok/catalog/compare/compare_store.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';

final _unescape = HtmlUnescape();

class ProductTile extends StatefulWidget {
  const ProductTile({super.key, required this.product});
  final Product product;

  @override
  State<ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<ProductTile> {
  bool _isFavorite = false;
  bool _favoriteLoading = false;
  bool _isCompared = false;
  bool _compareLoading = false;

  int get _productId => int.tryParse(widget.product.id) ?? 0;

  double get _price {
    if (widget.product.prices.isEmpty) return 0;
    // Предпочитаем подтверждённую розничную группу (30 — "Розничная
    // ИСПОЛЬЗОВАТЬ"), если она есть у товара — та же логика, что в
    // карточке товара и сравнении.
    final retail = widget.product.prices.where((p) => p.typeId == '30').toList();
    final source = retail.isNotEmpty ? retail : widget.product.prices;
    return source.map((p) => p.price).reduce((a, b) => a < b ? a : b);
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
  void initState() {
    super.initState();
    _isFavorite = FavoritesState.instance.isFavorite(_productId);
    FavoritesState.instance.addListener(_onStateChanged);
    _isCompared = CompareState.instance.isCompared(_productId);
    CompareState.instance.addListener(_onCompareChanged);
  }

  @override
  void dispose() {
    FavoritesState.instance.removeListener(_onStateChanged);
    CompareState.instance.removeListener(_onCompareChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    final isFav = FavoritesState.instance.isFavorite(_productId);
    if (isFav != _isFavorite) {
      setState(() => _isFavorite = isFav);
    }
  }

  void _onCompareChanged() {
    if (!mounted) return;
    final isComp = CompareState.instance.isCompared(_productId);
    if (isComp != _isCompared) setState(() => _isCompared = isComp);
  }

  Future<void> _toggleCompare() async {
    if (_compareLoading) return;
    setState(() => _compareLoading = true);
    await CompareStore.instance.toggle(widget.product);
    if (mounted) setState(() => _compareLoading = false);
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading) return;
    setState(() => _favoriteLoading = true);
    await FavoritesService.instance.toggle(_productId);
    if (mounted) setState(() => _favoriteLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/products-item', arguments: widget.product),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Картинка
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: SizedBox(
                  width: double.infinity,
                  child: widget.product.image != null && widget.product.image!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.product.image!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey.shade100,
                            child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade100,
                          child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
                        ),
                ),
              ),
            ),

            // Текстовая часть
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_price > 0)
                    Text(
                      _fmt(_price),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _unescape.convert(widget.product.name),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // ── Три иконки ───────────────────────────────────
            Row(
              children: [
                // Корзина
                Expanded(
                  child: _IconBtn(
                    svgAsset: 'assets/icons/shopping-cart.svg',
                    color: Colors.black54,
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Корзина скоро будет доступна')),
                    ),
                  ),
                ),

                // Избранное (сердце)
                Expanded(
                  child: _favoriteLoading
                      ? const SizedBox(
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF4CAF50)),
                            ),
                          ),
                        )
                      : _IconBtn(
                          svgAsset: 'assets/icons/heart.svg',
                          // Зелёный если в избранном, серый если нет
                          color: _isFavorite
                              ? const Color(0xFF4CAF50)
                              : Colors.black54,
                          onTap: _toggleFavorite,
                        ),
                ),

                // Сравнение
                Expanded(
                  child: _compareLoading
                      ? const SizedBox(height: 40,
                          child: Center(child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4CAF50)))))
                      : _IconBtn(
                          svgAsset: 'assets/icons/compare.svg',
                          color: _isCompared ? const Color(0xFF4CAF50) : Colors.black54,
                          onTap: _toggleCompare,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка с SVG иконкой
class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.svgAsset,
    required this.color,
    required this.onTap,
  });
  final String svgAsset;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 40,
        child: Center(
          child: SvgPicture.asset(
            svgAsset,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
