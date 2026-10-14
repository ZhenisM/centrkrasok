import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:centrkrasok/auth/auth_service.dart';
import 'package:centrkrasok/customer/view/new_customer_dialog.dart';
import 'package:centrkrasok/customer/view/search_customer_screen.dart';
import 'package:centrkrasok/customer/view/bad_lead_dialog.dart';
import 'package:centrkrasok/customer/view/potential_project_screen.dart';
import 'package:centrkrasok/cart/cart_local_store.dart';
import 'package:centrkrasok/repositories/products/catalog_sync_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _loadingCustomer = true;

  @override
  void initState() {
    super.initState();
    _loadActiveCustomer();
    CartBadge.revision.addListener(_onCartsChanged);
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

  /// «Текущий клиент» — клиент ТЕКУЩЕЙ корзины (как в профиле и кабинете
  /// клиента); перечитывается при любой смене корзины.
  Map<String, dynamic>? _cartClient;

  @override
  void dispose() {
    CartBadge.revision.removeListener(_onCartsChanged);
    super.dispose();
  }

  Future<void> _loadActiveCustomer() async {
    final cart = await CartLocalStore.loadCurrent();
    if (!mounted) return;
    setState(() {
      _cartClient = cart?.clientInfo == null
          ? (cart == null ? null : {'NAME': cart.title})
          : Map<String, dynamic>.from(cart!.clientInfo!);
      _loadingCustomer = false;
    });
  }

  void _onCartsChanged() => _loadActiveCustomer();

  Future<void> _openNewCustomer() async {
    final result = await showNewCustomerDialog(context);
    if (result == true) {
      _loadActiveCustomer();
    } else if (result is String && mounted) {
      // Такой контакт уже есть — «Поиск клиента» с этим номером.
      final selected = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SearchCustomerScreen(mode: CustomerSearchMode.contact, initialPhone: result),
      ));
      if (selected == true) _loadActiveCustomer();
    }
  }

  Future<void> _openPotentialProject() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PotentialProjectScreen()));
  }

  Future<void> _openSearchCustomer() async {
    final selected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SearchCustomerScreen(mode: CustomerSearchMode.company)),
    );
    if (selected == true) {
      _loadActiveCustomer();
    }
  }

  Future<void> _openBadLead() async {
    await showBadLeadDialog(context);
  }

  void _openProfile() {
    // Каталог теперь открывается из профиля (как в offlinesvet).
    Navigator.of(context).pushNamed('/profile');
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
          'Центр Красок',
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
                  'Новый лид',
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

            // Поиск компании — белая без бордера (как на сайте «Поиск Компании»)
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _openSearchCustomer,
                icon: const Icon(Icons.business_outlined),
                label: const Text(
                  'Поиск компании',
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
            const SizedBox(height: 12),

            // Некачественный лид — красная, короткая анкета без сбора
            // контактных данных (клиент мог отказаться их предоставить).
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _openBadLead,
                icon: const Icon(Icons.thumb_down_outlined),
                label: const Text(
                  'Некачественный лид',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Потенциальный проект — форма Битрикс24, как на сайте
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _openPotentialProject,
                icon: const Icon(Icons.architecture_outlined),
                label: const Text(
                  'Потенциальный проект',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF26529A),
                  foregroundColor: Colors.white,
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
      // Профиль — красная кнопка с иконкой в правом нижнем углу, как в offlinesvet.
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFE53935),
        onPressed: _openProfile,
        child: SvgPicture.asset(
          'assets/icons/document.svg',
          width: 24, height: 24,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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

    final c = _cartClient;
    if (c == null) {
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

    final isCompany = c['ENTITY'] == 'COMPANY';
    final name = '${(isCompany ? c['TITLE'] : c['NAME']) ?? ''}';
    final subtitle = isCompany
        ? '${c['BIN'] ?? c['IIN'] ?? ''}'
        : [c['PHONE'], c['TYPE']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');

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
              isCompany ? Icons.business_outlined : Icons.person,
              color: const Color(0xFF4CAF50),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCompany ? 'Текущая компания' : 'Текущий клиент',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (subtitle.isNotEmpty)
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
