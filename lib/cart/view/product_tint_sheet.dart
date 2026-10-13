import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:centrkrasok/cart/cart_api_service.dart';
import 'package:centrkrasok/cart/cart_local_store.dart';
import 'package:centrkrasok/cart/models/cart_model.dart';
import 'package:centrkrasok/cart/models/room_options.dart';
import 'package:centrkrasok/cart/tint_api_service.dart';
import 'package:centrkrasok/customer/customer_storage.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';

const _green = Color(0xFF4CAF50);
const _fieldBg = Color(0xFFF5F5F5);

/// Показывать ли «Колеровать» — ровно как на сайте
/// (catalog.element: `if ($arResult['PROPERTIES']['color_da']['VALUE'])`):
/// кнопка есть у всех товаров, где свойство color_da заполнено — и «Да»,
/// и «Нет». Само свойство называется «Колеровка обязательна»: «Да» значит,
/// что без колеровки товар не продаётся, «Нет» — колеровка по желанию.
bool canTintProduct(Product p) => (p.props['color_da']?.value ?? '').trim().isNotEmpty;

/// «Колеровать» с детальной карточки — то же, что модальное окно
/// pronsProductTintModal на сайте (Prons\Tint::addToBasket): цвет из
/// палитр (или «Нет цвета» вручную), помещение, площадь, кастомизация,
/// количество → товар с колеровкой в текущую корзину.
Future<void> showProductTintSheet(BuildContext context, Product product) async {
  final current = await CartLocalStore.loadCurrent();
  if (current == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала выберите клиента — «Анкета лида» или «Существующий клиент»')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ProductTintSheet(product: product, cart: current),
  );
  if (added == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Товар с колеровкой добавлен в корзину')),
    );
  }
}

class _ProductTintSheet extends StatefulWidget {
  const _ProductTintSheet({required this.product, required this.cart});
  final Product product;
  final Cart cart;

  @override
  State<_ProductTintSheet> createState() => _ProductTintSheetState();
}

class _ProductTintSheetState extends State<_ProductTintSheet> {
  final _tintApi = TintApiService(dio: Dio());
  final _cartApi = CartApiService(dio: Dio());

  final _searchCtrl = TextEditingController();
  final _squareCtrl = TextEditingController();
  final _customCtrl = TextEditingController();
  final _manualNameCtrl = TextEditingController();
  final _manualPaletteCtrl = TextEditingController();

  int? _managerId;
  List<TintPalette> _palettes = [];
  String _paletteCode = 'all';
  bool _palettesLoading = true;

  List<TintColor> _results = [];
  bool _searching = false;
  bool _searched = false;

  TintColor? _selected;
  bool _manual = false; // «Нет цвета» — колеровка и палитра вручную
  String _room = 'Без значения';
  int _quantity = 1;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _managerId = await CustomerStorage.currentManagerId();
    if (_managerId == null) {
      setState(() { _palettesLoading = false; _error = 'Не удалось определить менеджера'; });
      return;
    }
    try {
      final p = await _tintApi.loadPalettes(managerId: _managerId!);
      if (mounted) setState(() => _palettes = p);
    } catch (e) {
      if (mounted) setState(() => _error = 'Палитры не загрузились: $e');
    } finally {
      if (mounted) setState(() => _palettesLoading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_searchCtrl, _squareCtrl, _customCtrl, _manualNameCtrl, _manualPaletteCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty || _managerId == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _searching = true; _error = null; });
    try {
      final r = await _tintApi.search(managerId: _managerId!, q: q, paletteCode: _paletteCode);
      if (mounted) setState(() { _results = r; _searched = true; });
    } catch (e) {
      if (mounted) setState(() => _error = 'Поиск не удался: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  double get _price {
    final prices = widget.product.prices;
    if (prices.isEmpty) return 0;
    final retail = prices.where((p) => p.typeId == '30').toList();
    final source = retail.isNotEmpty ? retail : prices;
    return source.map((p) => p.price).reduce((a, b) => a < b ? a : b);
  }

  Future<void> _submit() async {
    final tintName = _manual ? _manualNameCtrl.text.trim() : (_selected?.name ?? '');
    final tintPalette = _manual ? _manualPaletteCtrl.text.trim() : (_selected?.palette ?? '');
    final tintRgb = _manual ? '' : (_selected?.color ?? '');
    if (tintName.isEmpty || tintPalette.isEmpty) {
      setState(() => _error = _manual ? 'Укажите колеровку и палитру' : 'Найдите и выберите цвет');
      return;
    }
    if (_managerId == null) return;

    final props = <String, String>{
      if ((widget.product.brend ?? '').isNotEmpty) 'BREND': widget.product.brend!,
      'TINT_NAME': tintName,
      'TINT_COLLECTION': tintPalette,
      if (tintRgb.isNotEmpty) 'TINT_RGB': tintRgb,
      if (_customCtrl.text.trim().isNotEmpty) 'TINT_CUSTOMIZATION': _customCtrl.text.trim(),
      if (_room.isNotEmpty) 'SELECT_ROOM': _room,
      if (_squareCtrl.text.trim().isNotEmpty) 'ROOM_SQUARE': _squareCtrl.text.trim(),
    };

    setState(() { _saving = true; _error = null; });
    final productId = int.tryParse(widget.product.id) ?? 0;
    final items = List<CartItem>.from(widget.cart.items);
    // Как на сайте: тот же товар с тем же цветом и помещением — прибавляем
    // количество; другой цвет — отдельная позиция корзины.
    bool same(CartItem i) =>
        i.productId == productId &&
        i.props['TINT_NAME'] == props['TINT_NAME'] &&
        i.props['TINT_COLLECTION'] == props['TINT_COLLECTION'] &&
        (i.props['TINT_CUSTOMIZATION'] ?? '') == (props['TINT_CUSTOMIZATION'] ?? '') &&
        (i.props['SELECT_ROOM'] ?? '') == (props['SELECT_ROOM'] ?? '') &&
        (i.props['TINT_PRICE'] ?? '').isEmpty;
    final index = items.indexWhere(same);
    if (index == -1) {
      items.add(CartItem(
        productId: productId,
        name: widget.product.name,
        quantity: _quantity.toDouble(),
        price: _price,
        customPrice: true,
        props: props,
      ));
    } else {
      items[index] = items[index].copyWith(
        quantity: items[index].quantity + _quantity,
        props: {...items[index].props, ...props},
      );
    }

    try {
      await _cartApi.updateCartItems(basketId: widget.cart.id, managerId: _managerId!, items: items);
      await CartLocalStore.updateItems(widget.cart.id, items);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _error = 'Не удалось добавить товар: $e'; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final paletteName = _paletteCode == 'all'
        ? 'Все палитры'
        : _palettes.firstWhere((p) => p.code == _paletteCode, orElse: () => TintPalette(code: _paletteCode, name: _paletteCode)).name;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(children: [
              const Expanded(child: Text('Выберите цвет', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), children: [
              Text(widget.product.name, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              const SizedBox(height: 12),

              // --- Палитра + поиск (или «Нет цвета») ---
              if (!_manual) ...[
                _PickerField(
                  label: _palettesLoading ? 'Загрузка палитр…' : paletteName,
                  onTap: _palettesLoading
                      ? null
                      : () async {
                          final picked = await showSearchablePicker(
                            context,
                            title: 'Палитра',
                            items: ['Все палитры', ..._palettes.map((p) => p.name)],
                            selected: paletteName,
                          );
                          if (picked == null) return;
                          setState(() {
                            _paletteCode = picked == 'Все палитры'
                                ? 'all'
                                : _palettes.firstWhere((p) => p.name == picked).code;
                          });
                        },
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: _dec('Поиск колеровки…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _searching ? null : _search,
                      child: _searching
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search),
                    ),
                  ),
                ]),
                if (_selected != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _ColorRow(color: _selected!, selected: true, onTap: null),
                  ),
                if (_searched && _results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('Не найдено', style: TextStyle(color: Colors.grey)),
                  ),
                if (_results.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final c = _results[i];
                        final sel = _selected?.name == c.name && _selected?.palette == c.palette;
                        return _ColorRow(color: c, selected: sel, onTap: () => setState(() {
                          _selected = c;
                          _results = [];
                        }));
                      },
                    ),
                  ),
              ] else ...[
                TextField(controller: _manualNameCtrl, decoration: _dec('Колеровка')),
                const SizedBox(height: 8),
                TextField(controller: _manualPaletteCtrl, decoration: _dec('Палитра')),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() { _manual = !_manual; _error = null; }),
                  child: Text(_manual ? '← Найти цвет в палитрах' : 'Нет цвета — ввести вручную'),
                ),
              ),

              const Divider(height: 24),

              // --- Параметры позиции ---
              const _Label('Выбор помещения'),
              _PickerField(
                label: _room,
                onTap: () async {
                  final picked = await showSearchablePicker(context,
                      title: 'Помещение', items: roomOptions, selected: _room);
                  if (picked != null) setState(() => _room = picked);
                },
              ),
              const SizedBox(height: 12),
              const _Label('Площадь'),
              TextField(controller: _squareCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _dec('м²')),
              const SizedBox(height: 12),
              const _Label('Кастомизация'),
              TextField(controller: _customCtrl, decoration: _dec('Например: 50% от оттенка')),
              const SizedBox(height: 12),
              const _Label('Количество'),
              Row(children: [
                _QtyBtn(icon: Icons.remove, onTap: _quantity > 1 ? () => setState(() => _quantity--) : null),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text('$_quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                _QtyBtn(icon: Icons.add, onTap: () => setState(() => _quantity++)),
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: Text(_saving ? 'Добавляем…' : 'Добавить в корзину',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: _fieldBg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );

Color _hex(String hex) {
  final h = hex.replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? Colors.grey.shade300 : Color(v);
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15))),
            const Icon(Icons.keyboard_arrow_down),
          ]),
        ),
      );
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.color, required this.selected, required this.onTap});
  final TintColor color;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        onTap: onTap,
        leading: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: _hex(color.color), shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300)),
        ),
        title: Text(color.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(color.palette, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        trailing: selected ? const Icon(Icons.check_circle, color: _green) : null,
      );
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: _fieldBg,
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, size: 20))),
      );
}

/// Список с полем поиска сверху (палитры, помещения).
Future<String?> showSearchablePicker(BuildContext context,
    {required String title, required List<String> items, String? selected}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _SearchList(title: title, items: items, selected: selected),
  );
}

class _SearchList extends StatefulWidget {
  const _SearchList({required this.title, required this.items, this.selected});
  final String title;
  final List<String> items;
  final String? selected;
  @override
  State<_SearchList> createState() => _SearchListState();
}

class _SearchListState extends State<_SearchList> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final words = _q.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final list = words.isEmpty
        ? widget.items
        : widget.items.where((i) => words.every(i.toLowerCase().contains)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: _dec('Поиск: ${widget.title.toLowerCase()}').copyWith(prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Ничего не найдено', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final item = list[i];
                      final sel = item == widget.selected;
                      return ListTile(
                        title: Text(item, style: TextStyle(fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                        trailing: sel ? const Icon(Icons.check, color: _green) : null,
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
