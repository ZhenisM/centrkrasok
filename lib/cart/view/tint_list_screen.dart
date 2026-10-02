import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:centrkrasok/cart/tint_basket_service.dart';
import 'package:centrkrasok/cart/view/tint_request_screen.dart';

/// «Мои колеровки» — как список /tint/ на сайте (заявки этого менеджера).
class TintListScreen extends StatefulWidget {
  const TintListScreen({super.key});

  @override
  State<TintListScreen> createState() => _TintListScreenState();
}

class _TintListScreenState extends State<TintListScreen> {
  final _service = TintBasketService(dio: Dio());
  List<TintListItem>? _items;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await _service.list();
      setState(() => _items = items);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
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
          title: const Text('Мои колеровки'),
        ),
        body: _items == null
            ? Center(
                child: _error != null
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Повторить')),
                      ])
                    : const CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _items!.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Колеровок пока нет', style: TextStyle(color: Colors.grey))),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items!.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final t = _items![i];
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final added = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(builder: (_) => TintRequestScreen(tintId: t.id)),
                                );
                                if (added == true) _changed = true;
                                _load();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(children: [
                                  Container(
                                    width: 96,
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                        color: tintStatusColor(t.statusCode), borderRadius: BorderRadius.circular(8)),
                                    child: Text(t.statusName,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: t.statusCode == 'in_process' || t.statusCode == 'price_set'
                                                ? Colors.white
                                                : Colors.black87)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('№${t.id}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                      Text([t.date, if (t.client.isNotEmpty) t.client].join(' · '),
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                      if (t.priceSetter.isNotEmpty)
                                        Text('Цены проставил: ${t.priceSetter}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                    ]),
                                  ),
                                  const Icon(Icons.chevron_right, color: Colors.grey),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
