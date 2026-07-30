import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';

/// Список свойств для отображения в сравнении.
/// Порядок важен — именно в таком порядке выводятся строки.
/// Подобрано для каталога красок (ID=87) на основе реальных кодов
/// свойств из админки — при необходимости список легко расширить.
const kCompareProps = [
  ('Цена',      '__price__'),   // специальный ключ — берём из prices
  ('Бренд',     '__brend__'),   // из product.brend
  ('Артикул',   '__article__'), // из product.article
  ('Сегмент',           'SEGMENT'),
  ('Тип покрытия',      'TIP_POKRYTIYA'),
  ('Цвет',              'TSVET'),
  ('Объём тары',        'OBYOM_TARY'),
  ('База',              'baza'),
  ('Фасовка',           'FASOVKA'),
  ('Расход упаковки',   'RASHOD_UPAK'),
  ('Скорость высыхания','VYSYHANIYE'),
  ('Степень блеска',    'STEPEN_BLESKA'),
  ('Назначение',        'NAZNACHENIYE'),
];

/// Глобальное состояние сравнения
class CompareState {
  CompareState._();
  static final CompareState instance = CompareState._();

  final Set<int> _ids = {};

  bool isCompared(int productId) => _ids.contains(productId);

  void _setIds(List<int> ids) {
    _ids..clear()..addAll(ids);
    _notifyListeners();
  }

  void _toggle(int productId, bool inCompare) {
    if (inCompare) { _ids.add(productId); } else { _ids.remove(productId); }
    _notifyListeners();
  }

  final List<void Function()> _listeners = [];
  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void _notifyListeners() { for (final l in _listeners) l(); }
}

/// Локальное хранилище сравнения на sqflite
class CompareStore {
  static CompareStore? _instance;
  static Database? _db;

  CompareStore._();
  static CompareStore get instance => _instance ??= CompareStore._();

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'compare.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, _) {
      db.execute('''
        CREATE TABLE compare_items (
          product_id INTEGER PRIMARY KEY,
          product_json TEXT NOT NULL,
          added_at INTEGER NOT NULL
        )
      ''');
    });
    return _db!;
  }

  Future<void> init() async {
    final items = await getAll();
    CompareState.instance._setIds(items.map((p) => int.tryParse(p.id) ?? 0).toList());
  }

  Future<void> toggle(Product product) async {
    final productId = int.tryParse(product.id) ?? 0;
    final db = await _database;
    final exists = (await db.query('compare_items',
        where: 'product_id = ?', whereArgs: [productId], limit: 1)).isNotEmpty;

    if (exists) {
      await db.delete('compare_items', where: 'product_id = ?', whereArgs: [productId]);
      CompareState.instance._toggle(productId, false);
    } else {
      await db.insert('compare_items', {
        'product_id'   : productId,
        'product_json' : jsonEncode(_productToJson(product)),
        'added_at'     : DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      CompareState.instance._toggle(productId, true);
    }
  }

  Future<List<Product>> getAll() async {
    final db = await _database;
    final rows = await db.query('compare_items', orderBy: 'added_at ASC');
    return rows.map((r) {
      final json = jsonDecode(r['product_json'] as String) as Map<String, dynamic>;
      return Product.fromJson(json);
    }).toList();
  }

  Future<void> remove(int productId) async {
    final db = await _database;
    await db.delete('compare_items', where: 'product_id = ?', whereArgs: [productId]);
    CompareState.instance._toggle(productId, false);
  }

  Future<void> clear() async {
    final db = await _database;
    await db.delete('compare_items');
    CompareState.instance._setIds([]);
  }

  /// Получить значение свойства для отображения в сравнении
  static String getPropValue(Product p, String propKey) {
    switch (propKey) {
      case '__price__':
        if (p.prices.isEmpty) return '—';
        // Предпочитаем подтверждённую розничную группу (30 — "Розничная
        // ИСПОЛЬЗОВАТЬ"); если её нет у товара — берём минимальную из
        // того, что есть, как раньше.
        final retailPrices = p.prices.where((x) => x.typeId == '30').toList();
        final source = retailPrices.isNotEmpty ? retailPrices : p.prices;
        final price = source.map((x) => x.price).reduce((a, b) => a < b ? a : b);
        final formatted = price.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
        return '$formatted ₸';
      case '__brend__':
        return p.brend?.isNotEmpty == true ? p.brend! : '—';
      case '__article__':
        return p.article?.isNotEmpty == true ? p.article! : '—';
      default:
        final prop = p.props[propKey];
        return prop?.value.isNotEmpty == true ? prop!.value : '—';
    }
  }

  static Map<String, dynamic> _productToJson(Product p) => {
    'id'        : p.id,
    'name'      : p.name,
    'brend'     : p.brend,
    'article'   : p.article,
    'sectionId' : p.sectionId,
    'image'     : p.image,
    'prices'    : p.prices.map((pr) => {
      'type_id'  : pr.typeId,
      'type_name': pr.typeName,
      'price'    : pr.price,
      'currency' : pr.currency,
    }).toList(),
    'props'     : p.props.map((k, v) => MapEntry(k, {
      'NAME' : v.name,
      'CODE' : v.code,
      'VALUE': v.value,
    })),
  };
}
