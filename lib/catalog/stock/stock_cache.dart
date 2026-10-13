import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Остатки товара для карточки каталога — как на карточке сайта:
/// «Остаток Алматы», «Остаток AND Алматы», «Остаток Астана»,
/// «Остаток AND Астана»; если нигде нет — «Только под заказ».
class StockAmounts {
  final double almaty, andAlmaty, astana, andAstana;
  const StockAmounts(this.almaty, this.andAlmaty, this.astana, this.andAstana);

  bool get isEmpty => almaty <= 0 && andAlmaty <= 0 && astana <= 0 && andAstana <= 0;

  /// Строки для карточки в порядке сайта.
  List<MapEntry<String, double>> get lines => [
        if (almaty > 0) MapEntry('Остаток Алматы', almaty),
        if (andAlmaty > 0) MapEntry('Остаток AND Алматы', andAlmaty),
        if (astana > 0) MapEntry('Остаток Астана', astana),
        if (andAstana > 0) MapEntry('Остаток AND Астана', andAstana),
      ];
}

/// Кэш остатков для карточек. Карточки сами просят свои ID, запросы
/// собираются в одну пачку (stores_amount.php) — один запрос на экран
/// товаров, а не на каждую карточку. Без интернета остатков просто нет —
/// карточка их не показывает.
class StockCache {
  StockCache._();

  static const _url = 'https://prons.kz/ajax/centrkrasok/stores_amount.php';
  static const _ttl = Duration(minutes: 5);

  static final _dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 20)));
  static final Map<String, StockAmounts> _data = {};
  static final Map<String, DateTime> _loadedAt = {};
  static final Set<String> _pending = {};
  static final Set<String> _inFlight = {};
  static Timer? _timer;

  /// Меняется после каждой загрузки — карточки перерисовываются.
  static final ValueNotifier<int> version = ValueNotifier(0);

  static StockAmounts? get(String id) => _data[id];

  /// Запросить остатки товара (пачкой с соседними карточками).
  static void request(String id) {
    final at = _loadedAt[id];
    if (at != null && DateTime.now().difference(at) < _ttl) return;
    if (_inFlight.contains(id)) return;
    _pending.add(id);
    _timer ??= Timer(const Duration(milliseconds: 80), _flush);
  }

  static Future<void> _flush() async {
    _timer = null;
    final ids = _pending.toList();
    _pending.clear();
    _inFlight.addAll(ids);
    try {
      for (var i = 0; i < ids.length; i += 200) {
        final chunk = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
        final r = await _dio.get(_url,
            queryParameters: {'ids': chunk.join(',')},
            options: Options(responseType: ResponseType.plain));
        final items = (jsonDecode(r.data as String) as Map<String, dynamic>)['items'] as Map<String, dynamic>? ?? {};
        final now = DateTime.now();
        items.forEach((id, v) {
          final m = v as Map<String, dynamic>;
          double n(String k) => (m[k] as num?)?.toDouble() ?? 0;
          _data[id] = StockAmounts(n('almaty'), n('and_almaty'), n('astana'), n('and_astana'));
          _loadedAt[id] = now;
        });
        version.value++;
      }
    } catch (e) {
      debugPrint('StockCache: $e');
    } finally {
      _inFlight.removeAll(ids);
    }
  }
}
