import 'package:flutter/material.dart';
import 'package:centrkrasok/profile/client_orders_screen.dart';
import 'package:centrkrasok/profile/profile_api.dart';

/// «Кабинет клиента» — как /client/ и /client/orders/ сайта: данные
/// текущего клиента (предпочтения, персональные скидки), сделки клиента
/// в ЦК и Свете, заказы по статусам и список всех заказов.
class ClientCabinetScreen extends StatefulWidget {
  const ClientCabinetScreen({super.key, required this.basketId});
  final String basketId;
  @override
  State<ClientCabinetScreen> createState() => _ClientCabinetScreenState();
}

class _ClientCabinetScreenState extends State<ClientCabinetScreen> {
  final _api = ProfileApi();
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await _api.call('client', {'basket_id': widget.basketId});
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Color _hex(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? Colors.grey : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white,
        title: const Text('Кабинет клиента', style: TextStyle(fontWeight: FontWeight.w600)), centerTitle: true,
      ),
      body: d == null
          ? Center(child: _error != null
              ? Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Повторить')),
                ]))
              : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              _clientCard(Map<String, dynamic>.from(d['client'] as Map)),
              _dealsCard(Map<String, dynamic>.from(d['deals'] as Map)),
              _ordersSummary(Map<String, dynamic>.from(d['orders'] as Map)),
              _ordersList(),
            ]),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          Expanded(child: Text(v.isEmpty ? '—' : v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ]),
      );

  Widget _clientCard(Map<String, dynamic> c) {
    final isCompany = c['entity'] == 'COMPANY';
    String pct(num v) => '${v % 1 == 0 ? v.toInt() : v}%';
    return _card('Текущий клиент', [
      if (isCompany) ...[
        _kv('Наименование', '${c['title']}'),
        _kv('ИИН', '${c['iin']}'),
      ] else ...[
        _kv('Тип', '${c['type']}'),
        _kv('Имя', '${c['name']}'),
        _kv('Телефон', '${c['phone']}'),
        if ((c['favor'] as List).isNotEmpty) _kv('Предпочтения', (c['favor'] as List).join(' / ')),
        const SizedBox(height: 6),
        Text('Персональная скидка', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        _kv('Argile & PPL', pct(c['discount_argile_ppl'] as num)),
        _kv('Все', pct(c['discount_other'] as num)),
      ],
    ]);
  }

  Widget _dealsCard(Map<String, dynamic> deals) {
    Widget block(String title, Map m) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            _kv('Сделок', '${m['amount']}'),
            _kv('На сумму', '${fmtMoney(m['price'] as num)} ₸'),
            _kv('Последний менеджер', '${m['last_manager']}'),
          ]),
        );
    return _card('Сделки клиента', [
      block('Центр Красок', deals['ck'] as Map),
      block('Svet', deals['svet'] as Map),
    ]);
  }

  Widget _ordersSummary(Map<String, dynamic> o) => _card('Заказы клиента', [
        ...((o['statuses'] as List?) ?? []).map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(color: _hex('${s['color']}'), shape: BoxShape.circle)),
                Expanded(child: Text('${s['name']}', style: const TextStyle(fontSize: 13))),
                SizedBox(width: 36, child: Text('${s['total']}', textAlign: TextAlign.center)),
                SizedBox(width: 100, child: Text('${fmtMoney(s['price'] as num)} ₸', textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            )),
        const Divider(),
        Row(children: [
          const Expanded(child: Text('Итого', style: TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 36, child: Text('${o['total']}', textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 100, child: Text('${fmtMoney(o['price'] as num)} ₸', textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ]);

  /// «Все заказы клиента» — отдельный экран, как в offlinesvet.
  Widget _ordersList() {
    final c = Map<String, dynamic>.from(_data!['client'] as Map);
    final title = c['entity'] == 'COMPANY' ? '${c['title']}' : '${c['name']}';
    return SizedBox(
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ClientOrdersScreen(basketId: widget.basketId, title: title))),
        child: const Text('Все заказы клиента', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
