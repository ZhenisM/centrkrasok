import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:centrkrasok/auth/auth_service.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:centrkrasok/customer/customer.dart';
import 'package:centrkrasok/customer/customer_storage.dart';

/// Упрощённая версия профиля на этом этапе — кабинет клиента и
/// статистика менеджера пока не перенесены (см. обсуждение: они
/// завязаны на ID свойств заказа, которые для centrkrasok ещё нужно
/// сверить отдельно, чтобы не гадать вслепую).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _managerName = '';
  Customer? _activeCustomer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? '';
    final customer = await CustomerStorage.loadActive();
    if (!mounted) return;
    setState(() {
      _managerName = name;
      _activeCustomer = customer;
    });
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
              if (_activeCustomer != null) ...[
                const SizedBox(height: 16),
                Text('Текущий клиент', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Text(_activeCustomer!.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
          const SizedBox(height: 16),

          // Разделы (как в offlinesvet). Пока только каталог — "Мои успехи"
          // и "Кабинет клиента" для красок ещё не перенесены.
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: _MenuItem(
              svgAsset: 'assets/icons/shop.svg',
              label: 'Каталог',
              onTap: () => Navigator.of(context).pushNamed('/products-list'),
            ),
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
  const _MenuItem({required this.svgAsset, required this.label, required this.onTap});
  final String svgAsset;
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
          SvgPicture.asset(svgAsset, width: 24, height: 24,
              colorFilter: const ColorFilter.mode(Color(0xFF4CAF50), BlendMode.srcIn)),
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
