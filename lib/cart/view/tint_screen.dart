import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:centrkrasok/cart/models/cart_model.dart';
import 'package:centrkrasok/cart/tint_api_service.dart';
import 'package:centrkrasok/customer/customer_storage.dart';

const _green = Color(0xFF4CAF50);
const int _colorCountMax = 10; // как COLOR_COUNT_MAX на сайте

class _TintSlotData {
  TintColor color;
  String customization;
  int quantity;
  _TintSlotData({required this.color, this.customization = '', this.quantity = 1});
}

/// Экран колеровки для одной позиции корзины. Работает точно как на сайте:
/// 1) выбрать количество оттенков, 2) для каждого оттенка — свой цвет (по
/// поиску в базе) и своё количество (независимое от исходного количества
/// позиции и от количеств других оттенков), 3) "Добавить в корзину" —
/// возвращает список новых позиций (по одной на оттенок), которыми
/// исходная позиция будет ПОЛНОСТЬЮ заменена (даже если сумма количеств
/// новых не совпадает с исходным).
class TintScreen extends StatefulWidget {
  const TintScreen({super.key, required this.originalItem, this.displayName, this.imageUrl});
  final CartItem originalItem;
  final String? displayName;
  final String? imageUrl;

  @override
  State<TintScreen> createState() => _TintScreenState();
}

class _TintScreenState extends State<TintScreen> {
  final _tintApi = TintApiService(dio: Dio());

  int? _colorCount;
  List<_TintSlotData?> _slots = [];
  List<TintPalette> _palettes = [];
  bool _palettesLoading = true;
  int? _managerId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final managerId = await CustomerStorage.currentManagerId();
    _managerId = managerId;
    if (managerId == null) {
      if (mounted) setState(() => _palettesLoading = false);
      debugPrint('TintScreen: не удалось определить менеджера (не авторизован)');
      return;
    }
    await _loadPalettes(managerId);
  }

  Future<void> _loadPalettes(int managerId) async {
    try {
      final palettes = await _tintApi.loadPalettes(managerId: managerId);
      debugPrint('TintScreen: загружено палитр: ${palettes.length}');
      if (mounted) setState(() { _palettes = palettes; _palettesLoading = false; });
    } catch (e) {
      debugPrint('TintScreen: не удалось загрузить палитры: $e');
      if (mounted) setState(() => _palettesLoading = false);
    }
  }

  void _chooseColorCount(int count) {
    setState(() {
      _colorCount = count;
      _slots = List<_TintSlotData?>.filled(count, null);
    });
  }

  bool get _allSlotsFilled => _slots.isNotEmpty && _slots.every((s) => s != null);

  Future<void> _openColorPicker(int slotIndex) async {
    final managerId = _managerId;
    if (managerId == null) return;
    final result = await showModalBottomSheet<_TintSlotData>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ColorPickerSheet(
        tintApi: _tintApi,
        managerId: managerId,
        palettes: _palettes,
        initial: _slots[slotIndex],
      ),
    );
    if (result != null) {
      setState(() => _slots[slotIndex] = result);
    }
  }

  void _submit() {
    if (!_allSlotsFilled) return;
    final newItems = _slots.map((slot) {
      final s = slot!;
      final props = Map<String, String>.from(widget.originalItem.props);
      props['TINT_NAME'] = s.color.name;
      props['TINT_COLLECTION'] = s.color.palette;
      props['TINT_RGB'] = s.color.color;
      if (s.customization.trim().isNotEmpty) {
        props['TINT_CUSTOMIZATION'] = s.customization.trim();
      } else {
        props.remove('TINT_CUSTOMIZATION');
      }
      return widget.originalItem.copyWith(
        quantity: s.quantity.toDouble(),
        props: props,
      );
    }).toList();
    Navigator.of(context).pop(newItems);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: const Text('Колеровка')),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 88, height: 88,
                child: (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: widget.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.grey.shade100),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade100,
                          child: Icon(Icons.format_paint_outlined, color: Colors.grey.shade400, size: 32),
                        ),
                      )
                    : Container(
                        color: Colors.grey.shade100,
                        child: Icon(Icons.format_paint_outlined, color: Colors.grey.shade400, size: 32),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(widget.displayName ?? widget.originalItem.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        Expanded(
          child: _colorCount == null ? _buildColorCountStep() : _buildColorSlotsStep(),
        ),
        if (_colorCount != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _allSlotsFilled ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: const Text('Добавить в корзину', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildColorCountStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        const Text('Выберите количество оттенков колеровки',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
          for (var n = 1; n <= _colorCountMax; n++)
            GestureDetector(
              onTap: () => _chooseColorCount(n),
              child: Container(
                width: 56, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w600, color: _green)),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _buildColorSlotsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Выберите цвета', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        for (var i = 0; i < _slots.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _openColorPicker(i),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: _slots[i] == null
                    ? Text('Выбрать цвет ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600))
                    : Row(children: [
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: _parseHexColor(_slots[i]!.color.color),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('${_slots[i]!.color.name} x ${_slots[i]!.quantity}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ]),
              ),
            ),
          ),
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

/// Шторка выбора одного цвета — палитра, поиск, результаты, кастомизация,
/// количество. Возвращает заполненный _TintSlotData через Navigator.pop,
/// или null при отмене.
class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.tintApi, required this.managerId, required this.palettes, this.initial});
  final TintApiService tintApi;
  final int managerId;
  final List<TintPalette> palettes;
  final _TintSlotData? initial;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  final _searchCtrl = TextEditingController();
  final _customizationCtrl = TextEditingController();

  String _paletteCode = 'all';
  List<TintColor> _results = [];
  TintColor? _selected;
  int _quantity = 1;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _selected = widget.initial!.color;
      _customizationCtrl.text = widget.initial!.customization;
      _quantity = widget.initial!.quantity;
      _searchCtrl.text = widget.initial!.color.name;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customizationCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _error = null; });
    try {
      final results = await widget.tintApi.search(managerId: widget.managerId, q: q, paletteCode: _paletteCode);
      debugPrint('TintScreen: поиск "$q" (палитра=$_paletteCode) — найдено: ${results.length}');
      if (mounted) setState(() { _results = results; _searching = false; });
    } catch (e) {
      debugPrint('TintScreen: ошибка поиска "$q": $e');
      if (mounted) setState(() { _searching = false; _error = 'Не удалось выполнить поиск'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(children: [
          Center(
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Выбрать цвет', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 8),

          // Палитра
          DropdownButtonFormField<String>(
            value: _paletteCode,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('Все палитры')),
              for (final p in widget.palettes)
                DropdownMenuItem(value: p.code, child: Text(p.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) => setState(() => _paletteCode = value ?? 'all'),
          ),
          const SizedBox(height: 10),

          // Поиск
          Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Поиск колеровки...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44, height: 44,
              child: FilledButton(
                onPressed: _searching ? null : _search,
                style: FilledButton.styleFrom(backgroundColor: _green, padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _searching
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search, color: Colors.white),
              ),
            ),
          ]),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
          const SizedBox(height: 8),

          // Результаты поиска
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(_searching ? '' : 'Введите название и нажмите поиск',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = _results[i];
                      final isSelected = _selected?.name == c.name && _selected?.palette == c.palette;
                      return ListTile(
                        dense: true,
                        tileColor: isSelected ? _green.withValues(alpha: 0.08) : null,
                        leading: Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: _parseHexColor(c.color),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                        ),
                        title: Text(c.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(c.palette, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        onTap: () => setState(() => _selected = c),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 8),
          Text('Кастомизация', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          TextField(
            controller: _customizationCtrl,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),

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
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                onPressed: () => setState(() => _quantity++),
                icon: const Icon(Icons.add),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected == null ? null : () => Navigator.pop(
                context,
                _TintSlotData(color: _selected!, customization: _customizationCtrl.text, quantity: _quantity),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: const Text('Ок', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}
