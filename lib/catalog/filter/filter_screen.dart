import 'package:flutter/material.dart';

// -------------------------------------------------------
// Модели
// -------------------------------------------------------
class FilterDef {
  final String code;
  final String name;
  final String type; // 'list' или 'range'
  final List<String> values;
  final double min;
  final double max;

  const FilterDef({
    required this.code,
    required this.name,
    required this.type,
    this.values = const [],
    this.min = 0,
    this.max = 0,
  });

  factory FilterDef.fromJson(Map<String, dynamic> j) => FilterDef(
    code:   j['code'] as String,
    name:   j['name'] as String,
    type:   j['type'] as String,
    values: (j['values'] as List<dynamic>?)
        ?.map((e) => e.toString()).toList() ?? [],
    min:    (j['min'] as num?)?.toDouble() ?? 0,
    max:    (j['max'] as num?)?.toDouble() ?? 0,
  );
}

class ActiveFilters {
  final RangeValues? price;
  final Map<String, Set<String>> props; // code -> выбранные значения
  final Map<String, RangeValues> ranges; // code -> range

  const ActiveFilters({
    this.price,
    this.props = const {},
    this.ranges = const {},
  });

  bool get isEmpty {
    final hasProps = props.values.any((v) => v.isNotEmpty);
    return price == null && !hasProps && ranges.isEmpty;
  }

  ActiveFilters copyWith({
    RangeValues? price,
    Map<String, Set<String>>? props,
    Map<String, RangeValues>? ranges,
  }) => ActiveFilters(
    price:  price  ?? this.price,
    props:  props  ?? this.props,
    ranges: ranges ?? this.ranges,
  );

  Map<String, dynamic> toRequestPayload() {
    final result = <String, dynamic>{};
    if (price != null) {
      result['price'] = {'min': price!.start, 'max': price!.end};
    }
    final propsOut = <String, dynamic>{};
    for (final entry in props.entries) {
      if (entry.value.isNotEmpty) {
        propsOut[entry.key] = entry.value.toList();
      }
    }
    for (final entry in ranges.entries) {
      propsOut[entry.key] = {'min': entry.value.start, 'max': entry.value.end};
    }
    if (propsOut.isNotEmpty) result['props'] = propsOut;
    return result;
  }

  int get activeCount {
    int n = price != null ? 1 : 0;
    n += props.values.where((v) => v.isNotEmpty).length;
    n += ranges.length;
    return n;
  }
}


// -------------------------------------------------------
// Экран фильтра
// -------------------------------------------------------
class FilterScreen extends StatefulWidget {
  const FilterScreen({
    super.key,
    required this.filters,
    required this.priceRange,
    required this.initial,
  });

  final List<FilterDef> filters;
  final RangeValues priceRange;
  final ActiveFilters initial;

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  late RangeValues _price;
  late Map<String, Set<String>> _props;
  late Map<String, RangeValues> _ranges;

  final _priceMinCtrl = TextEditingController();
  final _priceMaxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Зажимаем сохранённую цену в границах реального диапазона
    final savedPrice = widget.initial.price;
    if (savedPrice != null) {
      final clampedStart = savedPrice.start
          .clamp(widget.priceRange.start, widget.priceRange.end);
      final clampedEnd   = savedPrice.end
          .clamp(widget.priceRange.start, widget.priceRange.end);
      _price = RangeValues(
        clampedStart <= clampedEnd ? clampedStart : widget.priceRange.start,
        clampedEnd   >= clampedStart ? clampedEnd  : widget.priceRange.end,
      );
    } else {
      _price = widget.priceRange;
    }
    _props  = {
      for (final e in widget.initial.props.entries) e.key: Set.from(e.value)
    };
    _ranges = Map.from(widget.initial.ranges);
    _priceMinCtrl.text = _price.start.toInt().toString();
    _priceMaxCtrl.text = _price.end.toInt().toString();
  }

  @override
  void dispose() {
    _priceMinCtrl.dispose();
    _priceMaxCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.of(context).pop(ActiveFilters(
      price: _price,
      props: _props,
      ranges: _ranges,
    ));
  }

  void _clear() {
    setState(() {
      _price = widget.priceRange;
      _priceMinCtrl.text = _price.start.toInt().toString();
      _priceMaxCtrl.text = _price.end.toInt().toString();
      _props = {};
      _ranges = {};
    });
  }

  String _fmt(double v) {
    final s = v.toInt().toString().split('');
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₸';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Фильтры',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        actions: [
          TextButton(
            onPressed: _clear,
            child: const Text('Очистить',
                style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Цена
          _Section(
            title: 'Цена',
            child: Column(children: [
              Row(children: [
                Expanded(child: _RangeInput(
                  label: 'От',
                  controller: _priceMinCtrl,
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    if (n != null && n < _price.end) {
                      setState(() => _price = RangeValues(
                          n.clamp(widget.priceRange.start, _price.end), _price.end));
                    }
                  },
                )),
                const SizedBox(width: 12),
                Expanded(child: _RangeInput(
                  label: 'До',
                  controller: _priceMaxCtrl,
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    if (n != null && n > _price.start) {
                      setState(() => _price = RangeValues(_price.start,
                          n.clamp(_price.start, widget.priceRange.end)));
                    }
                  },
                )),
              ]),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF4CAF50),
                  thumbColor: const Color(0xFF4CAF50),
                  inactiveTrackColor: Colors.grey.shade200,
                  overlayColor: const Color(0x224CAF50),
                ),
                child: RangeSlider(
                  values: _price,
                  min: widget.priceRange.start,
                  max: widget.priceRange.end,
                  onChanged: (v) {
                    setState(() {
                      _price = v;
                      _priceMinCtrl.text = v.start.toInt().toString();
                      _priceMaxCtrl.text = v.end.toInt().toString();
                    });
                  },
                ),
              ),
            ]),
          ),

          // Динамические фильтры
          ...widget.filters.map((f) {
            if (f.type == 'range') {
              return _RangeFilterTile(
                filter: f,
                value: _ranges[f.code] ?? RangeValues(f.min, f.max),
                onChanged: (v) => setState(() => _ranges[f.code] = v),
              );
            } else {
              return _ListFilterTile(
                filter: f,
                selected: _props[f.code] ?? const {},
                onToggle: (val) => setState(() {
                  _props[f.code] ??= {};
                  if (_props[f.code]!.contains(val)) {
                    _props[f.code]!.remove(val);
                  } else {
                    _props[f.code]!.add(val);
                  }
                }),
              );
            }
          }),

          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Применить',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------
// Секция с заголовком
// -------------------------------------------------------
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

// -------------------------------------------------------
// Range input поле
// -------------------------------------------------------
class _RangeInput extends StatelessWidget {
  const _RangeInput({required this.label, required this.controller, required this.onChanged});
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF3F2F7),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ]);
  }
}

// -------------------------------------------------------
// Range filter (размеры)
// -------------------------------------------------------
class _RangeFilterTile extends StatelessWidget {
  const _RangeFilterTile({required this.filter, required this.value, required this.onChanged});
  final FilterDef filter;
  final RangeValues value;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ExpandableTile(
      title: filter.name,
      child: Column(children: [
        Row(children: [
          Expanded(child: _RangeInput(
            label: 'От',
            controller: TextEditingController(text: value.start.toInt().toString()),
            onChanged: (v) {
              final n = double.tryParse(v);
              if (n != null && n < value.end) {
                onChanged(RangeValues(
                    n.clamp(filter.min, value.end), value.end));
              }
            },
          )),
          const SizedBox(width: 12),
          Expanded(child: _RangeInput(
            label: 'До',
            controller: TextEditingController(text: value.end.toInt().toString()),
            onChanged: (v) {
              final n = double.tryParse(v);
              if (n != null && n > value.start) {
                onChanged(RangeValues(value.start,
                    n.clamp(value.start, filter.max)));
              }
            },
          )),
        ]),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF4CAF50),
            thumbColor: const Color(0xFF4CAF50),
            inactiveTrackColor: Colors.grey.shade200,
          ),
          child: RangeSlider(
            values: value,
            min: filter.min,
            max: filter.max,
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------
// List filter (checkbox с поиском)
// -------------------------------------------------------
class _ListFilterTile extends StatefulWidget {
  const _ListFilterTile({required this.filter, required this.selected, required this.onToggle});
  final FilterDef filter;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  State<_ListFilterTile> createState() => _ListFilterTileState();
}

class _ListFilterTileState extends State<_ListFilterTile> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final values = widget.filter.values
        .where((v) => _search.isEmpty ||
            v.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return _ExpandableTile(
      title: widget.filter.name,
      badge: widget.selected.isEmpty ? null : '${widget.selected.length}',
      child: Column(children: [
        // Поиск (если значений больше 5)
        if (widget.filter.values.length > 5) ...[
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Поиск',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: const Color(0xFFF3F2F7),
              contentPadding: EdgeInsets.zero,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Список значений
        ...values.map((v) {
          final isSelected = widget.selected.contains(v);
          return InkWell(
            onTap: () => widget.onToggle(v),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4CAF50) : Colors.white,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4CAF50)
                          : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(v,
                    style: TextStyle(
                      fontSize: 14,
                      color: isSelected ? const Color(0xFF4CAF50) : Colors.black87,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
              ]),
            ),
          );
        }),

        if (values.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Ничего не найдено',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
      ]),
    );
  }
}

// -------------------------------------------------------
// Разворачиваемый тайл
// -------------------------------------------------------
class _ExpandableTile extends StatefulWidget {
  const _ExpandableTile({required this.title, required this.child, this.badge});
  final String title;
  final Widget child;
  final String? badge;

  @override
  State<_ExpandableTile> createState() => _ExpandableTileState();
}

class _ExpandableTileState extends State<_ExpandableTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              Expanded(
                child: Row(children: [
                  Text(widget.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  if (widget.badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(widget.badge!,
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ]),
              ),
              Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: Colors.grey.shade500,
              ),
            ]),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: widget.child,
          ),
      ]),
    );
  }
}
