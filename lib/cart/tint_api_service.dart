import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Один найденный цвет — из ответа tint_search.php?action=search.
class TintColor {
  final String color; // "#RRGGBB"
  final String name; // код/название цвета, например "DX 30YY 63/231"
  final String series;
  final String palette; // человекочитаемое название палитры

  const TintColor({
    required this.color,
    required this.name,
    this.series = '',
    required this.palette,
  });

  factory TintColor.fromJson(Map<String, dynamic> json) => TintColor(
        color: json['color']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        series: json['series']?.toString() ?? '',
        palette: json['palette']?.toString() ?? '',
      );
}

/// Одна палитра — из ответа tint_search.php?action=palettes.
class TintPalette {
  final String code;
  final String name;

  const TintPalette({required this.code, required this.name});

  factory TintPalette.fromJson(Map<String, dynamic> json) => TintPalette(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

class TintApiException implements Exception {
  final String message;
  TintApiException(this.message);
  @override
  String toString() => message;
}

/// Сервис для tint_search.php — поиск цвета и список палитр колеровки.
///
/// Сайт s6 закрыт для неавторизованных на уровне eventhandlers.php
/// (проверка срабатывает ещё внутри prolog_before.php, до того как
/// выполняется хоть строчка кода самого tint_search.php) — обойти это
/// изнутри скрипта не получилось (Bitrix явно блокирует ручной
/// session_start() до своего ядра). Рабочий путь — как обычный браузер:
/// один раз авторизоваться (tint_login.php, штатно, уже после старта
/// ядра) и слать полученный PHPSESSID как обычную cookie на все
/// последующие запросы. Сессия кэшируется на уровне класса (на всё время
/// работы приложения) и при первой же неудаче считается протухшей —
/// тогда логинимся заново один раз и повторяем запрос.
class TintApiService {
  TintApiService({required this.dio});
  final Dio dio;

  static const String _baseUrl = 'https://prons.kz/ajax/centrkrasok';
  static String? _phpSessionId;

  Future<void> _login(int managerId) async {
    try {
      final response = await dio.get(
        '$_baseUrl/tint_login.php',
        queryParameters: {'manager_id': managerId.toString()},
      );
      final data = _ensureMap(response.data);
      if (data['error'] != null) {
        throw TintApiException(data['error'].toString());
      }
      final result = data['result'] as Map<String, dynamic>?;
      final sessionId = result?['session_id']?.toString();
      if (sessionId == null || sessionId.isEmpty) {
        throw TintApiException('Сервер не вернул session_id при авторизации');
      }
      _phpSessionId = sessionId;
    } on DioException catch (e) {
      debugPrint('tint_login: ошибка сети: ${e.message}, ответ сервера: ${e.response?.data}');
      throw TintApiException('Не удалось авторизоваться для колеровки: ${e.message}');
    }
  }

  Options _cookieOptions() => Options(
        headers: {
          if (_phpSessionId != null) 'Cookie': 'PHPSESSID=$_phpSessionId',
        },
      );

  /// Выполняет запрос к tint_search.php; если сессии ещё нет — сначала
  /// логинится; если запрос всё равно не удался (сессия протухла) —
  /// логинится заново один раз и повторяет.
  Future<Map<String, dynamic>> _callSearchEndpoint(
    int managerId,
    Map<String, String> queryParameters,
  ) async {
    if (_phpSessionId == null) {
      await _login(managerId);
    }

    Future<Map<String, dynamic>> attempt() async {
      final response = await dio.get(
        '$_baseUrl/tint_search.php',
        queryParameters: queryParameters,
        options: _cookieOptions(),
      );
      return _ensureMap(response.data);
    }

    try {
      final data = await attempt();
      if (data['error'] != null) {
        throw TintApiException(data['error'].toString());
      }
      return data;
    } catch (e) {
      // Сессия могла протухнуть (или это была первая попытка без сессии
      // вообще) — логинимся заново один раз и пробуем снова.
      debugPrint('tint_search: первая попытка не удалась ($e), пробую перелогиниться');
      await _login(managerId);
      final data = await attempt();
      if (data['error'] != null) {
        throw TintApiException(data['error'].toString());
      }
      return data;
    }
  }

  Future<List<TintPalette>> loadPalettes({required int managerId}) async {
    final data = await _callSearchEndpoint(managerId, {
      'action': 'palettes',
      'manager_id': managerId.toString(),
    });
    final result = data['result'] as List<dynamic>? ?? [];
    return result.map((e) => TintPalette.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<TintColor>> search({
    required int managerId,
    required String q,
    String paletteCode = 'all',
  }) async {
    final data = await _callSearchEndpoint(managerId, {
      'action': 'search',
      'manager_id': managerId.toString(),
      'q': q,
      'paletteCode': paletteCode,
    });
    final result = data['result'] as List<dynamic>? ?? [];
    return result.map((e) => TintColor.fromJson(e as Map<String, dynamic>)).toList();
  }

  Map<String, dynamic> _ensureMap(dynamic data) {
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    if (data is Map<String, dynamic>) return data;
    debugPrint('TintApiService: неожиданный формат ответа (${data.runtimeType}): $data');
    throw TintApiException('Некорректный формат ответа сервера');
  }
}
