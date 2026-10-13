import 'package:flutter/material.dart';
import 'package:centrkrasok/router/router.dart';
import 'package:centrkrasok/theme/theme.dart';
import 'package:centrkrasok/repositories/products/local_db.dart';
import 'package:centrkrasok/catalog/compare/compare_store.dart';
import 'package:centrkrasok/customer/bad_lead_queue.dart';
import 'package:centrkrasok/cart/cart_local_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализируем локальную БД (офлайн-кэш каталога)
  await LocalDb.init();

  // Инициализируем хранилище сравнения
  await CompareStore.instance.init();

  // Примечание: SyncService (фоновая отправка офлайн-очереди корзин/заказов)
  // пока не подключаем — корзины в centrkrasok ещё нет.

  // Некачественные лиды, не доехавшие до Bitrix в прошлый запуск.
  BadLeadQueue.instance.restore();

  // Значок количества товаров у корзины в нижнем меню.
  CartBadge.refresh();

  runApp(MaterialApp(
    theme: darkTheme,
    initialRoute: '/',
    routes: routes,
  ));
}
