import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:centrkrasok/bitrix/bitrix_service.dart';

/// Одна отложенная задача — все данные анкеты "Некачественный лид".
///
/// ВАЖНО: managerName хранится как ИМЯ, а не готовый ID — поиск ID
/// менеджера в Bitrix24 (findUserIdByName) сам по себе тоже сетевой
/// запрос, поэтому его тоже откладываем до фоновой обработки, а не
/// делаем на экране перед постановкой в очередь.
class PendingBadLeadJob {
  final String id; // локальный ID задачи (для очереди), не ID лида
  final String? title;
  final String comment;
  final String? peopleCount;
  final List<String> whoWasWith;
  final String? gender;
  final String? age;
  final List<String> psychotype;
  final List<String> failReasons;
  final String? managerName;
  final DateTime createdAt;

  PendingBadLeadJob({
    required this.id,
    required this.title,
    required this.comment,
    required this.peopleCount,
    required this.whoWasWith,
    required this.gender,
    required this.age,
    required this.psychotype,
    required this.failReasons,
    required this.managerName,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'comment': comment,
        'peopleCount': peopleCount,
        'whoWasWith': whoWasWith,
        'gender': gender,
        'age': age,
        'psychotype': psychotype,
        'failReasons': failReasons,
        'managerName': managerName,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PendingBadLeadJob.fromJson(Map<String, dynamic> json) => PendingBadLeadJob(
        id: json['id'] as String,
        title: json['title'] as String?,
        comment: json['comment'] as String? ?? '',
        peopleCount: json['peopleCount'] as String?,
        whoWasWith: (json['whoWasWith'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
        gender: json['gender'] as String?,
        age: json['age'] as String?,
        psychotype: (json['psychotype'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
        failReasons: (json['failReasons'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
        managerName: json['managerName'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Синглтон-очередь отправки некачественных лидов в фоне. Менеджер жмёт
/// "Сохранить" на анкете — задача мгновенно (без сети) ложится в очередь
/// и на диск, а сама отправка (создание лида) идёт
/// отдельно, в фоне, не блокируя интерфейс. Если сети нет или Bitrix не
/// отвечает — задача остаётся в очереди и повторяется позже, не теряется.
class BadLeadQueue {
  BadLeadQueue._();

  static final BadLeadQueue instance = BadLeadQueue._();

  static const _storageKey = 'pending_bad_leads';
  static const _retryInterval = Duration(seconds: 20);

  final _bitrixService = BitrixService(dio: Dio());
  final List<PendingBadLeadJob> _queue = [];
  bool _processing = false;
  Timer? _retryTimer;

  /// Сколько задач сейчас ждут отправки — можно показать менеджеру
  /// небольшим индикатором на главном экране.
  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  /// Вызывать один раз при старте приложения — подхватывает задачи,
  /// оставшиеся с прошлого запуска (например, приложение закрыли, пока
  /// сети не было).
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _queue.addAll(list.map((e) => PendingBadLeadJob.fromJson(e as Map<String, dynamic>)));
      pendingCount.value = _queue.length;
      _processNext();
    } catch (e) {
      debugPrint('BadLeadQueue.restore: не удалось прочитать очередь ($e)');
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_queue.map((j) => j.toJson()).toList()));
    pendingCount.value = _queue.length;
  }

  /// Кладёт задачу в очередь и сразу возвращает управление — сама
  /// отправка идёт в фоне, вызывающий код ждать её не должен.
  Future<void> enqueue(PendingBadLeadJob job) async {
    _queue.add(job);
    await _persist();
    _processNext(); // не await — запускаем и уходим
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryInterval, _processNext);
  }

  Future<void> _processNext() async {
    if (_processing || _queue.isEmpty) return;
    _processing = true;
    _retryTimer?.cancel();

    final job = _queue.first;
    try {
      int? managerId;
      if (job.managerName != null && job.managerName!.isNotEmpty) {
        managerId = await _bitrixService.findUserIdByName(job.managerName!);
      }

      final leadId = await _bitrixService.createBadLead(
        title: job.title,
        comment: job.comment,
        peopleCount: job.peopleCount,
        whoWasWith: job.whoWasWith,
        gender: job.gender,
        age: job.age,
        psychotype: job.psychotype,
        failReasons: job.failReasons,
        managerId: managerId,
      );
      debugPrint('BadLeadQueue: некачественный лид $leadId создан');

      _queue.removeAt(0);
      await _persist();
    } catch (e) {
      debugPrint('BadLeadQueue: не удалось отправить лид (${job.id}), попробую позже ($e)');
      _scheduleRetry();
    } finally {
      _processing = false;
    }

    if (_queue.isNotEmpty) {
      // Больше одной задачи — продолжаем сразу, без ожидания таймера.
      unawaited(_processNext());
    }
  }
}
