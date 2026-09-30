import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:centrkrasok/customer/models/customer_model.dart';

/// Базовый URL входящего вебхука Bitrix24.
const String _bitrixWebhookUrl =
    'https://abis.bitrix24.kz/rest/21537/l7qiphejvc8khwx7';

/// "Тип клиента (КРАСКИ)" — одиночный выбор (Дизайнер / Клиент).
/// ID значений — CustomerType.bitrixPaintLeadFieldId.
const _typeFieldCode = 'UF_CRM_1674045477';

/// "Источник клиента (КРАСКИ) 2025" — множественный выбор (шлём одно
/// значение списком). Коды и ID сверены через crm.lead.fields.
const _sourceFieldCode = 'UF_CRM_1674124214';

/// ID значения "Другое" — источник по умолчанию, если менеджер не указал.
const String defaultSourceId = '35555';

/// Значения источника для выпадающего списка, id -> название (порядок
/// как в Bitrix24).
const Map<String, String> leadSources = {
  '35539': 'Существующий клиент',
  '35541': 'Инстаграм ЦК',
  '35543': 'Instagram dulux_almaty',
  '35545': 'Витрина',
  '35547': 'По рекомендации',
  '35549': 'По рекомендации дизайнера',
  '35551': 'Интернет-магазин',
  '35553': '2ГИС',
  '35555': 'Другое',
  '45501': 'От партнера направления SVET.kz',
  '102165': 'МК/Мероприятия',
  '102167': 'Выставка',
  '102169': 'Инстаграм премиум',
};

// -------------------------------------------------------
// Поля формы "Некачественный лид" (КРАСКИ). Коды и ID значений сверены
// через crm.lead.fields в Bitrix24: там, где у поля есть отдельная
// версия "(КРАСКИ)" (пол, возраст, психотип) — берём её; остальные
// поля (сколько человек, кто был, причина провала) общие для всех.
// -------------------------------------------------------

/// "Сколько человек было с клиентом (Анкета)" — одиночный выбор, общее.
const _peopleCountFieldCode = 'UF_CRM_1636358700';
const Map<String, String> peopleCountOptions = {
  '79087': 'Сам клиент',
  '13621': '1 (один)',
  '13623': '2 (два)',
  '13625': '3 (три)',
  '13627': '4 (четыре)',
  '13629': '5 (пять)',
  '13631': '6 (шесть)',
  '14105': 'Семья',
};
/// "Сам клиент" — поле "Кто был с клиентом" тогда не нужно.
const String peopleCountAloneId = '79087';

/// "Кто был с клиентом" — множественный выбор, общее.
const _whoWasWithFieldCode = 'UF_CRM_1636547473';
const Map<String, String> whoWasWithOptions = {
  '14107': 'Мужчина',
  '14109': 'Женщина',
  '14111': 'Бабушка',
  '14113': 'Дедушка',
  '14115': 'Ребенок',
  '14117': 'Девушка',
  '14119': 'Парень',
};

/// "Пол клиента (КРАСКИ)" — одиночный выбор.
const _genderFieldCode = 'UF_CRM_1674041857';
const Map<String, String> genderOptions = {
  '35437': 'Мужчина',
  '35439': 'Женщина',
  '35441': 'Семья',
};

/// Общее поле "Пол клиента" (без пометки) — пишем и в него, как в
/// offlinesvet: его показывает стандартная карточка лида.
const _genderFieldCode2 = 'UF_CRM_1636347555';
const Map<String, String> _genderIdToGenderFieldCode2 = {
  '35437': '13555', // Мужчина
  '35439': '13557', // Женщина
  '35441': '13559', // Семья
};

/// "Возраст клиента (КРАСКИ)" — одиночный выбор.
const _ageFieldCode = 'UF_CRM_1674042899';
const Map<String, String> ageOptions = {
  '35449': '25-35 лет',
  '35451': '35-45 лет',
  '35453': '45-55 лет',
  '35455': '55 и старше',
};

/// "Психотип клиента (КРАСКИ)" — множественный выбор.
const _psychotypeFieldCode = 'UF_CRM_1674046363';
const Map<String, String> psychotypeOptions = {
  '35489': 'Аудиал',
  '35491': 'Визуал',
  '35493': 'Кинестетик',
  '35495': 'Диджитал',
};

/// "Причина провала Лида" — множественный выбор, общее.
const _failReasonFieldCode = 'UF_CRM_1739347472';
const Map<String, String> failReasonOptions = {
  '79113': 'Клиент отказался предоставить данные',
  '79115': 'Отсутствие интереса',
  '79117': 'Нет в ассортименте',
  '79119': 'Дорого (цену озвучил)',
  '79121': 'Не готов к покупкам',
  '79123': 'Просто интересовался',
};

/// Статус "Некачественный лид" (системное STATUS_ID).
const String badLeadStatusId = 'JUNK';

/// Источник лида "Приложение Краски" (системное SOURCE_ID, сверено через
/// crm.status.list). У offlinesvet — "Приложение Svet" (UC_SY64LH).
const String appSourceId = 'UC_PLMEMT';

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

  /// Ищет пользователя Bitrix24 по ФИО — нужен, потому что user_id менеджера
  /// в приложении берётся из другой системы (prons.kz, 1C-Bitrix) и НЕ
  /// совпадает с ID того же человека в Bitrix24 (два разных продукта,
  /// независимая нумерация пользователей). Возвращает null, если совпадений
  /// нет или их несколько (чтобы не назначить лид не тому человеку наугад).
  ///
  /// ВАЖНО: user_name хранится строкой вида "Фамилия Имя" (например,
  /// "Леготкин Максим"), а в самом Bitrix24 это два ОТДЕЛЬНЫХ поля (NAME,
  /// LAST_NAME) — такая же точная строка "Леготкин Максим" нигде в
  /// профиле не хранится целиком, поэтому широкий FILTER[FIND] по всей
  /// строке её не находит. Разбиваем на слова и ищем прицельно по полям.
  Future<int?> findUserIdByName(String fullName) async {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    // user_name хранится как "Фамилия Имя" — для обычного случая (без
    // отчества) это ровно два слова.
    if (parts.length == 2) {
      final byOrder1 = await _findUserId(lastName: parts[0], name: parts[1]);
      if (byOrder1 != null) return byOrder1;
      // На случай если где-то ФИО сохранено в обратном порядке ("Имя Фамилия").
      final byOrder2 = await _findUserId(lastName: parts[1], name: parts[0]);
      if (byOrder2 != null) return byOrder2;
    }

    // Запасной вариант (три и более слова — с отчеством, или одно слово) —
    // широкий поиск по всей строке через user.search.
    return _findUserIdByFind(fullName);
  }

  Future<int?> _findUserId({required String lastName, required String name}) async {
    try {
      final response = await dio.get(
        '$_bitrixWebhookUrl/user.get.json',
        queryParameters: {
          'FILTER[NAME]': name,
          'FILTER[LAST_NAME]': lastName,
        },
      );
      final data = _unwrapResult(response);
      final results = data['result'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      if (results.length > 1) {
        debugPrint('findUserIdByName: неоднозначно — найдено ${results.length} '
            'пользователей Bitrix24 по имени "$name $lastName", пропускаю ASSIGNED_BY_ID');
        return null;
      }
      final id = results.first['ID'];
      return int.tryParse(id.toString());
    } catch (e) {
      debugPrint('findUserIdByName: ошибка user.get ($e)');
      return null;
    }
  }

  Future<int?> _findUserIdByFind(String fullName) async {
    try {
      final response = await dio.get(
        '$_bitrixWebhookUrl/user.search.json',
        queryParameters: {'FILTER[FIND]': fullName},
      );
      final data = _unwrapResult(response);
      final results = data['result'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        debugPrint('findUserIdByName: пользователь Bitrix24 не найден по имени "$fullName"');
        return null;
      }
      if (results.length > 1) {
        debugPrint('findUserIdByName: неоднозначно — найдено ${results.length} '
            'пользователей Bitrix24 по имени "$fullName", пропускаю ASSIGNED_BY_ID');
        return null;
      }
      final id = results.first['ID'];
      return int.tryParse(id.toString());
    } catch (e) {
      debugPrint('findUserIdByName: ошибка user.search ($e)');
      return null;
    }
  }

  /// Создаёт лид, привязанный к контакту. Возвращает ID созданного лида.
  Future<String> createLead({
    required String contactId,
    required String name,
    required String phone,
    required CustomerType type,
    String comment = '',
    String sourceId = defaultSourceId,
    int? managerId,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.lead.add.json',
        data: {
          'fields': {
            'TITLE': 'Новый клиент (приложение): $name',
            // Без явного SOURCE_ID Bitrix ставит первый по сортировке
            // источник ("Витрина").
            'SOURCE_ID': appSourceId,
            'NAME': name,
            'PHONE': [
              {'VALUE': phone, 'VALUE_TYPE': 'WORK'},
            ],
            'COMMENTS': comment,
            'CONTACT_ID': contactId,
            _typeFieldCode: type.bitrixPaintLeadFieldId,
            _sourceFieldCode: [sourceId],
            // Без этого ответственным становится владелец вебхука, а не
            // менеджер, который создал лид в приложении.
            if (managerId != null) 'ASSIGNED_BY_ID': managerId,
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

  /// "Некачественный лид" — отдельная короткая анкета для случаев, когда
  /// сделка не состоялась (клиент отказался от общения, ушёл без покупки
  /// и т.п.). В отличие от createLead(), НЕ создаёт контакт и не требует
  /// имя/телефон — сайт тоже не спрашивает контактные данные на этом
  /// сценарии (одна из причин провала — "Клиент отказался предоставить
  /// данные"). STATUS_ID выставляется сразу в "Некачественный лид"
  /// (badLeadStatusId) и в самой форме не выбирается.
  Future<String> createBadLead({
    String? title,
    String comment = '',
    String? peopleCount,
    List<String> whoWasWith = const [],
    String? gender,
    String? age,
    List<String> psychotype = const [],
    List<String> failReasons = const [],
    int? managerId,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.lead.add.json',
        data: {
          'fields': {
            'TITLE': (title != null && title.isNotEmpty) ? title : 'Некачественный лид (приложение Краски)',
            'SOURCE_ID': appSourceId,
            'STATUS_ID': badLeadStatusId,
            'COMMENTS': comment,
            // Без этого поля Bitrix назначает ответственным того, на кого
            // настроен сам вебхук — а не менеджера, который реально
            // авторизован в приложении и создал лид.
            if (managerId != null) 'ASSIGNED_BY_ID': managerId,
            if (peopleCount != null) _peopleCountFieldCode: peopleCount,
            if (whoWasWith.isNotEmpty) _whoWasWithFieldCode: whoWasWith,
            if (gender != null) _genderFieldCode: gender,
            if (gender != null && _genderIdToGenderFieldCode2[gender] != null)
              _genderFieldCode2: _genderIdToGenderFieldCode2[gender],
            if (age != null) _ageFieldCode: age,
            if (psychotype.isNotEmpty) _psychotypeFieldCode: psychotype,
            if (failReasons.isNotEmpty) _failReasonFieldCode: failReasons,
          },
        },
      );

      final data = _unwrapResult(response);
      final leadId = data['result'].toString();


      return leadId;
    } on DioException catch (e) {
      debugPrint('createBadLead: ошибка сети: $e');
      throw BitrixApiException('Не удалось создать лид в Bitrix');
    }
  }
}
