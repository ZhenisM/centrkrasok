import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:centrkrasok/checkout/order_service.dart';

const _green = Color(0xFF4CAF50);

/// «Заказ создан» — как страница подтверждения сайта: номер и дата заказа,
/// печать КП (те же компоненты сайта: «КП» и «КП НОВЫЕ»).
class OrderSuccessScreen extends StatefulWidget {
  const OrderSuccessScreen({super.key, required this.order});
  final CreatedOrder order;

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> {
  final _service = OrderService(dio: Dio());
  bool _busy = false;

  Future<void> _open(String kind, String city, String lang, {bool print = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await _service.kpLink(widget.order.orderId, kind: kind, city: city, lang: lang, print: print);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) messenger.showSnackBar(const SnackBar(content: Text('Не удалось открыть КП')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final city = o.city;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, true);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F2F7),
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          title: const Text('Заказ оформлен'),
          automaticallyImplyLeading: false,
          actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, true))],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              const Icon(Icons.check_circle, color: _green, size: 56),
              const SizedBox(height: 8),
              Text('Заказ №${o.accountNumber.isNotEmpty ? o.accountNumber : o.orderId}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('от ${o.date} успешно создан', style: TextStyle(color: Colors.grey.shade700)),
            ]),
          ),
          const SizedBox(height: 16),
          _section('КП', [
            _btn('Распечатать', Icons.print_outlined, () => _open('v1', city, 'ru', print: true)),
            _btn('Для клиента', Icons.picture_as_pdf_outlined, () => _open('v1', city, 'ru')),
            _btn('Для клиента (каз)', Icons.picture_as_pdf_outlined, () => _open('v1', city, 'kz')),
          ]),
          _section('КП НОВЫЕ', [
            _btn('КП Алматы', Icons.picture_as_pdf_outlined, () => _open('v2', 'almaty', 'ru')),
            _btn('КП Алматы (каз)', Icons.picture_as_pdf_outlined, () => _open('v2', 'almaty', 'kz')),
            _btn('КП Астана', Icons.picture_as_pdf_outlined, () => _open('v2', 'astana', 'ru')),
            _btn('КП Астана (каз)', Icons.picture_as_pdf_outlined, () => _open('v2', 'astana', 'kz')),
          ]),
          if (_busy) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Готово', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _section(String title, List<Widget> buttons) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...buttons,
        ]),
      );

  Widget _btn(String label, IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            icon: Icon(icon, size: 20),
            label: Align(alignment: Alignment.centerLeft, child: Text(label)),
            onPressed: _busy ? null : onTap,
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
      );
}
