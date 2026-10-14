import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:centrkrasok/profile/profile_api.dart';

/// Редактирование заказа — та же страница Bitrix (sale_order_edit.php),
/// что «Изменить» в «Заказах клиента» сайта.
///
/// Вход: сервер выдаёт одноразовую ссылку (profile.php → edit_link),
/// по которой WebView САМ авторизуется на prons.kz. Раньше в WebView
/// подкладывались куки сессии из приложения — сайт видел две сессии
/// и показывал форму авторизации по кругу.
class OrderEditScreen extends StatefulWidget {
  final int orderId;
  final String orderNumber;
  const OrderEditScreen({super.key, required this.orderId, required this.orderNumber});

  @override
  State<OrderEditScreen> createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends State<OrderEditScreen> {
  WebViewController? _controller;
  bool _loading = true;
  bool _editLoaded = false;
  String? _error;

  static const _host = 'prons.kz';

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() { _error = null; _loading = true; });
    try {
      // Чистые куки — чтобы старые сессии не мешали входу.
      await WebViewCookieManager().clearCookies();
      final r = await ProfileApi().call('edit_link', {'order_id': '${widget.orderId}'});
      final url = r['url'].toString();
      final c = _controller ?? _createController();
      _controller = c;
      await c.loadRequest(Uri.parse(url));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  WebViewController _createController() => WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) { if (mounted) setState(() => _loading = true); },
      onPageFinished: (url) {
        if (!mounted) return;
        setState(() => _loading = false);
        if (url.contains('/bitrix/admin/sale_order_edit.php') || url.contains('/bitrix/admin/sale_order_shipment_edit.php')) {
          _editLoaded = true;
          // Как на сайте: прячем кнопку «Список» и шапку админки.
          _controller?.runJavaScript('''
            ['btn_list','bx-panel','header'].forEach(function(id){var e=document.getElementById(id); if(e) e.style.display='none';});
          ''');
        }
      },
      onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        if (uri == null) return NavigationDecision.prevent;
        final inEditor = uri.path.contains('/bitrix/admin/sale_order_edit.php') ||
            uri.path.contains('/bitrix/admin/sale_order_shipment_edit.php') ||
            uri.path.contains('/ajax/centrkrasok/order_edit_login.php') ||
            uri.path.startsWith('/bitrix/') ;
        if (uri.host == _host && inEditor) return NavigationDecision.navigate;
        // Ушли со страницы редактирования (сохранили и т.п.) — закрываем экран.
        if (_editLoaded && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заказ сохранён')));
          Navigator.of(context).pop(true);
        }
        return NavigationDecision.prevent;
      },
    ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop(_editLoaded)),
        title: Text('Заказ #${widget.orderNumber}'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _open)],
      ),
      body: _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 44),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _open, child: const Text('Повторить')),
              ]),
            ))
          : Stack(children: [
              if (_controller != null) WebViewWidget(controller: _controller!),
              if (_loading) const LinearProgressIndicator(color: Color(0xFF4CAF50), backgroundColor: Color(0xFFE8F5E9)),
            ]),
    );
  }
}
