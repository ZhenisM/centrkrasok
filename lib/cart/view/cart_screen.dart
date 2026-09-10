import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:centrkrasok/bitrix/bitrix_service.dart' show NoInternetException;
import 'package:centrkrasok/cart/cart_api_service.dart';
import 'package:centrkrasok/cart/cart_local_store.dart';
import 'package:centrkrasok/cart/models/cart_model.dart';
import 'package:centrkrasok/cart/models/coupon_catalog.dart';
import 'package:centrkrasok/cart/models/room_options.dart';
import 'package:centrkrasok/customer/customer_storage.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:centrkrasok/repositories/products/local_db.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';
import 'package:centrkrasok/repositories/products/products.dart';
import 'package:centrkrasok/common/animated_search_bar.dart';
import 'package:centrkrasok/common/menu/menu_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

const _green = Color(0xFF4CAF50);

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cartApiService = CartApiService(dio: Dio());

  int? _managerId;
  List<Cart>? _carts;
  Cart? _current;
  bool _loading = true;
  String? _error;
  bool _mutating = false; // блокирует повторные тапы во время запроса к серверу
  Map<String, Product> _productsById = {}; // для картинки/имени — из локального каталога, по PRODUCT_ID
  List<Section>? _sections; // для кнопки меню в шапке — как в каталоге
  final _productsRepository = ProductsRepository(dio: Dio());

  @override
  void initState() {
    super.initState();
    _loadCarts();
    _loadSections();
  }

  Future<void> _loadSections() async {
    try {
      final sections = await _productsRepository.getSections();
      if (mounted) setState(() => _sections = sections);
    } catch (e) {
      // Меню без разделов просто не откроется по кнопке — не критично для
      // самого экрана корзины, поэтому без отдельного _error-состояния.
      debugPrint('CartScreen: не удалось загрузить разделы для меню: $e');
    }
  }

  void _menuOpen() {
    if (_sections == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(sections: _sections!, products: const []),
      ),
    );
  }

  Future<void> _loadCarts() async {
    setState(() { _loading = true; _error = null; });

    final managerId = await CustomerStorage.currentManagerId();
    _managerId = managerId;
    if (managerId == null) {
      setState(() { _loading = false; _error = 'Не удалось определить менеджера'; });
      return;
    }

    List<Cart> carts;
    try {
      carts = await _cartApiService.loadCarts(managerId: managerId);
      await CartLocalStore.saveAll(carts);
    } on NoInternetException {
      carts = await CartLocalStore.loadAll();
    } catch (e) {
      // Раньше здесь ошибка нигде не печаталась — если loadCarts() падает
      // не из-за сети (например, Cart.fromJson() споткнулся на каком-то
      // заказе), это тихо приводило к фолбэку на устаревший локальный
      // кэш НАВСЕГДА (каждая следующая попытка синхронизации падала бы
      // так же и снова откатывалась к тому же кэшу) — в частности это
      // объясняло бы "призрачные" корзины, удалённые на сайте, но всё
      // ещё видимые в приложении.
      debugPrint('loadCarts: не удалось обновить с сервера, использую локальный кэш: $e');
      carts = await CartLocalStore.loadAll();
      if (carts.isEmpty) {
        setState(() { _loading = false; _error = 'Не удалось загрузить корзины'; });
        return;
      }
    }

    final current = await CartLocalStore.loadCurrent()
        ?? (carts.isNotEmpty ? carts.first : null);

    // Картинка/актуальное имя товара — только из локального каталога
    // (полностью офлайн, уже синхронизирован); сервер их не отдаёт и не
    // должен — это не его забота.
    final productIds = <String>{
      for (final cart in carts)
        for (final item in cart.items) item.productId.toString(),
    }.toList();
    final products = productIds.isEmpty
        ? <Product>[]
        : await LocalDb.loadProductsByIds(productIds);
    final productsById = {for (final p in products) p.id: p};

    setState(() {
      _carts = carts;
      _current = current;
      _productsById = productsById;
      _loading = false;
    });
  }

  double _totalPrice(Cart cart) => cart.totalPrice;

  /// Обновляет состав текущей корзины и на сервере, и локально (оптимистично
  /// на UI сразу, откат при ошибке).
  Future<void> _syncItems(List<CartItem> newItems) async {
    final current = _current;
    final managerId = _managerId;
    if (current == null || managerId == null || _mutating) return;

    final previous = current.items;
    setState(() {
      _mutating = true;
      _current = current.copyWith(items: newItems);
      _carts = _carts?.map((c) => c.id == current.id ? _current! : c).toList();
    });

    try {
      await _cartApiService.updateCartItems(
        basketId: current.id,
        managerId: managerId,
        items: newItems,
      );
      await CartLocalStore.updateItems(current.id, newItems);
    } catch (e) {
      // откат
      setState(() {
        _current = current.copyWith(items: previous);
        _carts = _carts?.map((c) => c.id == current.id ? _current! : c).toList();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить изменения корзины')),
        );
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _changeQuantity(CartItem item, double newQuantity) {
    final current = _current;
    if (current == null) return;

    final items = List<CartItem>.from(current.items);
    final index = items.indexWhere((i) => i.productId == item.productId);
    if (index == -1) return;

    if (newQuantity <= 0) {
      items.removeAt(index);
    } else {
      items[index] = items[index].copyWith(quantity: newQuantity);
    }
    _syncItems(items);
  }

  void _deleteItem(CartItem item) => _changeQuantity(item, 0);

  /// Применяет/снимает купоны. В отличие от _syncItems (товары), каждый
  /// купон проверяется на сервере через настоящий Bitrix
  /// DiscountCouponsManager — если код не существует/неактивен, сервер
  /// вернёт ошибку и купоны локально не поменяются. Можно выбрать
  /// несколько сразу — общая скидка и купон на конкретный товар не
  /// исключают друг друга.
  Future<void> _applyCoupons(List<String> coupons) async {
    final current = _current;
    final managerId = _managerId;
    if (current == null || managerId == null) return;

    setState(() => _mutating = true);
    try {
      await _cartApiService.updateCartItems(
        basketId: current.id,
        managerId: managerId,
        items: current.items,
        coupons: coupons,
      );
      await CartLocalStore.updateCoupons(current.id, coupons);
      final updated = current.copyWith(coupons: coupons);
      setState(() {
        _current = updated;
        _carts = _carts?.map((c) => c.id == current.id ? updated : c).toList();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(coupons.isNotEmpty
              ? 'Купоны применены: ${coupons.join(', ')}'
              : 'Купоны сняты')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is CartApiException ? e.message : 'Не удалось применить купоны')),
        );
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить всё?'),
        content: const Text('Все товары в текущей корзине будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true) {
      await _syncItems([]);
    }
  }

  Future<void> _editProps(CartItem item) async {
    final squareCtrl = TextEditingController(text: item.props['ROOM_SQUARE'] ?? '');
    final existingRoom = item.props['SELECT_ROOM'];
    String? selectedRoom = (existingRoom != null && existingRoom.isNotEmpty) ? existingRoom : null;
    // Если в позиции уже стоит значение, которого нет в справочнике
    // (например, осталось от повтора старого заказа) — добавляем его
    // отдельным пунктом сверху, чтобы не потерять при сохранении.
    final options = [
      if (selectedRoom != null && !roomOptions.contains(selectedRoom)) selectedRoom,
      ...roomOptions,
    ];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const _SheetHandle(),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Свойства товара', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Помещение', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: selectedRoom,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              hint: const Text('Выберите помещение'),
              items: options.map((room) => DropdownMenuItem(value: room, child: Text(room))).toList(),
              onChanged: (value) => setSheetState(() => selectedRoom = value),
            ),
            const SizedBox(height: 12),
            _PropsField(label: 'Площадь, м2', controller: squareCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            _GreenButton(label: 'Сохранить', onTap: () => Navigator.pop(ctx, true)),
          ]),
        );
      }),
    );

    if (saved == true) {
      final items = List<CartItem>.from(_current?.items ?? []);
      final index = items.indexWhere((i) => i.productId == item.productId);
      if (index == -1) return;
      final newProps = Map<String, String>.from(items[index].props);
      newProps['SELECT_ROOM'] = selectedRoom ?? '';
      newProps['ROOM_SQUARE'] = squareCtrl.text.trim();
      items[index] = items[index].copyWith(props: newProps);
      _syncItems(items);
    }
  }

  void _openCartsSheet() {
    final carts = _carts;
    if (carts == null || carts.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const _SheetHandle(),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Лиды', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                Text('${carts.length} лидов', style: TextStyle(color: Colors.grey.shade500)),
              ]),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: carts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('Нет активных корзин', style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: carts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final cart = carts[i];
                          final isSelected = cart.id == _current?.id;
                          return _CartSelectorTile(
                            cart: cart,
                            selected: isSelected,
                            onTap: () async {
                              await CartLocalStore.setCurrent(cart.id);
                              setState(() => _current = cart);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            onDelete: () async {
                              final removed = await _deleteCart(cart);
                              if (removed) {
                                carts.removeAt(i);
                                setSheetState(() {});
                                if (carts.isEmpty && ctx.mounted) Navigator.pop(ctx);
                              }
                            },
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  /// Удаляет корзину (статус -> "удалена") и на сервере, и локально.
  /// Возвращает true, если удаление прошло успешно. Если удаляли текущую
  /// корзину — переключает текущую на следующую из оставшихся (или на
  /// null, если корзин больше не осталось).
  Future<bool> _deleteCart(Cart cart) async {
    final managerId = _managerId;
    if (managerId == null) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Удалить корзину?'),
        content: Text('Корзина «${cart.title}» будет удалена.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await _cartApiService.setCartStatus(
        basketId: cart.id,
        managerId: managerId,
        status: CartStatus.deleted,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось удалить корзину')),
        );
      }
      return false;
    }

    await CartLocalStore.removeCart(cart.id);

    final remaining = (_carts ?? []).where((c) => c.id != cart.id).toList();
    Cart? newCurrent = _current;
    if (_current?.id == cart.id) {
      newCurrent = remaining.isNotEmpty ? remaining.first : null;
      if (newCurrent != null) {
        await CartLocalStore.setCurrent(newCurrent.id);
      }
    }

    if (mounted) {
      setState(() {
        _carts = remaining;
        _current = newCurrent;
      });
    }
    return true;
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — скоро будет доступно')),
    );
  }

  void _showPrintSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var city = 'Алматы';
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const _SheetHandle(),
                const SizedBox(height: 12),
                const Align(alignment: Alignment.centerLeft,
                  child: Text('Распечатать', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _CityToggle(
                    label: 'Алматы', selected: city == 'Алматы',
                    onTap: () => setSheetState(() => city = 'Алматы'))),
                  const SizedBox(width: 8),
                  Expanded(child: _CityToggle(
                    label: 'Астана', selected: city == 'Астана',
                    onTap: () => setSheetState(() => city = 'Астана'))),
                ]),
                const SizedBox(height: 16),
                ...['Договор купли-продажи', 'Приложение к договору',
                    'Согласие на колеровку (каз)', 'Согласие на колеровку (рус)']
                    .map((label) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _OutlinedRowButton(
                            label: label,
                            onTap: () { Navigator.pop(ctx); _showComingSoon('Печать документов'); },
                          ),
                        )),
              ]),
            ),
          );
        });
      },
    );
  }

  void _showDiscountSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String? selected;
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const _SheetHandle(),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Скидки на колеровку', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  TextButton(onPressed: () => setSheetState(() => selected = null), child: const Text('Сбросить')),
                ]),
                const SizedBox(height: 8),
                ...['10%', '20%'].map((v) => _SelectableRow(
                      label: v,
                      selected: selected == v,
                      onTap: () => setSheetState(() => selected = v),
                    )),
                const SizedBox(height: 12),
                _GreenButton(label: 'Применить', onTap: () { Navigator.pop(ctx); _showComingSoon('Скидки на колеровку'); }),
              ]),
            ),
          );
        });
      },
    );
  }

  void _showCouponsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String? selected = _current?.coupons.isNotEmpty == true ? _current!.coupons.first : null;
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20, right: 20, top: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                ),
                child: Column(children: [
                  const _SheetHandle(),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Купоны', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    TextButton(
                      onPressed: () => setSheetState(() => selected = null),
                      child: const Text('Сбросить'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(children: [
                        for (final entry in couponCatalog)
                          if (entry is CouponSectionHeader)
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(entry.title,
                                    style: const TextStyle(
                                        fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87)),
                              ),
                            )
                          else if (entry is CouponGroup) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(entry.name,
                                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            for (final code in entry.codes)
                              _SelectableRow(
                                label: code,
                                selected: selected == code,
                                onTap: () => setSheetState(
                                    () => selected = (selected == code) ? null : code),
                              ),
                          ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _GreenButton(
                    label: 'Применить',
                    onTap: () {
                      Navigator.pop(ctx);
                      _applyCoupons(selected == null ? [] : [selected!]);
                    },
                  ),
                ]),
              ),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final itemsCount = current?.itemsCount ?? 0;
    final hasItems = itemsCount > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Мультикорзина'),
        centerTitle: true,
        actions: [
          const CatalogSearchBar(),
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/menu.svg',
              width: 22, height: 22,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            onPressed: _menuOpen,
          ),
        ],
      ),
      body: Column(children: [
        _ClientSelector(current: current, onTap: _openCartsSheet),
        Expanded(child: _buildBody(current, itemsCount)),
      ]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasItems)
            _ContinueBar(
              itemsCount: itemsCount,
              totalPrice: _formatPrice(_totalPrice(current!)),
              onContinue: () => _showComingSoon('Оформление заказа'),
            ),
          const AppBottomNavBar(currentTab: AppBottomTab.cart),
        ],
      ),
    );
  }

  Widget _buildBody(Cart? current, double itemsCount) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 40),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadCarts, child: const Text('Повторить')),
        ]),
      );
    }
    if (current == null) {
      return const Center(child: Text('Нет активных корзин', style: TextStyle(color: Colors.grey)));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${itemsCount.toInt()} товаров', style: const TextStyle(fontWeight: FontWeight.w500)),
          GestureDetector(
            onTap: current.items.isEmpty ? null : _deleteAll,
            child: Text('Удалить всё',
                style: TextStyle(color: current.items.isEmpty ? Colors.grey.shade400 : Colors.grey.shade600)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: _ActionButton(label: 'Распечатать', onTap: _showPrintSheet)),
          const SizedBox(width: 8),
          Expanded(child: _ActionButton(label: 'На колеровку', onTap: () => _showComingSoon('Колеровка'))),
        ]),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: _ActionButton(label: 'Скидки на колер...', onTap: _showDiscountSheet)),
          const SizedBox(width: 8),
          Expanded(child: _ActionButton(label: 'Купоны', onTap: _showCouponsSheet)),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: current.items.isEmpty
            ? const Center(child: Text('Корзина пуста', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: current.items.length,
                itemBuilder: (_, i) {
                  final item = current.items[i];
                  return _CartItemTile(
                    item: item,
                    product: _productsById[item.productId.toString()],
                    enabled: !_mutating,
                    onIncrement: () => _changeQuantity(item, item.quantity + 1),
                    onDecrement: () => _changeQuantity(item, item.quantity - 1),
                    onDelete: () => _deleteItem(item),
                    onEditProps: () => _editProps(item),
                    onTint: () => _showComingSoon('Колеровка'),
                  );
                },
              ),
      ),
    ]);
  }
}

String _formatPrice(double price) {
  final rounded = price.round();
  final str = rounded.toString();
  final buf = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buf.write(' ');
    buf.write(str[i]);
  }
  return '$buf ₸';
}

// =========================================================
// Виджеты
// =========================================================

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Container(
        width: 40, height: 4,
        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
      );
}

/// Селектор текущего клиента/корзины под шапкой — показывает имя текущей
/// корзины (см. Cart.title), тап открывает шторку "Лиды" со списком всех
/// активных корзин менеджера.
class _ClientSelector extends StatelessWidget {
  const _ClientSelector({required this.current, required this.onTap});
  final Cart? current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Text(
                current?.title ?? 'Клиент не выбран',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down),
          ]),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.product,
    required this.enabled,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.onEditProps,
    required this.onTint,
  });

  final CartItem item;
  final Product? product; // из локального каталога по PRODUCT_ID — для картинки и актуального имени
  final bool enabled;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;
  final VoidCallback onEditProps;
  final VoidCallback onTint;

  @override
  Widget build(BuildContext context) {
    final tintColor = item.props['TINT_COLOR']; // пока нигде не пишется — колеровка отложена
    final displayName = (product?.name.isNotEmpty ?? false) ? product!.name : item.name;
    final image = product?.image;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56, height: 56,
              child: (image != null && image.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey.shade100),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey.shade100,
                        child: Icon(Icons.format_paint_outlined, color: Colors.grey.shade400),
                      ),
                    )
                  : Container(
                      color: Colors.grey.shade100,
                      child: Icon(Icons.format_paint_outlined, color: Colors.grey.shade400),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(_formatPrice(item.price), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (item.hasDiscount) ...[
                  const SizedBox(width: 6),
                  Text(_formatPrice(item.basePrice),
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade400,
                          decoration: TextDecoration.lineThrough)),
                ],
              ]),
              Row(children: [
                Text('${_formatPrice(item.price)}/шт', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                if (item.hasDiscount) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(4)),
                    child: Text('-${item.discountPercent.round()}%',
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
              const SizedBox(height: 4),
              Text(displayName, style: const TextStyle(fontSize: 13)),
              if (tintColor != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Text('Цвет колеровки  ', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  Container(width: 14, height: 14,
                      decoration: BoxDecoration(color: _parseHexColor(tintColor), shape: BoxShape.circle)),
                ]),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          IconButton(
            onPressed: enabled ? onDelete : null,
            icon: SvgPicture.asset('assets/icons/trash.svg', width: 26, height: 26,
                colorFilter: ColorFilter.mode(Colors.grey.shade500, BlendMode.srcIn)),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: enabled ? onEditProps : null,
            icon: SvgPicture.asset('assets/icons/list.svg', width: 18, height: 18,
                colorFilter: ColorFilter.mode(Colors.grey.shade500, BlendMode.srcIn)),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onTint, // колеровка отложена — просто "скоро"
            icon: SvgPicture.asset('assets/icons/color.svg', width: 24, height: 24,
                colorFilter: ColorFilter.mode(Colors.grey.shade400, BlendMode.srcIn)),
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
          _QtyStepper(
            quantity: item.quantity,
            enabled: enabled,
            onIncrement: onIncrement,
            onDecrement: onDecrement,
          ),
        ]),
      ]),
    );
  }
}

Color _parseHexColor(String hex) {
  final cleaned = hex.replaceAll('#', '');
  try {
    return Color(int.parse('FF$cleaned', radix: 16));
  } catch (_) {
    return Colors.grey;
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.quantity,
    required this.enabled,
    required this.onIncrement,
    required this.onDecrement,
  });
  final double quantity;
  final bool enabled;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          onPressed: enabled ? onDecrement : null,
          icon: const Icon(Icons.remove, size: 18),
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 28,
          child: Text(
            quantity == quantity.roundToDouble() ? quantity.toInt().toString() : quantity.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          onPressed: enabled ? onIncrement : null,
          icon: const Icon(Icons.add, size: 18),
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }
}

class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.itemsCount, required this.totalPrice, required this.onContinue});
  final double itemsCount;
  final String totalPrice;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _green,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: GestureDetector(
        onTap: onContinue,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${itemsCount.toInt()} товар', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(totalPrice, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const Row(children: [
            Text('Продолжить', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward, color: Colors.white, size: 18),
          ]),
        ]),
      ),
    );
  }
}

class _CartSelectorTile extends StatelessWidget {
  const _CartSelectorTile({required this.cart, required this.selected, required this.onTap, required this.onDelete});
  final Cart cart;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? _green : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cart.title,
                  style: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                cart.items.isEmpty ? '0' : _formatPrice(cart.totalPrice),
                style: TextStyle(
                  color: selected ? Colors.white : (cart.items.isEmpty ? Colors.grey.shade400 : Colors.black87),
                  fontSize: 20, fontWeight: FontWeight.w700,
                ),
              ),
              Text('Позиций ${cart.items.length}',
                  style: TextStyle(color: selected ? Colors.white70 : Colors.grey.shade500, fontSize: 12)),
            ]),
          ),
        ),
        IconButton(
          onPressed: onDelete,
          icon: SvgPicture.asset('assets/icons/trash.svg', width: 20, height: 20,
              colorFilter: ColorFilter.mode(selected ? Colors.white : Colors.grey.shade500, BlendMode.srcIn)),
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }
}

class _PropsField extends StatelessWidget {
  const _PropsField({required this.label, required this.controller, this.keyboardType = TextInputType.text});
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ]);
  }
}

class _GreenButton extends StatelessWidget {
  const _GreenButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _CityToggle extends StatelessWidget {
  const _CityToggle({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _green : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _OutlinedRowButton extends StatelessWidget {
  const _OutlinedRowButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

class _SelectableRow extends StatelessWidget {
  const _SelectableRow({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? _green : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
