import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';
import 'package:centrkrasok/repositories/products/models/section.dart';

class LocalDb {
  static Database? _db;

  // Инициализация БД — вызывать один раз в main()
  static Future<void> init() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'centrkrasok.db');

    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            parent_id TEXT,
            image TEXT,
            children_json TEXT NOT NULL,
            saved_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            brend TEXT,
            article TEXT,
            section_id TEXT NOT NULL,
            image TEXT,
            prices_json TEXT NOT NULL,
            props_json TEXT NOT NULL,
            search_text TEXT,
            saved_at INTEGER NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_products_section ON products(section_id)',
        );
        await db.execute(
          'CREATE INDEX idx_products_search ON products(search_text)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Добавляем поле для офлайн-поиска. Оно хранит уже приведённый
          // к нижнему регистру текст (регистр приводим в Dart — toLowerCase()
          // корректно работает с кириллицей, а встроенный LIKE в SQLite
          // по умолчанию складывает регистр только для ASCII).
          await db.execute('ALTER TABLE products ADD COLUMN search_text TEXT');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_products_search ON products(search_text)',
          );

          // Заполняем search_text для товаров, уже сохранённых до этого
          // обновления (иначе они не найдутся поиском, пока их не
          // пересохранят при следующей синхронизации).
          final rows = await db.query('products', columns: ['id', 'name', 'brend', 'article']);
          final batch = db.batch();
          for (final row in rows) {
            final text = [row['name'], row['brend'], row['article']]
                .where((e) => e != null && e.toString().isNotEmpty)
                .map((e) => e.toString().toLowerCase())
                .join(' ');
            batch.update('products', {'search_text': text},
                where: 'id = ?', whereArgs: [row['id']]);
          }
          await batch.commit(noResult: true);
        }

        if (oldVersion < 3) {
          // Картинка раздела — подтягивается из Bitrix (PICTURE секции).
          // У уже закэшированных ранее разделов её просто не будет, пока
          // не пройдёт следующая обычная загрузка списка разделов
          // (getSections()) — это не критично, разделы и так продолжат
          // отображаться, просто временно без картинки слева.
          await db.execute('ALTER TABLE sections ADD COLUMN image TEXT');
        }
      },
    );

    debugPrint('LocalDb: инициализирована');
  }

  static Database get _database {
    if (_db == null) throw StateError('LocalDb не инициализирован. Вызови LocalDb.init()');
    return _db!;
  }

  // -------------------------------------------------------
  // Секции
  // -------------------------------------------------------

  static Future<void> saveSections(List<Section> sections) async {
    final batch = _database.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    void insertSection(Section s) {
      batch.insert(
        'sections',
        {
          'id': s.id,
          'name': s.name,
          'parent_id': s.parentId,
          'image': s.image,
          'children_json': jsonEncode(s.children.map(_sectionToMap).toList()),
          'saved_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Рекурсивно сохраняем дочерние
      for (final child in s.children) {
        insertSection(child);
      }
    }

    for (final s in sections) {
      insertSection(s);
    }

    await batch.commit(noResult: true);
    debugPrint('LocalDb: сохранено ${sections.length} корневых разделов');
  }

  static Future<List<Section>> loadSections() async {
    final rows = await _database.query('sections');
    if (rows.isEmpty) return [];

    // Строим карту всех секций
    final map = <String, Section>{};
    for (final row in rows) {
      map[row['id'] as String] = Section(
        id: row['id'] as String,
        name: row['name'] as String,
        parentId: row['parent_id'] as String?,
        image: row['image'] as String?,
        children: [], // заполним ниже
      );
    }

    // Строим дерево
    final roots = <Section>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final parentId = row['parent_id'] as String?;
      final section = map[id]!;

      if (parentId == null || parentId.isEmpty || !map.containsKey(parentId)) {
        roots.add(section);
      } else {
        (map[parentId]!.children as List).add(section);
      }
    }

    debugPrint('LocalDb: загружено ${roots.length} корневых разделов из кэша');
    return roots;
  }

  static Future<bool> hasSections() async {
    final result = await _database.rawQuery('SELECT COUNT(*) as cnt FROM sections');
    return (result.first['cnt'] as int) > 0;
  }

  // -------------------------------------------------------
  // Товары
  // -------------------------------------------------------

  static Future<void> saveProducts(List<Product> products, {int? savedAt}) async {
    final batch = _database.batch();
    final now = savedAt ?? DateTime.now().millisecondsSinceEpoch;

    for (final p in products) {
      final searchText = [p.name, p.brend, p.article]
          .where((e) => e != null && e.isNotEmpty)
          .map((e) => e!.toLowerCase())
          .join(' ');

      batch.insert(
        'products',
        {
          'id': p.id,
          'name': p.name,
          'brend': p.brend,
          'article': p.article,
          'section_id': p.sectionId,
          'image': p.image,
          'prices_json': jsonEncode(p.prices.map((price) => {
            'type_id': price.typeId,
            'type_name': price.typeName,
            'price': price.price,
            'currency': price.currency,
          }).toList()),
          'props_json': jsonEncode(p.props.map((code, prop) => MapEntry(code, {
            'NAME': prop.name,
            'CODE': prop.code,
            'VALUE': prop.value,
          }))),
          'search_text': searchText,
          'saved_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // Офлайн-поиск по названию/бренду/артикулу — используется в
  // search_screen.dart как фолбэк, когда search_products.php недоступен.
  // Ищем по предвычисленному search_text (уже в нижнем регистре), а не
  // через `LIKE ... COLLATE NOCASE` — тот не складывает регистр кириллицы.
  static Future<List<Product>> searchProducts(String query, {int limit = 30}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final rows = await _database.query(
      'products',
      where: 'search_text LIKE ?',
      whereArgs: ['%$q%'],
      limit: limit,
    );
    return rows.map(_productFromRow).toList();
  }

  // Удаляет товары, не подтверждённые последним ПОЛНЫМ обходом каталога
  // (т.е. сняты с продажи / больше не ACTIVE в Bitrix) — иначе такие
  // товары остались бы в офлайн-кэше навсегда. Вызывать только после
  // того, как полный обход прошёл успешно от первой до последней страницы —
  // если прервать синхронизацию на середине и вызвать это, можно случайно
  // удалить ещё вполне активные товары, до которых просто не успели дойти.
  static Future<int> deleteStaleProducts({required int before}) async {
    return _database.delete(
      'products',
      where: 'saved_at < ?',
      whereArgs: [before],
    );
  }

  // ВАЖНО: раньше этот метод не имел ограничения по количеству строк —
  // для маленьких разделов (сотня-другая товаров, пока кэш наполнялся
  // только вручную просмотренными страницами) это было не страшно. После
  // полной синхронизации каталога в некоторых разделах (например,
  // "Люстры") оказались ТЫСЯЧИ товаров, и попытка вытащить их все одним
  // запросом роняла приложение с OutOfMemoryError прямо на границе
  // Flutter <-> Android (слишком большой единоразовый пакет данных).
  // Теперь поддерживает limit/offset — вызывающий код сам решает, сколько
  // грузить за раз.
  static Future<List<Product>> loadProductsBySection(
    String sectionId, {
    int? limit,
    int? offset,
  }) async {
    final rows = await _database.query(
      'products',
      where: 'section_id = ?',
      whereArgs: [sectionId],
      orderBy: 'id ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_productFromRow).toList();
  }

  // Товары сразу из НЕСКОЛЬКИХ разделов (раздел + все подразделы) одним
  // SQL-запросом с limit/offset — используется вместо того, чтобы делать
  // Future.wait по каждому разделу отдельно и потом склеивать в Dart:
  // так СУБД сама уже отдаёт нужную порцию, а не всё целиком.
  static Future<List<Product>> loadProductsForSections(
    List<String> sectionIds, {
    int? limit,
    int? offset,
  }) async {
    if (sectionIds.isEmpty) return [];
    final placeholders = List.filled(sectionIds.length, '?').join(',');
    final rows = await _database.query(
      'products',
      where: 'section_id IN ($placeholders)',
      whereArgs: sectionIds,
      orderBy: 'id ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_productFromRow).toList();
  }

  // Для случаев, когда реально нужны ВСЕ товары раздела целиком (построение
  // фильтров, офлайн-фильтрация) — читаем порциями по [batchSize], а не
  // одним огромным запросом, чтобы не повторить тот же OutOfMemoryError.
  static Future<List<Product>> loadAllProductsForSectionsBatched(
    List<String> sectionIds, {
    int batchSize = 500,
  }) async {
    final all = <Product>[];
    int offset = 0;
    while (true) {
      final batch = await loadProductsForSections(sectionIds, limit: batchSize, offset: offset);
      all.addAll(batch);
      if (batch.length < batchSize) break;
      offset += batchSize;
    }
    return all;
  }

  // Товары по списку ID — используется как офлайн-фолбэк для корзины:
  // товар мог попасть в общий кэш каталога при обычном просмотре разделов,
  // даже если он ни разу не показывался именно на экране корзины.
  static Future<List<Product>> loadProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _database.query(
      'products',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return rows.map(_productFromRow).toList();
  }

  static Future<int> countProducts() async {
    final result = await _database.rawQuery('SELECT COUNT(*) as cnt FROM products');
    return result.first['cnt'] as int;
  }

  // -------------------------------------------------------
  // Конвертация
  // -------------------------------------------------------

  static Map<String, dynamic> _sectionToMap(Section s) => {
    'ID': s.id,
    'NAME': s.name,
    'PARENT_ID': s.parentId,
    'IMAGE': s.image,
    'CHILDREN': s.children.map(_sectionToMap).toList(),
  };

  static Product _productFromRow(Map<String, dynamic> row) {
    final pricesList = (jsonDecode(row['prices_json'] as String) as List<dynamic>)
        .map((e) => Price.fromJson(e as Map<String, dynamic>))
        .toList();

    final propsMap = <String, Prop>{};
    (jsonDecode(row['props_json'] as String) as Map<String, dynamic>)
        .forEach((code, value) {
      if (value is Map<String, dynamic>) {
        propsMap[code] = Prop.fromJson(value);
      }
    });

    return Product(
      id: row['id'] as String,
      name: row['name'] as String,
      brend: row['brend'] as String?,
      article: row['article'] as String?,
      sectionId: row['section_id'] as String,
      image: row['image'] as String?,
      prices: pricesList,
      props: propsMap,
    );
  }
}
