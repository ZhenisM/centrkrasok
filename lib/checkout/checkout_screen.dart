import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:centrkrasok/checkout/order_service.dart';
import 'package:centrkrasok/checkout/order_success_screen.dart';

const _green = Color(0xFF4CAF50);
const _bg = Color(0xFFF3F2F7);

/// «СТОИМОСТЬ ДОСТАВКИ»: физлицо — 120, юрлицо — 201.
const _deliveryCostIds = {120, 201};

/// Оформление заказа — как страница оформления сайта: тип плательщика,
/// поля из Bitrix с автозаполнением, условные поля, состав и сумма.
/// Возвращает true, если заказ оформлен (корзина ушла в «оформленные»).
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.basketId});
  final String basketId;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _service = OrderService(dio: Dio());
  OrderForm? _form;
  String? _error;
  bool _loading = false;
  bool _submitting = false;

  final Map<int, dynamic> _values = {};
  final Map<int, TextEditingController> _ctrls = {};
  final _commentCtrl = TextEditingController();
  final Set<int> _invalid = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({int? personType}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final form = await _service.form(widget.basketId, personType: personType);
      setState(() {
        _form = form;
        _values
          ..clear()
          ..addAll(form.values);
        for (final c in _ctrls.values) {
          c.dispose();
        }
        _ctrls.clear();
        _invalid.clear();
        _commentCtrl.text = form.comment;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TextEditingController _ctrl(OrderPropField f) => _ctrls.putIfAbsent(f.id, () {
        final v = _values[f.id];
        return TextEditingController(text: v == null ? '' : (v is List ? v.join(', ') : v.toString()));
      });

  String _str(int id) {
    final v = _values[id];
    if (v is List) return v.isEmpty ? '' : v.first.toString();
    return v?.toString() ?? '';
  }

  bool _visible(OrderPropField f) {
    final form = _form!;
    if (form.hidden.contains(f.id) || form.auto.contains(f.id)) return false;
    for (final r in form.rules) {
      if (r.props.contains(f.id)) return _str(r.when) == r.equals;
    }
    return true;
  }

  bool _required(OrderPropField f) {
    for (final r in _form!.rules) {
      if (r.props.contains(f.id)) return r.required ? _str(r.when) == r.equals : f.required;
    }
    return f.required;
  }

  bool _empty(dynamic v) {
    if (v == null) return true;
    if (v is List) return v.where((e) => e.toString().trim().isNotEmpty).isEmpty;
    return v.toString().trim().isEmpty;
  }

  Future<void> _submit() async {
    final form = _form;
    if (form == null) return;
    final missing = <String>[];
    final payload = <int, dynamic>{};
    _invalid.clear();
    for (final f in form.props) {
      if (form.auto.contains(f.id)) {
        // Скрытые поля, которые сайт заполняет сам, — отправляем как есть.
        if (!_empty(_values[f.id])) payload[f.id] = _values[f.id];
        continue;
      }
      if (!_visible(f)) continue;
      final v = _values[f.id];
      if (_required(f) && _empty(v)) {
        missing.add(f.name);
        _invalid.add(f.id);
      }
      if (!_empty(v)) payload[f.id] = v;
    }
    if (missing.isNotEmpty) {
      setState(() {});
      _snack('Заполните: ${missing.join(', ')}');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Оформить заказ?'),
        content: Text('Сумма: ${_fmt(form.total)} ₸. Заказ уйдёт в работу и в 1С.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: _green),
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Оформить')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _submitting = true);
    try {
      final order = await _service.create(
        basketId: widget.basketId,
        personType: form.personType,
        values: payload,
        comment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OrderSuccessScreen(order: order)),
        result: true,
      );
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Заказ не оформлен'),
            content: SingleChildScrollView(child: SelectableText(e.toString())),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    final form = _form;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _green, foregroundColor: Colors.white, title: const Text('Оформление заказа')),
      body: form == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Повторить')),
                      ]))
                  : const CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _loading || _submitting,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
                _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Title('Товары в заказе (${form.basket.length})'),
                  ...form.basket.map(_basketLine),
                  const Divider(height: 20),
                  Row(children: [
                    const Expanded(child: Text('Итого', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                    Text('${_fmt(form.total)} ₸', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                ])),
                _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _Title('Тип плательщика'),
                  SegmentedButton<int>(
                    segments: form.personTypes
                        .map((e) => ButtonSegment(value: e.key, label: Text(e.value, textAlign: TextAlign.center)))
                        .toList(),
                    selected: {form.personType},
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                          (s) => s.contains(WidgetState.selected) ? _green : Colors.white),
                      foregroundColor: WidgetStateProperty.resolveWith(
                          (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.black87),
                    ),
                    onSelectionChanged: (s) => _load(personType: s.first),
                  ),
                ])),
                _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _Title('Покупатель'),
                  ...form.props.where((f) => _visible(f) && !_deliveryCostIds.contains(f.id)).map(_field),
                ])),
                // «Стоимость доставки» — как на сайте, отдельно перед комментарием.
                if (form.props.any((f) => _deliveryCostIds.contains(f.id) && _visible(f)))
                  _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ...form.props.where((f) => _deliveryCostIds.contains(f.id) && _visible(f)).map(_field),
                  ])),
                _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _Title('Комментарий к заказу'),
                  TextField(controller: _commentCtrl, maxLines: 3, decoration: _dec(null)),
                ])),
                if (_loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
              ]),
            ),
      bottomNavigationBar: form == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: _submitting || _loading ? null : _submit,
                    child: _submitting
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Оформить заказ · ${_fmt(form.total)} ₸',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: child,
      );

  /// Товар: картинка над названием, колеровка, количество × цена, сумма.
  Widget _basketLine(OrderBasketLine l) {
    final tint = l.props['TINT_NAME'];
    final rgb = l.props['TINT_RGB'];
    final discounted = l.basePrice > l.price + 0.5;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: l.picture.isEmpty
                ? Container(width: 120, height: 120, color: Colors.white,
                    child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400))
                : CachedNetworkImage(imageUrl: l.picture, width: 120, height: 120, fit: BoxFit.contain,
                    errorWidget: (context, url, error) => Container(width: 120, height: 120, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 8),
        Text(l.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        if (tint != null && tint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              if (rgb != null && rgb.isNotEmpty)
                Container(width: 14, height: 14, margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: _hex(rgb), shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300))),
              Expanded(child: Text('Колеровка: $tint${l.props['TINT_PRICE'] != null ? ' · ${l.props['TINT_PRICE']} ₸' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
            ]),
          ),
        if (l.props['TINT_DISCOUNT'] != null)
          Text('Скидка на колеровку: ${l.props['TINT_DISCOUNT']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${_qty(l.quantity)} ${l.measure} × ${_fmt(l.price)} ₸'),
              if (discounted)
                TextSpan(text: '  ${_fmt(l.basePrice)} ₸',
                    style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)),
            ]), style: const TextStyle(fontSize: 13)),
          ),
          Text('${_fmt(l.sum)} ₸', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Widget _label(OrderPropField f) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(children: [
          if (_required(f)) const TextSpan(text: '* ', style: TextStyle(color: Colors.red)),
          TextSpan(text: f.name, style: TextStyle(fontWeight: FontWeight.w600,
              color: _invalid.contains(f.id) ? Colors.red : Colors.black87)),
          if (f.description.isNotEmpty)
            TextSpan(text: '\n${f.description}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ])),
      );

  Widget _field(OrderPropField f) {
    Widget input;
    final form = _form!;
    if (f.type == 'ENUM' && f.multiple) {
      final cur = (_values[f.id] is List ? List<String>.from((_values[f.id] as List).map((e) => e.toString())) : <String>[]);
      input = Wrap(spacing: 8, runSpacing: 4, children: f.variants.map((v) {
        final sel = cur.contains(v.key);
        return FilterChip(
          label: Text(v.value), selected: sel, selectedColor: _green.withValues(alpha: 0.2),
          onSelected: (on) => setState(() {
            on ? cur.add(v.key) : cur.remove(v.key);
            _values[f.id] = List<String>.from(cur);
          }),
        );
      }).toList());
    } else if (f.type == 'ENUM' && (f.asList || f.variants.length > 12)) {
      final cur = _str(f.id);
      input = DropdownButtonFormField<String>(
        initialValue: f.variants.any((v) => v.key == cur) ? cur : null,
        isExpanded: true,
        decoration: _dec(null),
        items: f.variants.map((v) => DropdownMenuItem(value: v.key, child: Text(v.value))).toList(),
        onChanged: (v) => setState(() => _values[f.id] = v),
      );
    } else if (f.type == 'ENUM') {
      final cur = _str(f.id);
      input = Wrap(spacing: 8, runSpacing: 4, children: f.variants.map((v) => ChoiceChip(
            label: Text(v.value), selected: cur == v.key, selectedColor: _green.withValues(alpha: 0.2),
            onSelected: (_) => setState(() => _values[f.id] = v.key),
          )).toList());
    } else if (f.type == 'Y/N') {
      input = Switch(value: _str(f.id) == 'Y', activeThumbColor: _green,
          onChanged: (on) => setState(() => _values[f.id] = on ? 'Y' : 'N'));
    } else if (f.type == 'DATE') {
      input = OutlinedButton.icon(
        icon: const Icon(Icons.calendar_today, size: 18),
        label: Text(_str(f.id).isEmpty ? 'Выбрать дату' : _str(f.id)),
        onPressed: () async {
          final d = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: DateTime.now());
          if (d != null) {
            setState(() => _values[f.id] =
                '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}');
          }
        },
      );
    } else {
      final isPartner = f.id == form.partnerPropId;
      input = TextField(
        controller: _ctrl(f),
        maxLines: f.multiline ? 3 : 1,
        keyboardType: f.isPhone || f.code.contains('PHONE') || f.name.toLowerCase().contains('телефон')
            ? TextInputType.phone
            : f.type == 'NUMBER' || f.name.toLowerCase().contains('площадь')
                ? const TextInputType.numberWithOptions(decimal: true)
                : f.isEmail ? TextInputType.emailAddress : TextInputType.text,
        decoration: _dec(isPartner ? 'Начните вводить — найдём в базе' : null).copyWith(
          suffixIcon: isPartner ? IconButton(icon: const Icon(Icons.search), onPressed: () => _searchPartner(f)) : null,
        ),
        onChanged: (v) => _values[f.id] = v,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label(f), input]),
    );
  }

  /// Поиск партнёра/дизайнера по базе — как подсказки на сайте.
  Future<void> _searchPartner(OrderPropField f) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PartnerSearchSheet(service: _service, personType: _form!.personType, initial: _ctrl(f).text),
    );
    if (picked != null) {
      setState(() {
        _ctrl(f).text = picked;
        _values[f.id] = picked;
      });
    }
  }
}

class _PartnerSearchSheet extends StatefulWidget {
  const _PartnerSearchSheet({required this.service, required this.personType, required this.initial});
  final OrderService service;
  final int personType;
  final String initial;

  @override
  State<_PartnerSearchSheet> createState() => _PartnerSearchSheetState();
}

class _PartnerSearchSheetState extends State<_PartnerSearchSheet> {
  late final TextEditingController _q = TextEditingController(text: widget.initial.startsWith('.') ? '' : widget.initial);
  List<OrderPartner> _items = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (_q.text.length >= 2) _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final r = await widget.service.partners(_q.text, widget.personType);
      if (mounted) setState(() => _items = r);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _q,
              autofocus: true,
              decoration: _dec('Название или ФИО (от 2 букв)'),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _search);
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(children: _items.map((p) => ListTile(
                  title: Text(p.name),
                  subtitle: p.bin.isNotEmpty ? Text(p.bin) : null,
                  onTap: () => Navigator.pop(context, p.name),
                )).toList()),
          ),
        ]),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      );
}

InputDecoration _dec(String? hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: _bg,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

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

Color _hex(String hex) {
  final h = hex.replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? Colors.grey.shade300 : Color(v);
}
