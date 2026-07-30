import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:centrkrasok/customer/models/customer_model.dart';
import 'package:centrkrasok/bitrix/bitrix_service.dart' show NoInternetException;

/// Сервис для собственных PHP-эндпоинтов prons.kz, отдельных от Bitrix24 CRM
/// (используется тот же хост и стиль, что и в ProductsRepository:
/// https://prons.kz/ajax/centrkrasok/...).
///
/// Компании (Highload-блок CompanyList, ID=30) физически живут на prons.kz,
/// а не в Bitrix24 — отсюда отдельный сервис от BitrixService.
const String _pronsBaseUrl = 'https://prons.kz/ajax/centrkrasok';

class PronsApiService {
  PronsApiService({required this.dio});

  final Dio dio;

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> _requireInternet() async {
    if (!await _hasInternet()) {
      throw NoInternetException();
    }
  }

  /// Поиск компаний по названию (короткому или полному) либо по БИН/ИИН.
  Future<List<CompanySearchResult>> searchCompanies({
    required String query,
    required bool byBin,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.get(
        '$_pronsBaseUrl/search_companies.php',
        queryParameters: {
          'query': query,
          'type': byBin ? 'bin' : 'name',
        },
      );

      // Диагностика — уберём после того, как разберёмся с "0 результатов".
      debugPrint('searchCompanies: запрошенный URL: ${response.requestOptions.uri}');
      debugPrint('searchCompanies: тип ответа: ${response.data.runtimeType}');
      debugPrint('searchCompanies: сырой ответ: ${response.data}');

      dynamic data = response.data;

      // Если сервер не указал верный Content-Type, Dio может вернуть JSON
      // как обычную строку вместо распарсенной Map — разбираем сами.
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (e) {
          debugPrint('searchCompanies: не удалось распарсить строку как JSON: $e');
          return [];
        }
      }

      if (data is! Map<String, dynamic>) {
        debugPrint('searchCompanies: неожиданный тип ответа после разбора: ${data.runtimeType}');
        return [];
      }

      final result = data['result'] as List<dynamic>? ?? [];
      debugPrint('searchCompanies: найдено элементов: ${result.length}');

      return result.map((e) {
        final item = e as Map<String, dynamic>;
        return CompanySearchResult(
          companyId: item['id'].toString(),
          name: item['name']?.toString().trim() ?? '',
          fullName: item['fullName']?.toString().trim() ?? '',
          bin: item['bin']?.toString().trim() ?? '',
          phone: item['phone']?.toString().trim() ?? '',
          email: item['email']?.toString().trim() ?? '',
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('searchCompanies: ошибка сети: ${e.message}, ответ: ${e.response?.data}');
      rethrow;
    }
  }
}
