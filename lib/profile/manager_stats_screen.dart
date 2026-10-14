import 'package:flutter/material.dart';
import 'package:centrkrasok/profile/profile_api.dart';

/// «Мои успехи» — по макету: переключатель двух последних месяцев сверху,
/// карточки показателей за выбранный месяц (заказы, сумма, оплачено) и
/// разбивка по статусам. Данные — как страница /manager/ сайта
/// (App\Manager::getOrders), только за календарный месяц.
class ManagerStatsScreen extends StatefulWidget {
  const ManagerStatsScreen({super.key});
  @override
  State<ManagerStatsScreen> createState() => _ManagerStatsScreenState();
}

class _ManagerStatsScreenState extends State<ManagerStatsScreen> {
  final _api = ProfileApi();
  // [0] — прошлый месяц, [1] — текущий (слева направо, как на макете)
  final List<Map<String, dynamic>?> _months = [null, null];
  final List<String?> _errors = [null, null];
  int _selected = 1;

  static const _green = Color(0xFF14A10E);
  static const _bg = Color(0xFFF3F2F7);

  @override
  void initState() {
    super.initState();
    _load(0);
    _load(1);
  }

  Future<void> _load(int index) async {
    setState(() => _errors[index] = null);
    try {
      final d = await _api.call('month', {'offset': index == 1 ? '0' : '1'});
      if (mounted) setState(() => _months[index] = d);
    } catch (e) {
      if (mounted) setState(() => _errors[index] = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _tabTitle(int i) => (_months[i]?['title'] as String?) ?? (i == 1 ? 'Этот месяц' : 'Прошлый месяц');

  @override
  Widget build(BuildContext context) {
    final d = _months[_selected];
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white,
        title: const Text('Мои успехи', style: TextStyle(fontWeight: FontWeight.w600)), centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(_selected),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          // Переключатель месяцев
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0xFFE6E6EB), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              for (final i in [0, 1])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _selected == i ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(_tabTitle(i),
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: _selected == i ? Colors.black87 : Colors.grey.shade500,
                          )),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          if (d == null)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(child: _errors[_selected] != null
                  ? Column(children: [
                      Text(_errors[_selected]!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => _load(_selected), child: const Text('Повторить')),
                    ])
                  : const CircularProgressIndicator()),
            )
          else ...[
            _card('Статистика', Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _metric('Заказов', '${d['total_amount']}', Colors.black87, flex: 2),
              const SizedBox(width: 12),
              _metric('Сумма', '${fmtMoney(d['total_price'] as num)} ₸', _green, flex: 4),
              const SizedBox(width: 12),
              _metric('Оплачено', '${fmtMoney(d['total_paid_price'] as num)} ₸', _green, flex: 4),
            ])),
            if ((d['statuses'] as List).isNotEmpty)
              _card('По статусам', Column(children: [
                Row(children: [
                  Expanded(flex: 5, child: Text('Статус', style: _label)),
                  Expanded(flex: 2, child: Text('Заказов', style: _label, textAlign: TextAlign.center)),
                  Expanded(flex: 3, child: Text('Сумма', style: _label, textAlign: TextAlign.right)),
                ]),
                const Divider(height: 16),
                ...(d['statuses'] as List).map((s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(flex: 5, child: Text('${s['name']}', style: const TextStyle(fontSize: 14))),
                        Expanded(flex: 2, child: Text('${s['amount']}', textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                        Expanded(flex: 3, child: Text('${fmtMoney(s['price'] as num)} ₸', textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                      ]),
                    )),
              ]))
            else
              _card('По статусам', Text('Заказов за этот месяц нет', style: TextStyle(color: Colors.grey.shade600))),
          ],
        ]),
      ),
    );
  }

  TextStyle get _label => TextStyle(fontSize: 12, color: Colors.grey.shade500);

  Widget _card(String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 14),
          child,
        ]),
      );

  Widget _metric(String label, String value, Color color, {int flex = 1}) => Expanded(
        flex: flex,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _label),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: color)),
          ),
        ]),
      );
}
