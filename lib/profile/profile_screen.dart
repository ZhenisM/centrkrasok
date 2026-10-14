import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:centrkrasok/auth/auth_service.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:centrkrasok/customer/customer.dart';
import 'package:centrkrasok/customer/customer_storage.dart';
import 'package:centrkrasok/cart/cart_local_store.dart';
import 'package:centrkrasok/cart/view/tint_list_screen.dart';
import 'package:centrkrasok/profile/calculator_screen.dart';
import 'package:centrkrasok/profile/client_cabinet_screen.dart';
import 'package:centrkrasok/profile/manager_stats_screen.dart';

/// Профиль — как боковое меню сайта offline.centr-krasok.kz:
/// менеджер, «Мои успехи», текущий клиент, «Кабинет клиента», «Мои
/// колеровки», «Калькулятор», каталог, выход. («Кофейня» и «Склад» —
/// позже.)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _managerName = '';
  /// Клиент ТЕКУЩЕЙ корзины — тот же, что в «Кабинете клиента»
  /// (раньше брался отдельно сохранённый «активный» клиент, который не
  /// менялся при переключении корзины).
  String? _currentClientName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? '';
    final customer = await CustomerStorage.loadActive();
    final cart = await CartLocalStore.loadCurrent();
    final info = cart?.clientInfo;
    String? clientName;
    if (info != null) {
      clientName = (info['ENTITY'] == 'COMPANY' ? info['TITLE'] : info['NAME'])?.toString();
    }
    clientName ??= cart?.title;
    if (!mounted) return;
    setState(() {
      _managerName = name;
      _currentClientName = (clientName != null && clientName.trim().isNotEmpty) ? clientName : customer?.name;
    });
  }

  /// Кабинет клиента — для клиента текущей корзины (как на сайте —
  /// для текущего клиента).
  Future<void> _openClientCabinet() async {
    final cart = await CartLocalStore.loadCurrent();
    if (!mounted) return;
    if (cart == null || cart.clientInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Нет клиента — выберите его через «Анкету лида» или «Существующий клиент»')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientCabinetScreen(basketId: cart.id)));
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Профиль', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Менеджер', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              Text(_managerName.isEmpty ? '—' : _managerName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              if (_currentClientName != null) ...[
                const SizedBox(height: 16),
                Text('Текущий клиент', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Text(_currentClientName!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              _MenuItem(
                icon: Icons.emoji_events_outlined,
                label: 'Мои успехи',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManagerStatsScreen())),
              ),
              const Divider(height: 1, indent: 56),
              _MenuItem(
                icon: Icons.badge_outlined,
                label: 'Кабинет клиента',
                onTap: () async { await _openClientCabinet(); _load(); },
              ),
              const Divider(height: 1, indent: 56),
              _MenuItem(
                icon: Icons.water_drop_outlined,
                label: 'Мои колеровки',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TintListScreen())),
              ),
              const Divider(height: 1, indent: 56),
              _MenuItem(
                icon: Icons.calculate_outlined,
                label: 'Калькулятор',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CalculatorScreen())),
              ),
              const Divider(height: 1, indent: 56),
              _MenuItem(
                svgAsset: 'assets/icons/shop.svg',
                label: 'Каталог',
                onTap: () => Navigator.of(context).pushNamed('/products-list'),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('Выйти из аккаунта'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.profile),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({this.svgAsset, this.icon, required this.label, required this.onTap});
  final String? svgAsset;
  final IconData? icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          if (svgAsset != null)
            SvgPicture.asset(svgAsset!, width: 24, height: 24,
                colorFilter: const ColorFilter.mode(Color(0xFF4CAF50), BlendMode.srcIn))
          else
            Icon(icon, size: 24, color: const Color(0xFF4CAF50)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
        ]),
      ),
    );
  }
}
