import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:centrkrasok/cart/cart_api_service.dart';
import 'package:centrkrasok/cart/cart_local_store.dart';
import 'package:centrkrasok/cart/models/cart_model.dart';
import 'package:centrkrasok/customer/customer_storage.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';
import 'package:centrkrasok/cart/models/room_options.dart';

const _green = Color(0xFF4CAF50);

/// Показывает шторку "Добавить в корзину" (количество + Помещение +
/// Площадь) и добавляет товар в ТЕКУЩУЮ корзину менеджера (см.
/// CartLocalStore.loadCurrent() — локальный указатель "какая корзина сейчас
/// открыта", сервер этого не хранит). Если текущей корзины нет (клиент ещё
/// не выбран), сразу показывает подсказку вместо шторки — товар класть
/// некуда.
Future<void> showAddToCartSheet(BuildContext context, Product product) async {
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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AddToCartSheet(product: product, cart: current),
  );

  if (added == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Товар добавлен в корзину')),
    );
  }
}

class _AddToCartSheet extends StatefulWidget {
  const _AddToCartSheet({required this.product, required this.cart});
  final Product product;
  final Cart cart;

  @override
  State<_AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends State<_AddToCartSheet> {
  final _cartApiService = CartApiService(dio: Dio());
  final _squareCtrl = TextEditingController();
  String? _selectedRoom;

  int _quantity = 1;
  bool _saving = false;
  String? _error;

  // Та же логика выбора цены, что в ProductTile/ProductItemScreen —
  // группа 30 ("Розничная ИСПОЛЬЗОВАТЬ"), если она есть у товара.
  double get _price {
    final prices = widget.product.prices;
    if (prices.isEmpty) return 0;
    final retail = prices.where((p) => p.typeId == '30').toList();
    final source = retail.isNotEmpty ? retail : prices;
    return source.map((p) => p.price).reduce((a, b) => a < b ? a : b);
  }

  @override
  void dispose() {
    _squareCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final managerId = await CustomerStorage.currentManagerId();
    if (managerId == null) {
      setState(() => _error = 'Не удалось определить менеджера');
      return;
    }

    setState(() { _saving = true; _error = null; });

    final productId = int.tryParse(widget.product.id) ?? 0;
    final items = List<CartItem>.from(widget.cart.items);
    final index = items.indexWhere((i) => i.productId == productId);

    final props = <String, String>{
      if (_selectedRoom != null && _selectedRoom!.isNotEmpty) 'SELECT_ROOM': _selectedRoom!,
      if (_squareCtrl.text.trim().isNotEmpty) 'ROOM_SQUARE': _squareCtrl.text.trim(),
      if (widget.product.brend != null && widget.product.brend!.isNotEmpty) 'BREND': widget.product.brend!,
    };

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
      // Тот же товар уже есть в корзине — прибавляем количество, а
      // свойства (Помещение/Площадь) обновляем на введённые сейчас, если
      // хоть одно из полей заполнено (иначе оставляем прежние).
      items[index] = items[index].copyWith(
        quantity: items[index].quantity + _quantity,
        props: props.isNotEmpty ? props : items[index].props,
      );
    }

    try {
      await _cartApiService.updateCartItems(
        basketId: widget.cart.id,
        managerId: managerId,
        items: items,
      );
      await CartLocalStore.updateItems(widget.cart.id, items);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _error = 'Не удалось добавить товар'; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Добавить в корзину', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(widget.product.name,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 16),

        Text('Количество', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            IconButton(
              onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text('$_quantity', textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              onPressed: () => setState(() => _quantity++),
              icon: const Icon(Icons.add),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        Text('Помещение', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: _selectedRoom,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          hint: const Text('Выберите помещение'),
          items: roomOptions
              .map((room) => DropdownMenuItem(value: room, child: Text(room)))
              .toList(),
          onChanged: (value) => setState(() => _selectedRoom = value),
        ),
        const SizedBox(height: 12),

        Text('Площадь, м2', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        TextField(
          controller: _squareCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('В корзину', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ]),
          ),
        ),
      ]),
    );
  }
}
