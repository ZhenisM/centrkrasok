import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Документ для печати из корзины — те же 4 пункта, что на сайте
/// offline.centr-krasok.kz (кнопка «Распечатать» в корзине).
enum PrintDoc {
  purchase('purchase', null, 'Договор купли-продажи'),
  annex('annex', null, 'Приложение к договору'),
  tintKz('tint', 'kz', 'Согласие на колеровку (каз)'),
  tintRu('tint', 'ru', 'Согласие на колеровку (рус)');

  const PrintDoc(this.code, this.lang, this.label);
  final String code;
  final String? lang;
  final String label;
}

class PrintApiException implements Exception {
  final String message;
  final bool needsRelogin;
  PrintApiException(this.message, {this.needsRelogin = false});
  @override
  String toString() => message;
}

/// Печать документов корзины: сервер проверяет токен и владельца корзины
/// и возвращает одноразовую подписанную ссылку на PDF (10 минут). Токен в
/// ссылку не попадает, поэтому её безопасно открыть в браузере/просмотрщике.
class PrintApiService {
  PrintApiService({required this.dio});
  final Dio dio;

  static const _url = 'https://prons.kz/ajax/centrkrasok/print_basket_link.php';

  /// city: 'almaty' | 'astana'. Возвращает URL готового PDF.
  Future<String> getDocumentUrl({
    required String basketId,
    required PrintDoc doc,
    required String city,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    if (token.isEmpty) {
      throw PrintApiException('Сессия истекла, войдите заново', needsRelogin: true);
    }

    try {
      final response = await dio.post(
        _url,
        data: FormData.fromMap({
          'token': token,
          'basket_id': basketId,
          'doc': doc.code,
          'city': city,
          'lang': doc.lang ?? 'ru',
        }),
        options: Options(
          // plain + ручной разбор: если сервер вернёт не-JSON, увидим текст,
          // а не молчаливое «не удалось».
          responseType: ResponseType.plain,
          // Любой ответ разбираем сами — в 4xx/5xx сервер присылает
          // понятное сообщение (а в 5xx — ещё и техническую причину).
          validateStatus: (s) => s != null,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      dynamic data = response.data;
      if (data is String) {
        try { data = jsonDecode(data); } catch (_) {}
      }
      if (data is Map && data['result'] is Map && data['result']['url'] is String) {
        return data['result']['url'] as String;
      }
      if (data is Map && data['error'] != null) {
        final debug = data['debug']?.toString();
        if (debug != null) debugPrint('print_basket_link: ${response.statusCode} $debug');
        throw PrintApiException(
          debug != null ? '${data['error']}\n$debug' : data['error'].toString(),
          needsRelogin: response.statusCode == 401,
        );
      }
      // Не JSON — например, PHP вывел предупреждение или HTML-страницу.
      final raw = data?.toString() ?? '';
      debugPrint('print_basket_link: ${response.statusCode} не JSON: '
          '${raw.length > 500 ? raw.substring(0, 500) : raw}');
      throw PrintApiException('Сервер вернул неожиданный ответ (${response.statusCode})');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw PrintApiException('Нет подключения к интернету — печать работает только онлайн');
      }
      throw PrintApiException('Ошибка сервера при подготовке документа');
    }
  }
}
