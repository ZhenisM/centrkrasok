import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:centrkrasok/customer/models/customer_model.dart';

/// Базовый URL входящего вебхука Bitrix24.
const String _bitrixWebhookUrl =
    'https://abis.bitrix24.kz/rest/21537/l7qiphejvc8khwx7';

/// ID enum-значений справочника UF_CRM_1544076714 ("Тип клиента (СВЕТ)")
const _typeFieldCode = 'UF_CRM_1544076714';

/// ID enum-значений справочника UF_CRM_1673861444
/// ("Источник клиента для САЛОНОВ Света 2026")
const _sourceFieldCode = 'UF_CRM_1673861444';

/// ID значения "Другое" — источник по умолчанию, если менеджер не указал.
const String defaultSourceId = '76585';

/// Полный список значений источника для UI (dropdown), id -> название.
const Map<String, String> leadSources = {
  '35313': 'Существующий клиент',
  '100519': '2ГИС',
  '35315': 'Витрина',
  '78677': 'Сертификат, полученный от партнера',
  '35319': 'По рекомендации',
  '78703': 'Instagram',
  '35321': 'По рекомендации партнера или дизайнера',
  '45343': 'Центр Красок #1',
  '78683': 'Таргетинг (реклама с Instagram)',
  '79745': 'Выставка',
  '79747': 'Контекстная реклама',
  '79749': 'Маркетплейс (Каспи/Халык)',
  '35323': 'Интернет-магазин svet.kz',
  '78013': 'Запрос на почту',
  '100695': 'Мастер-класс (мероприятие)',
  '76585': 'Другое',
};

/// Исключение — нет подключения к интернету. Отдельный тип, чтобы UI
/// мог показать именно "Нет интернета", а не общую ошибку сети.
class NoInternetException implements Exception {
  @override
  String toString() => 'Нет подключения к интернету';
}

/// Исключение — ошибка ответа Bitrix (например, неверный вебхук, нет прав).
class BitrixApiException implements Exception {
  final String message;
  BitrixApiException(this.message);

  @override
  String toString() => message;
}

class BitrixService {
  BitrixService({required this.dio});

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

  Map<String, dynamic> _unwrapResult(Response response) {
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw BitrixApiException('Некорректный ответ сервера Bitrix');
    }
    if (data['error'] != null) {
      final description = data['error_description'] ?? data['error'];
      throw BitrixApiException('Bitrix: $description');
    }
    return data;
  }

  // -------------------------------------------------------
  // Контакты
  // -------------------------------------------------------

  /// Поиск контактов по телефону.
  ///
  /// ВАЖНО: Bitrix не поддерживает LIKE/%-фильтр для мультиполей (PHONE,
  /// EMAIL и т.д.) — фильтрация по ним работает только на точное
  /// совпадение, а точная запись номера в CRM может отличаться форматом
  /// (+7 / 8 / пробелы / скобки). Поэтому ищем правильным способом:
  /// 1) crm.duplicate.findbycomm — он сам нормализует номер и возвращает
  ///    ID совпавших контактов;
  /// 2) crm.contact.list с фильтром по точному ID, чтобы получить карточки.
  Future<List<CustomerSearchResult>> searchContactsByPhone(
    String phone,
  ) async {
    await _requireInternet();

    try {
      final dupResponse = await dio.post(
        '$_bitrixWebhookUrl/crm.duplicate.findbycomm.json',
        data: {
          'type': 'PHONE',
          'values': [phone],
        },
      );

      final dupData = _unwrapResult(dupResponse);

      // Bitrix возвращает result как объект {"CONTACT":[...], "LEAD":[...]}
      // когда есть хотя бы одно совпадение, но как ПУСТОЙ СПИСОК []
      // когда совпадений вообще нет ни по одной сущности. Поэтому нельзя
      // жёстко кастовать в Map — нужно сначала проверить тип.
      final rawDupResult = dupData['result'];
      final dupResult = rawDupResult is Map<String, dynamic>
          ? rawDupResult
          : <String, dynamic>{};

      final contactIds = (dupResult['CONTACT'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      if (contactIds.isEmpty) return [];

      final listResponse = await dio.post(
        '$_bitrixWebhookUrl/crm.contact.list.json',
        data: {
          'filter': {'ID': contactIds},
          'select': ['ID', 'NAME', 'LAST_NAME', 'PHONE'],
        },
      );

      final listData = _unwrapResult(listResponse);
      final result = listData['result'] as List<dynamic>? ?? [];

      return result.map((e) {
        final item = e as Map<String, dynamic>;
        final phones = item['PHONE'] as List<dynamic>? ?? [];
        final phoneValue = phones.isNotEmpty
            ? (phones.first as Map<String, dynamic>)['VALUE']?.toString() ?? ''
            : '';

        return CustomerSearchResult(
          contactId: item['ID'].toString(),
          name: item['NAME']?.toString() ?? '',
          lastName: item['LAST_NAME']?.toString() ?? '',
          phone: phoneValue,
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('searchContactsByPhone: ошибка сети: $e');
      throw BitrixApiException('Ошибка соединения с Bitrix');
    }
  }

  /// Создаёт новый контакт. Возвращает ID созданного контакта.
  Future<String> createContact({
    required String name,
    String lastName = '',
    required String phone,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.contact.add.json',
        data: {
          'fields': {
            'NAME': name,
            'LAST_NAME': lastName,
            'PHONE': [
              {'VALUE': phone, 'VALUE_TYPE': 'WORK'},
            ],
          },
        },
      );

      final data = _unwrapResult(response);
      return data['result'].toString();
    } on DioException catch (e) {
      debugPrint('createContact: ошибка сети: $e');
      throw BitrixApiException('Не удалось создать контакт в Bitrix');
    }
  }

  // -------------------------------------------------------
  // Лиды
  // -------------------------------------------------------

  /// Создаёт лид, привязанный к контакту. Возвращает ID созданного лида.
  Future<String> createLead({
    required String contactId,
    required String name,
    required String phone,
    required CustomerType type,
    String comment = '',
    String sourceId = defaultSourceId,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.lead.add.json',
        data: {
          'fields': {
            'TITLE': 'Новый клиент (приложение): $name',
            'NAME': name,
            'PHONE': [
              {'VALUE': phone, 'VALUE_TYPE': 'WORK'},
            ],
            'COMMENTS': comment,
            'CONTACT_ID': contactId,
            _typeFieldCode: type.bitrixFieldId,
            _sourceFieldCode: [sourceId],
          },
        },
      );

      final data = _unwrapResult(response);
      return data['result'].toString();
    } on DioException catch (e) {
      debugPrint('createLead: ошибка сети: $e');
      throw BitrixApiException('Не удалось создать лид в Bitrix');
    }
  }
}
