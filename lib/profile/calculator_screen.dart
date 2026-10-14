import 'package:flutter/material.dart';

/// «Калькулятор» — как модальное окно calculator.php на сайте: объём
/// краски для стен (минус окна и двери, 2 слоя) и для потолка.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _Opening {
  final h = TextEditingController();
  final w = TextEditingController();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _wallH = TextEditingController();
  final _wallP = TextEditingController();
  final List<_Opening> _windows = [];
  final List<_Opening> _doors = [];
  final _wallRate = TextEditingController();
  final _ceilL = TextEditingController();
  final _ceilW = TextEditingController();
  final _ceilRate = TextEditingController();

  double _n(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;
  String _f(double v) => v == 0 ? '0' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

  @override
  Widget build(BuildContext context) {
    final wallArea = _n(_wallH) * _n(_wallP);
    final openings = [..._windows, ..._doors].fold<double>(0, (s, o) => s + _n(o.h) * _n(o.w));
    final rawPaint = wallArea - openings;
    final badData = rawPaint < 0; // как на сайте: «ошибка в данных»
    final paintArea = badData ? 0.0 : rawPaint;
    final twoLayers = paintArea * 2;
    final wallGrams = twoLayers * _n(_wallRate);
    final ceilArea = _n(_ceilL) * _n(_ceilW);
    final ceilGrams = ceilArea * _n(_ceilRate);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white,
        title: const Text('Калькулятор', style: TextStyle(fontWeight: FontWeight.w600)), centerTitle: true,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _card('Объём краски для стен', [
            _sub('Площадь стен комнаты'),
            _pair(_wallH, 'Высота, м', _wallP, 'Периметр, м'),
            _result('Результат', '${_f(wallArea)} м²'),
            _sub('Общая площадь дверей и окон'),
            ..._windows.asMap().entries.map((e) => _openingRow('Окно ${e.key + 1}', e.value, () => _windows.removeAt(e.key))),
            ..._doors.asMap().entries.map((e) => _openingRow('Дверь ${e.key + 1}', e.value, () => _doors.removeAt(e.key))),
            Row(children: [
              TextButton.icon(onPressed: () => setState(() => _windows.add(_Opening())),
                  icon: const Icon(Icons.add), label: const Text('Окно')),
              TextButton.icon(onPressed: () => setState(() => _doors.add(_Opening())),
                  icon: const Icon(Icons.add), label: const Text('Дверь')),
            ]),
            _result('Результат', '${_f(openings)} м²'),
            const Divider(height: 24),
            _result('Окрашиваемая поверхность стен', badData ? 'ошибка в данных' : '${_f(paintArea)} м²'),
            _result('Площадь покраски (2 слоя)', badData ? 'ошибка в данных' : '${_f(twoLayers)} м²'),
            _sub('Необходимый объём материала'),
            _field(_wallRate, 'Расход в г/м² или мл/м²'),
            _result('Результат в г. или мл.', _f(wallGrams)),
            _result('Результат в кг. или л.', _f(wallGrams / 1000), bold: true),
          ]),
          _card('Объём краски для потолка', [
            _sub('Площадь потолка'),
            _pair(_ceilL, 'Длина, м', _ceilW, 'Ширина, м'),
            _result('Результат', '${_f(ceilArea)} м²'),
            _sub('Необходимый объём материала'),
            _field(_ceilRate, 'Расход в г/м² или мл/м²'),
            _result('Результат в г. или мл.', _f(ceilGrams)),
            _result('Результат в кг. или л.', _f(ceilGrams / 1000), bold: true),
          ]),
        ]),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  Widget _sub(String t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Widget _field(TextEditingController c, String hint) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: hint, isDense: true, filled: true, fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
      );

  Widget _pair(TextEditingController a, String ha, TextEditingController b, String hb) => Row(children: [
        Expanded(child: _field(a, ha)),
        const SizedBox(width: 8),
        Expanded(child: _field(b, hb)),
      ]);

  Widget _openingRow(String label, _Opening o, VoidCallback remove) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 62, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(child: _field(o.h, 'Высота, м')),
          const SizedBox(width: 6),
          Expanded(child: _field(o.w, 'Ширина, м')),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(remove)),
        ]),
      );

  Widget _result(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 17 : 14, color: bold ? const Color(0xFF2E7D32) : Colors.black87)),
        ]),
      );
}
