import 'package:flutter/material.dart';
import 'package:centrkrasok/auth/auth_service.dart';
import 'package:centrkrasok/customer/customer.dart';
import 'package:centrkrasok/customer/view/new_customer_dialog.dart';
import 'package:centrkrasok/customer/view/search_customer_screen.dart';
import 'package:centrkrasok/repositories/products/catalog_sync_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Customer? _activeCustomer;
  bool _loadingCustomer = true;

  @override
  void initState() {
    super.initState();
    _loadActiveCustomer();
    _maybeSyncCatalog();
  }

  // Полная фоновая синхронизация каталога — не чаще раза в сутки (см.
  // CatalogSyncService.shouldSync()), не блокирует экран: если каталог
  // уже синхронизировался недавно, ничего не произойдёт; если давно
  // (или никогда) — тихо начнёт скачивать в фоне, экран продолжает
  // работать как обычно.
  Future<void> _maybeSyncCatalog() async {
    final syncService = CatalogSyncService();
    if (await syncService.shouldSync()) {
      syncService.syncFullCatalog();
    }
  }

  Future<void> _loadActiveCustomer() async {
    final customer = await CustomerStorage.loadActive();
    if (!mounted) return;
    setState(() {
      _activeCustomer = customer;
      _loadingCustomer = false;
    });
  }

  Future<void> _openNewCustomer() async {
    final selected = await showNewCustomerDialog(context);
    if (selected == true) {
      _loadActiveCustomer();
    }
  }

  Future<void> _openSearchCustomer() async {
    final selected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SearchCustomerScreen()),
    );
    if (selected == true) {
      _loadActiveCustomer();
    }
  }

  Future<void> _confirmLogout() async {
    bool? confirm = await showDialog(
      context: context,
      // На iPad один и тот же тап иногда обрабатывается как два события:
      // открытие диалога и практически сразу — тап по затемнённому фону
      // (barrier), из-за чего диалог мгновенно закрывался сам, без явного
      // нажатия "Отмена"/"Выйти" (на Android/эмуляторе так не происходило).
      // barrierDismissible: false заодно и правильнее с точки зрения UX —
      // подтверждение выхода не должно закрываться случайным тапом мимо.
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text("Выход"),
        content: Text("Вы уверены, что хотите выйти?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Отмена"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Выйти"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Вы вышли из аккаунта")),
      );
      await Future.delayed(Duration(milliseconds: 300));

      await AuthService.logout();

      if (!context.mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/auth',
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        elevation: 0,
        title: const Text(
          'Centr-krasok',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined, color: Colors.white),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildActiveCustomerCard(),
            const SizedBox(height: 20),

            // Анкета лида — зелёная
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _openNewCustomer,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text(
                  'Анкета лида',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Существующий клиент — белая без бордера
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _openSearchCustomer,
                icon: const Icon(Icons.search),
                label: const Text(
                  'Существующий клиент',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCustomerCard() {
    if (_loadingCustomer) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_activeCustomer == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'Клиент не выбран',
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
      );
    }

    final customer = _activeCustomer!;
    final subtitle = customer.isCompany
        ? customer.bin
        : '${customer.phone} · ${customer.type.label}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE8F5E9),
            child: Icon(
              customer.isCompany ? Icons.business_outlined : Icons.person,
              color: const Color(0xFF4CAF50),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.isCompany ? 'Текущая компания' : 'Текущий клиент',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                Text(
                  customer.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
