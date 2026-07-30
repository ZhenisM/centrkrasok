import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:centrkrasok/customer/models/customer_model.dart';

/// Хранит список клиентов, с которыми работал менеджер, и текущего
/// активного клиента — по аналогии с мультикорзиной (HL-блок Multibaskets
/// на prons.kz, поле UF_MULTIBASKETS_MANAGER_ID): один менеджер -> много
/// клиентов, у каждого своя "корзина" (пока без товаров).
///
/// Список привязывается к user_id менеджера (numeric ID из Bitrix,
/// возвращается login.php/check.php) — он стабилен между сессиями,
/// в отличие от auth_token, который перевыпускается при каждом логине.
class CustomerStorage {
  static const _userIdKey = 'user_id';
  static String _customersKey(String userId) => 'customers_$userId';
  static String _activeIdKey(String userId) => 'active_customer_id_$userId';

  static Future<String?> _currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  /// Публичный доступ к user_id менеджера как числу — нужен для вызовов
  /// CartApiService (manager_id обязателен при создании/переключении корзин).
  /// Возвращает null, если пользователь не залогинен или user_id не сохранён.
  static Future<int?> currentManagerId() async {
    final raw = await _currentUserId();
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  /// Список всех клиентов, выбранных/созданных текущим менеджером.
  static Future<List<Customer>> loadAll() async {
    final userId = await _currentUserId();
    if (userId == null) return [];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customersKey(userId));
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Customer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('CustomerStorage.loadAll: ошибка парсинга: $e');
      return [];
    }
  }

  /// Текущий активный клиент (для которого собирается корзина), либо null.
  static Future<Customer?> loadActive() async {
    final userId = await _currentUserId();
    if (userId == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final activeKey = prefs.getString(_activeIdKey(userId));
    if (activeKey == null) return null;

    final all = await loadAll();
    for (final c in all) {
      if (c.storageKey == activeKey) return c;
    }
    return null;
  }

  /// Добавляет/обновляет клиента в списке менеджера и делает его активным.
  /// Используется как при создании нового контакта+лида, так и при выборе
  /// уже существующего контакта/компании — в обоих случаях он становится текущим.
  static Future<void> setActive(Customer customer) async {
    final userId = await _currentUserId();
    if (userId == null) {
      debugPrint('CustomerStorage.setActive: нет user_id, отмена');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();

    final idx = all.indexWhere((c) => c.storageKey == customer.storageKey);
    if (idx >= 0) {
      all[idx] = customer;
    } else {
      all.add(customer);
    }

    final encoded = jsonEncode(all.map((c) => c.toJson()).toList());
    await prefs.setString(_customersKey(userId), encoded);
    await prefs.setString(_activeIdKey(userId), customer.storageKey);
  }

  /// Очищает список клиентов текущего менеджера (например, при логауте).
  static Future<void> clearAll() async {
    final userId = await _currentUserId();
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customersKey(userId));
    await prefs.remove(_activeIdKey(userId));
  }
}
