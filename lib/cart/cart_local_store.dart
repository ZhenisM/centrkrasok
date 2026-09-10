import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:centrkrasok/cart/models/cart_model.dart';

/// Локальное зеркало корзин-заказов в sqflite.
///
/// В отличие от offlinesvet, "текущая корзина" (is_current) — это ЧИСТО
/// локальное UI-состояние: сервер (cart_load.php/cart_save.php) для
/// centrkrasok вообще не хранит такого флага (корзина здесь — заказ, а не
/// строка HL-блока), поэтому is_current никогда никуда не отправляется,
/// только читается/пишется в этой локальной таблице.
class CartLocalStore {
  static const _dbName = 'carts_local_ck.db';
  static const _table  = 'carts';
  static Database? _db;

  static Future<Database> _open() async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), _dbName),
      version: 3,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_table (
          id            TEXT PRIMARY KEY,
          title         TEXT NOT NULL,
          status        TEXT NOT NULL DEFAULT "в работе",
          is_current    INTEGER NOT NULL DEFAULT 0,
          date_create   TEXT NOT NULL,
          client_info   TEXT,
          coupons_json  TEXT NOT NULL DEFAULT "[]",
          items_json    TEXT NOT NULL DEFAULT "[]"
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Старая колонка "coupon" (один купон) — версии 3 больше не
          // читает/пишет её, но ALTER TABLE ... DROP COLUMN в sqlite не
          // всегда доступен, поэтому просто оставляем как мёртвый столбец.
          await db.execute('ALTER TABLE $_table ADD COLUMN coupon TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE $_table ADD COLUMN coupons_json TEXT NOT NULL DEFAULT "[]"');
        }
      },
    );
    return _db!;
  }

  /// Сохраняет список корзин с сервера, СОХРАНЯЯ существующий локальный
  /// is_current для тех ID, что уже были в базе (сервер этого флага не
  /// присылает). Корзины, которых больше нет на сервере (оформлены/удалены
  /// другим устройством), из локальной базы убираются.
  static Future<void> saveAll(List<Cart> carts) async {
    final db = await _open();
    final existingCurrentIds = <String>{};
    final existingRows = await db.query(_table, where: 'is_current = 1');
    for (final row in existingRows) {
      existingCurrentIds.add(row['id'] as String);
    }

    await db.transaction((txn) async {
      await txn.delete(_table);
      for (final cart in carts) {
        final map = _toMap(cart);
        map['is_current'] = existingCurrentIds.contains(cart.id) ? 1 : 0;
        await txn.insert(_table, map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    // Если после синхронизации ни одна корзина не помечена текущей
    // (например, первая загрузка, либо ранее текущая пропала) —
    // делаем текущей самую свежую.
    final anyCurrent = await db.query(_table, where: 'is_current = 1', limit: 1);
    if (anyCurrent.isEmpty && carts.isNotEmpty) {
      await setCurrent(carts.first.id);
    }
  }

  static Future<List<Cart>> loadAll() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'is_current DESC, date_create DESC');
    return rows.map(_fromMap).toList();
  }

  static Future<Cart?> loadCurrent() async {
    final db = await _open();
    final rows = await db.query(_table, where: 'is_current = 1', limit: 1);
    if (rows.isEmpty) return null;
    return _fromMap(rows.first);
  }

  /// Переключить текущую корзину (только локально).
  static Future<void> setCurrent(String basketId) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.update(_table, {'is_current': 0});
      await txn.update(_table, {'is_current': 1}, where: 'id = ?', whereArgs: [basketId]);
    });
  }

  /// Добавить/обновить одну корзину локально (например сразу после
  /// createCart(), не дожидаясь следующего loadCarts()).
  static Future<void> upsertCart(Cart cart, {bool makeCurrent = false}) async {
    final db = await _open();
    if (makeCurrent) {
      await db.update(_table, {'is_current': 0});
    }
    final map = _toMap(cart);
    if (makeCurrent) map['is_current'] = 1;
    await db.insert(_table, map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Обновить состав товаров локально (сразу после успешного
  /// updateCartItems() на сервере — чтобы не ждать перезагрузки).
  static Future<void> updateItems(String basketId, List<CartItem> items) async {
    final db = await _open();
    await db.update(_table, {'items_json': encodeCartItems(items)},
        where: 'id = ?', whereArgs: [basketId]);
  }

  /// Обновить список купонов локально (сразу после успешного применения на
  /// сервере — чтобы не ждать перезагрузки списка корзин).
  static Future<void> updateCoupons(String basketId, List<String> coupons) async {
    final db = await _open();
    await db.update(_table, {'coupons_json': jsonEncode(coupons)},
        where: 'id = ?', whereArgs: [basketId]);
  }

  static Future<void> removeCart(String basketId) async {
    final db = await _open();
    await db.delete(_table, where: 'id = ?', whereArgs: [basketId]);
  }

  static Map<String, dynamic> _toMap(Cart cart) => {
        'id':           cart.id,
        'title':        cart.title,
        'status':       cart.status.label,
        'is_current':   0,
        'date_create':  cart.dateCreate.toIso8601String(),
        'client_info':  cart.clientInfo != null ? jsonEncode(cart.clientInfo) : null,
        'coupons_json': jsonEncode(cart.coupons),
        'items_json':   encodeCartItems(cart.items),
      };

  static Cart _fromMap(Map<String, dynamic> m) => Cart(
        id: m['id'] as String,
        title: m['title'] as String,
        status: CartStatus.fromLabel(m['status'] as String? ?? 'в работе'),
        dateCreate: DateTime.tryParse(m['date_create'] as String? ?? '') ?? DateTime.now(),
        clientInfo: m['client_info'] != null
            ? (jsonDecode(m['client_info'] as String) as Map<String, dynamic>)
            : null,
        coupons: _decodeCoupons(m['coupons_json'] as String? ?? '[]'),
        items: _decodeItems(m['items_json'] as String? ?? '[]'),
      );

  static List<String> _decodeCoupons(String raw) {
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  static List<CartItem> _decodeItems(String raw) {
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => CartItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}
