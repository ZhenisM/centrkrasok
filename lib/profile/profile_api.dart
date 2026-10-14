import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Запросы профиля менеджера (profile.php): «Мои успехи», текущий клиент,
/// кабинет клиента — те же данные, что боковое меню и страницы сайта.
class ProfileApi {
  static const _url = 'https://prons.kz/ajax/centrkrasok/profile.php';
  final _dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 40)));

  Future<Map<String, dynamic>> call(String action, [Map<String, String> params = const {}]) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    try {
      final r = await _dio.post(_url,
          data: FormData.fromMap({'token': token, 'action': action, ...params}),
          options: Options(responseType: ResponseType.plain, validateStatus: (s) => s != null));
      final data = jsonDecode(r.data as String);
      if (data is Map && data['result'] is Map) return Map<String, dynamic>.from(data['result'] as Map);
      throw Exception((data is Map ? data['error'] : null) ?? 'Неожиданный ответ сервера (${r.statusCode})');
    } on DioException {
      throw Exception('Нет подключения к интернету');
    }
  }
}

String fmtMoney(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}
