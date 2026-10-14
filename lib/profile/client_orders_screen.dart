import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:centrkrasok/cart/cart_api_service.dart';
import 'package:centrkrasok/cart/cart_local_store.dart';
import 'package:centrkrasok/cart/models/cart_model.dart';
import 'package:centrkrasok/customer/customer_storage.dart';
import 'package:centrkrasok/profile/order_edit_screen.dart';
import 'package:centrkrasok/profile/profile_api.dart';
import 'package:centrkrasok/repositories/products/products.dart';

const _green = Color(0xFF4CAF50);
const _bg = Color(0xFFF3F2F7);

/// Услуги «Малярные работы для колеровки» — при «Повторить» не переносим:
/// колеровку нужно рассчитать заново (у неё цена из заявки колеровщика).
const _tintServiceIds = {1450830, 1450831, 1450832, 1450833, 1450834, 1450835, 1450836, 1452015, 1497119, 1497120, 1497121, 1497122};

/// «Заказы клиента» — как /client/orders/ сайта: карточки заказов,
/// «Состав», «Скачать» (КП, КП новое, счёт) и «Действия» (повторить,
/// изменить) — всё через шторку снизу.
class ClientOrdersScreen extends StatefulWidget {
  const ClientOrdersScreen({super.key, required this.basketId, required this.title});
  final String basketId;
  final String title;
  @override
  State<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends State<ClientOrdersScreen> {
  final _api = ProfileApi();
  final List<Map<String, dynamic>> _orders = [];
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) { _orders.clear(); _page = 0; _hasMore = true; }
    if (!_hasMore) return;
    setState(() { _loading = true; _error = null; });
    try {
      final r = await _api.call('orders', {'basket_id': widget.basketId, 'page': '${_page + 1}'});
      final items = ((r['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _page = (r['page'] as num).toInt();
        _total = (r['total'] as num).toInt();
        _orders.addAll(items);
        _hasMore = items.length >= 50 && _orders.length < _total;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _hex(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? Colors.grey : Color(v);
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  // ---------- Состав ----------
  Future<void> _showItems(Map<String, dynamic> o) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _OrderItemsSheet(api: _api, order: o),
    );
  }

  // ---------- Скачать ----------
  Future<void> _showDownloads(Map<String, dynamic> o) async {
    final isCompany = o['person_type_id'] == 7;
    final groups = <String, List<MapEntry<String, String>>>{
      'КП': const [
        MapEntry('kp1_print', 'Распечатать'),
        MapEntry('kp1_ru', 'Для клиента'),
        MapEntry('kp1_kz', 'Для клиента (каз)'),
        MapEntry('kp1_ru_notint', 'Для клиента без колеровки'),
        MapEntry('kp1_kz_notint', 'Для клиента без колеровки (каз)'),
        MapEntry('tint_items_ru', 'Колеровка по товарам'),
        MapEntry('tint_items_kz', 'Колеровка по товарам (каз)'),
      ],
      'КП новое': const [
        MapEntry('kp2_ru', 'Для клиента'),
        MapEntry('kp2_kz', 'Для клиента (каз)'),
        MapEntry('kp2_ru_notint', 'Для клиента без колеровки'),
        MapEntry('kp2_kz_notint', 'Для клиента без колеровки (каз)'),
      ],
      if (isCompany) 'Счёт': const [MapEntry('invoice', 'Счёт на оплату')],
    };
    final doc = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _Sheet(
        title: 'Скачать · заказ №${o['number']}',
        children: [
          for (final g in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(g.key, style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
            ),
            ...g.value.map((d) => _SheetButton(
                  label: d.value,
                  icon: d.key == 'kp1_print' ? Icons.print_outlined : Icons.picture_as_pdf_outlined,
                  onTap: () => Navigator.pop(ctx, d.key),
                )),
          ],
        ],
      ),
    );
    if (doc == null) return;
    try {
      final r = await _api.call('order_doc', {'order_id': '${o['id']}', 'doc': doc});
      await launchUrl(Uri.parse(r['url'].toString()), mode: LaunchMode.externalApplication);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ---------- Действия ----------
  Future<void> _showActions(Map<String, dynamic> o) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _Sheet(
        title: 'Заказ №${o['number']}',
        children: [
          _SheetButton(label: 'Повторить', icon: Icons.refresh, onTap: () => Navigator.pop(ctx, 'repeat')),
          // «Изменить» — как на сайте: у всех заказов, кроме «Выполнен» (F).
          if ('${o['status_id']}' != 'F')
            _SheetButton(label: 'Изменить', icon: Icons.edit_outlined, onTap: () => Navigator.pop(ctx, 'edit')),
        ],
      ),
    );
    if (action == 'repeat') await _repeat(o);
    if (action == 'edit' && mounted) {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => OrderEditScreen(orderId: o['id'] as int, orderNumber: '${o['number']}')));
      if (saved == true) _load(reset: true);
    }
  }

  /// «Повторить» — позиции заказа ДОБАВЛЯЮТСЯ в текущую корзину (с
  /// текущими ценами каталога); тот же товар с теми же свойствами —
  /// прибавляется к количеству.
  Future<void> _repeat(Map<String, dynamic> o) async {
    final cart = await CartLocalStore.loadCurrent();
    if (!mounted) return;
    if (cart == null) return _snack('Нет текущей корзины — выберите клиента');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Повторить заказ №${o['number']}?'),
        content: const Text('Товары заказа будут добавлены в текущую корзину. '
            'Колеровку для них нужно будет рассчитать заново.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: _green),
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Повторить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _api.call('repeat', {'order_id': '${o['id']}'});
      final src = ((r['items'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((i) => !_tintServiceIds.contains(i['product_id']))
          .toList();
      if (src.isEmpty) return _snack('В заказе нет товаров для повтора');
      final products = await ProductsRepository(dio: Dio())
          .getProductsByIds(src.map((i) => '${i['product_id']}').toList());
      final byId = {for (final p in products) p.id: p};
      final items = List<CartItem>.from(cart.items);
      for (final i in src) {
        final p = byId['${i['product_id']}'];
        final props = <String, String>{
          for (final pr in (i['props'] as List))
            if (!['TINT_PRICE', 'TINT_DISCOUNT', 'PRODUCT.XML_ID', 'CATALOG.XML_ID'].contains(pr['code']))
              '${pr['code']}': '${pr['value']}',
        };
        double price = (i['price'] as num).toDouble();
        if (p != null && p.prices.isNotEmpty) {
          final retail = p.prices.where((x) => x.typeId == '30').toList();
          price = (retail.isNotEmpty ? retail : p.prices).map((x) => x.price).reduce((a, b) => a < b ? a : b);
        }
        final productId = i['product_id'] as int;
        final qty = (i['quantity'] as num).toDouble();
        bool sameProps(Map<String, String> a) =>
            a.length == props.length && props.entries.every((e) => a[e.key] == e.value);
        final idx = items.indexWhere((x) =>
            x.productId == productId && (x.props['TINT_PRICE'] ?? '').isEmpty && sameProps(
                Map.fromEntries(x.props.entries.where((e) => !['TINT_PRICE', 'TINT_DISCOUNT'].contains(e.key)))));
        if (idx >= 0) {
          items[idx] = items[idx].copyWith(quantity: items[idx].quantity + qty);
        } else {
          items.add(CartItem(
            productId: productId,
            name: p?.name ?? '${i['name']}',
            quantity: qty,
            price: price,
            customPrice: true,
            props: props,
          ));
        }
      }
      final managerId = await CustomerStorage.currentManagerId();
      if (managerId == null) return _snack('Не удалось определить менеджера');
      await CartApiService(dio: Dio()).updateCartItems(basketId: cart.id, managerId: managerId, items: items);
      await CartLocalStore.updateItems(cart.id, items);
      if (!mounted) return;
      _snack('Товары заказа добавлены в корзину');
      Navigator.of(context).pushNamed('/cart');
    } catch (e) {
      _snack('Не удалось повторить заказ: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _green, foregroundColor: Colors.white,
        title: const Text('Заказы клиента', style: TextStyle(fontWeight: FontWeight.w600)), centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _orders.isEmpty
            ? ListView(children: [
                const SizedBox(height: 120),
                Center(child: _loading
                    ? const CircularProgressIndicator()
                    : Text(_error ?? 'Заказов нет', style: const TextStyle(color: Colors.grey))),
              ])
            : NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _load();
                  return false;
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _orders.length + 2,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                        child: Row(children: [
                          Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text('Всего: $_total', style: TextStyle(color: Colors.grey.shade600)),
                        ]),
                      );
                    }
                    if (i == _orders.length + 1) {
                      return _loading
                          ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                          : const SizedBox(height: 16);
                    }
                    return _orderCard(_orders[i - 1]);
                  },
                ),
              ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    Widget kv(String k, Widget v) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            const SizedBox(height: 1),
            v,
          ]),
        );
    const valueStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${o['number']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            kv('Дата', Text('${o['date']}', style: valueStyle)),
            kv('Сумма', Text('${o['price']} ₸', style: valueStyle.copyWith(fontWeight: FontWeight.w700))),
            kv('Статус', Text('${o['status']}', style: valueStyle.copyWith(color: _hex('${o['status_color']}')))),
          ])),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            kv('Менеджер', Text('${o['manager']}'.isEmpty ? '—' : '${o['manager']}', style: valueStyle)),
            kv('Тип плательщика', Text(o['person_type_id'] == 7 ? 'Юридическое лицо' : 'Физическое лицо', style: valueStyle)),
            if ('${o['shipping_date']}'.isNotEmpty)
              kv('Дата отгрузки', Text('${o['shipping_date']}', style: valueStyle)),
          ])),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _pill('Состав', Icons.list_alt, () => _showItems(o))),
          const SizedBox(width: 8),
          Expanded(child: _pill('Скачать', Icons.download_outlined, () => _showDownloads(o))),
          const SizedBox(width: 8),
          Expanded(child: _pill('Действия', Icons.keyboard_arrow_up, () => _showActions(o))),
        ]),
      ]),
    );
  }

  Widget _pill(String label, IconData icon, VoidCallback onTap) => Material(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: Colors.black54),
              const SizedBox(width: 4),
              Flexible(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              ...children,
            ]),
          ),
        ),
      );
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: _bg,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Icon(icon, size: 20, color: Colors.black54),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
              ]),
            ),
          ),
        ),
      );
}

/// Шторка «Состав заказа» — как модальное окно «Состав» на сайте.
class _OrderItemsSheet extends StatefulWidget {
  const _OrderItemsSheet({required this.api, required this.order});
  final ProfileApi api;
  final Map<String, dynamic> order;
  @override
  State<_OrderItemsSheet> createState() => _OrderItemsSheetState();
}

class _OrderItemsSheetState extends State<_OrderItemsSheet> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.call('order_items', {'order_id': '${widget.order['id']}'}).then((r) {
      if (mounted) {
        setState(() => _items = ((r['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    }).catchError((e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    });
  }

  String _q(num v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text('Состав заказа №${widget.order['number']}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: _items == null
              ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                  itemCount: _items!.length,
                  separatorBuilder: (context, index) => const Divider(height: 20),
                  itemBuilder: (_, i) {
                    final it = _items![i];
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: '${it['picture']}'.isEmpty
                            ? Container(width: 56, height: 56, color: Colors.grey.shade100)
                            : CachedNetworkImage(imageUrl: '${it['picture']}', width: 56, height: 56, fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${it['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ...((it['props'] as List?) ?? []).map((p) => Text('${p['name']}: ${p['value']}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(child: Text('${_q(it['quantity'] as num)} × ${fmtMoney(it['price'] as num)} ₸',
                              style: const TextStyle(fontSize: 13))),
                          Text('${fmtMoney(it['sum'] as num)} ₸', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ])),
                    ]);
                  },
                ),
        ),
      ]),
    );
  }
}
