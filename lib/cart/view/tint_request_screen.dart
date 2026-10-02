import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:centrkrasok/cart/tint_basket_service.dart';

/// Страница заявки на колеровку — как /tint/detail.php?ID=… на сайте:
/// проставить цены (вручную или «из базы») и товар колеровки → «Применить»;
/// после — «Изменить» или «Добавить в корзину».
///
/// Возвращает true, если колеровку добавили в корзину (корзине нужно
/// перечитать себя с сервера).
class TintRequestScreen extends StatefulWidget {
  const TintRequestScreen({super.key, required this.tintId});
  final int tintId;

  @override
  State<TintRequestScreen> createState() => _TintRequestScreenState();
}

class _TintRequestScreenState extends State<TintRequestScreen> {
  final _service = TintBasketService(dio: Dio());
  TintDetail? _detail;
  String? _error;
  bool _busy = false;
  bool _changed = false;

  final Map<int, TextEditingController> _priceCtrls = {};
  final Map<int, int?> _tintProduct = {};
  final Map<int, String> _baseHints = {};
  final Set<int> _loadingBasePrice = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _bind(TintDetail d) {
    for (final p in d.products) {
      final ctrl = _priceCtrls.putIfAbsent(p.itemId, () => TextEditingController());
      ctrl.text = p.tintPrice != null && p.tintPrice! > 0 ? p.tintPrice!.round().toString() : '';
      final allowed = d.tintProducts.any((e) => e.key == p.catalogTintProductId);
      _tintProduct[p.itemId] = allowed ? p.catalogTintProductId : null;
    }
    _detail = d;
  }

  Future<void> _load() async {
    setState(() { _error = null; _busy = true; });
    try {
      final d = await _service.detail(widget.tintId);
      setState(() => _bind(d));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _priceFromBase(TintDetailProduct p) async {
    setState(() => _loadingBasePrice.add(p.itemId));
    try {
      final r = await _service.priceFromBase(widget.tintId, p.itemId);
      setState(() {
        _priceCtrls[p.itemId]!.text = r.price.round().toString();
        _baseHints[p.itemId] = r.targetBase.isNotEmpty
            ? 'Цена найдена, может быть некорректной. Нужная база для оттенка: ${r.targetBase} — проверьте базу товара.'
            : 'Цена найдена, может быть некорректной — проверьте.';
      });
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _loadingBasePrice.remove(p.itemId));
    }
  }

  Future<void> _applyPrices() async {
    final d = _detail;
    if (d == null) return;
    final prices = <int, double>{};
    final products = <int, int>{};
    for (final p in d.products.where((p) => p.active)) {
      final price = double.tryParse(_priceCtrls[p.itemId]!.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
      final tp = _tintProduct[p.itemId];
      if (price <= 0) return _snack('Укажите цену колеровки для всех позиций');
      if (tp == null) return _snack('Выберите товар колеровки для всех позиций');
      prices[p.itemId] = price;
      products[p.itemId] = tp;
    }
    await _run(() async => _bind(await _service.setPrices(d.id, prices, products)), 'Цены проставлены');
  }

  Future<void> _change() async {
    final d = _detail;
    if (d == null) return;
    await _run(() async => _bind(await _service.change(d.id)), null);
  }

  Future<void> _cancel() async {
    final d = _detail;
    if (d == null) return;
    final inBasket = d.statusCode == 'added_to_cart';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить колеровку?'),
        content: Text(inBasket
            ? 'Услуга колеровки и цены колеровки будут убраны из корзины. Позиции можно будет отправить на колеровку заново.'
            : 'Заявка будет отменена.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить колеровку'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      _bind(await _service.cancel(d.id));
      _changed = true;
    }, 'Колеровка отменена');
  }

  Future<void> _deactivate(TintDetailProduct p) async {
    final d = _detail;
    if (d == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Исключить из колеровки?'),
        content: Text('«${p.tintName}» не будет колероваться и не войдёт в стоимость колеровки. '
            'Сам товар останется в корзине без цены колеровки.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Исключить')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async => _bind(await _service.deactivate(d.id, p.itemId)), 'Позиция исключена из колеровки');
  }

  Future<void> _addToBasket() async {
    final d = _detail;
    if (d == null) return;
    await _run(() async {
      await _service.apply(d.appBasketId.toString(), d.id);
      _changed = true;
    }, 'Колеровка добавлена в корзину');
    if (_changed && mounted) Navigator.pop(context, true);
  }

  Future<void> _run(Future<void> Function() action, String? done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() {});
      if (done != null) _snack(done);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F2F7),
        appBar: AppBar(
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          title: Text('Колеровка №${widget.tintId}'),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _busy ? null : _load)],
        ),
        body: d == null
            ? Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Повторить')),
                        ]),
                      )
                    : const CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                _Header(detail: d),
                const SizedBox(height: 12),
                ...d.products.map(_productCard),
                const SizedBox(height: 8),
                if (d.canSetPrices || d.canChange)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Колеровка: ${_fmt(_currentTotal(d))} ₸',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                if (d.canSetPrices)
                  _BigButton(label: 'Применить', onTap: _busy ? null : _applyPrices),
                if (d.canChange) ...[
                  if (d.canApply)
                    _BigButton(label: 'Добавить в корзину', color: const Color(0xFFACD1EC), onTap: _busy ? null : _addToBasket)
                  else
                    Text('Заявка создана не из приложения — добавить её можно только в корзину на сайте.',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                  const SizedBox(height: 8),
                  _BigButton(label: 'Изменить', color: const Color(0xFFFFC107), onTap: _busy ? null : _change),
                ],
                if (d.canCancel) ...[
                  const SizedBox(height: 8),
                  _BigButton(label: 'Отменить', color: Colors.red, textColor: Colors.white, onTap: _busy ? null : _cancel),
                ],
                if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
              ]),
      ),
    );
  }

  double _currentTotal(TintDetail d) {
    var sum = 0.0;
    for (final p in d.products.where((p) => p.active)) {
      final v = double.tryParse(_priceCtrls[p.itemId]?.text.replaceAll(',', '.') ?? '') ?? 0;
      sum += v * p.quantity;
    }
    return sum;
  }

  Widget _productCard(TintDetailProduct p) {
    final d = _detail!;
    final editable = d.canSetPrices && p.active;
    return Opacity(
      opacity: p.active ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: p.picture.isEmpty
                  ? Container(width: 64, height: 64, color: Colors.grey.shade200)
                  : CachedNetworkImage(imageUrl: p.picture, width: 64, height: 64, fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Кол-во: ${_qty(p.quantity)} · ${p.brand} · база ${p.base} · ${p.volume}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                if (!p.active)
                  const Text('Исключено из колеровки', style: TextStyle(fontSize: 12, color: Colors.red)),
                if (p.active && d.canDeactivate && d.products.where((x) => x.active).length > 1)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.red, padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: _busy ? null : () => _deactivate(p),
                    child: const Text('Исключить из колеровки'),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: _hex(p.tintRgb), borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${p.tintName}\n${p.tintCollection}', style: const TextStyle(fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 10),
          if (editable) ...[
            DropdownButtonFormField<int>(
              initialValue: _tintProduct[p.itemId],
              isExpanded: true,
              decoration: _dec('Товар колеровки'),
              items: d.tintProducts
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _tintProduct[p.itemId] = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrls[p.itemId],
              keyboardType: TextInputType.number,
              decoration: _dec('Цена колеровки, ₸ за 1 шт'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _loadingBasePrice.contains(p.itemId) || _busy ? null : () => _priceFromBase(p),
                child: _loadingBasePrice.contains(p.itemId)
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Проставить цену из базы'),
              ),
            ),
            if (_baseHints[p.itemId] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_baseHints[p.itemId]!, style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
              ),
          ] else if (p.tintPrice != null && p.tintPrice! > 0) ...[
            Text('Товар колеровки: ${d.tintProducts.firstWhere((e) => e.key == p.catalogTintProductId, orElse: () => const MapEntry(0, '—')).value}',
                style: const TextStyle(fontSize: 13)),
            Text('Цена колеровки: ${_fmt(p.tintPrice!)} ₸ за 1 шт',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});
  final TintDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 14, height: 28,
              decoration: BoxDecoration(color: tintStatusColor(detail.statusCode), borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 8),
          Text(detail.statusName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Text(detail.date, style: TextStyle(color: Colors.grey.shade700)),
        if (detail.client.isNotEmpty) Text('Клиент: ${detail.client}'),
        if (detail.priceSetter.isNotEmpty) Text('Цены проставил: ${detail.priceSetter}'),
      ]),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.onTap, this.color, this.textColor});
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(backgroundColor: color ?? const Color(0xFF4CAF50), foregroundColor: textColor ?? (color == null ? Colors.white : Colors.black87), shape: shape),
              child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF3F2F7),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

Color _hex(String hex) {
  final h = hex.replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? Colors.grey.shade300 : Color(v);
}

String _qty(double q) => q % 1 == 0 ? q.toInt().toString() : q.toString();

String _fmt(double v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}
