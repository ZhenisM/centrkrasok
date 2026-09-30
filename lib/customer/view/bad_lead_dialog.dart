import 'package:flutter/material.dart';
import 'package:centrkrasok/bitrix/bitrix_service.dart';
import 'package:centrkrasok/customer/customer.dart';
import 'package:centrkrasok/customer/bad_lead_queue.dart';

Future<bool?> showBadLeadDialog(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFF3F2F7),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const BadLeadSheet(),
  );
}

class BadLeadSheet extends StatefulWidget {
  const BadLeadSheet({super.key});

  @override
  State<BadLeadSheet> createState() => _BadLeadSheetState();
}

class _BadLeadSheetState extends State<BadLeadSheet> {
  final _titleController = TextEditingController();
  final _commentController = TextEditingController();

  String? _peopleCount;
  final Set<String> _whoWasWith = {};
  String? _gender;
  String? _age;
  final Set<String> _psychotype = {};
  final Set<String> _failReasons = {};

  bool _loading = false;
  String? _error;


  @override
  void dispose() {
    _titleController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _peopleCount != null &&
      (_peopleCount == peopleCountAloneId || _whoWasWith.isNotEmpty) &&
      _gender != null &&
      _age != null &&
      _psychotype.isNotEmpty &&
      _failReasons.isNotEmpty;

  /// Отправка не ждёт сеть: задача мгновенно ложится в фоновую очередь
  /// (BadLeadQueue), форма сразу закрывается, лид создаётся в фоне.
  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() { _loading = true; _error = null; });

    try {
      final managerName = await CustomerStorage.currentManagerName();
      final title = _titleController.text.trim();

      await BadLeadQueue.instance.enqueue(PendingBadLeadJob(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        title: title.isNotEmpty ? title : null,
        comment: _commentController.text.trim(),
        peopleCount: _peopleCount,
        whoWasWith: _whoWasWith.toList(),
        gender: _gender,
        age: _age,
        psychotype: _psychotype.toList(),
        failReasons: _failReasons.toList(),
        managerName: managerName,
        createdAt: DateTime.now(),
      ));

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лид добавлен в очередь на отправку')),
      );
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        color: const Color(0xFFF3F2F7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Form(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Некачественный лид',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: Colors.black54,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                _SectionTitle('Название лида'),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    hintText: 'Некачественный лид (приложение)',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _SectionTitle('Сколько человек было с клиентом'),
                _SingleChoiceChips(
                  options: peopleCountOptions,
                  value: _peopleCount,
                  onChanged: (v) => setState(() {
                    _peopleCount = v;
                    if (v == peopleCountAloneId) _whoWasWith.clear();
                  }),
                ),

                if (_peopleCount != null && _peopleCount != peopleCountAloneId) ...[
                  const SizedBox(height: 16),
                  _SectionTitle('Кто был с клиентом'),
                  _MultiChoiceChips(
                    options: whoWasWithOptions,
                    values: _whoWasWith,
                    onToggle: (id) => setState(() {
                      if (!_whoWasWith.add(id)) _whoWasWith.remove(id);
                    }),
                  ),
                ],

                const SizedBox(height: 16),
                _SectionTitle('Пол клиента'),
                _SingleChoiceChips(
                  options: genderOptions,
                  value: _gender,
                  onChanged: (v) => setState(() => _gender = v),
                ),

                const SizedBox(height: 16),
                _SectionTitle('Возраст клиента'),
                _SingleChoiceChips(
                  options: ageOptions,
                  value: _age,
                  onChanged: (v) => setState(() => _age = v),
                ),

                const SizedBox(height: 16),
                _SectionTitle('Психотип клиента'),
                _MultiChoiceChips(
                  options: psychotypeOptions,
                  values: _psychotype,
                  onToggle: (id) => setState(() {
                    if (!_psychotype.add(id)) _psychotype.remove(id);
                  }),
                ),

                const SizedBox(height: 16),
                _SectionTitle('Причина провала лида'),
                _MultiChoiceChips(
                  options: failReasonOptions,
                  values: _failReasons,
                  onToggle: (id) => setState(() {
                    if (!_failReasons.add(id)) _failReasons.remove(id);
                  }),
                ),

                const SizedBox(height: 16),
                _SectionTitle('Комментарий (необязательно)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Комментарий',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],

                const SizedBox(height: 20),

                GestureDetector(
                  onTap: (_loading || !_canSubmit) ? null : _submit,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: _canSubmit ? const Color(0xFF4CAF50) : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    alignment: Alignment.center,
                    child: _loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Сохранить',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500)),
    );
  }
}

/// Группа чипов с одиночным выбором (аналог радио) — для "Пол"/"Возраст"/
/// "Сколько человек было с клиентом".
class _SingleChoiceChips extends StatelessWidget {
  const _SingleChoiceChips({required this.options, required this.value, required this.onChanged});
  final Map<String, String> options;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: options.entries.map((e) {
        final selected = value == e.key;
        return GestureDetector(
          onTap: () => onChanged(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF4CAF50) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(e.value,
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: selected ? Colors.white : Colors.black54,
                )),
          ),
        );
      }).toList(),
    );
  }
}

/// Группа чипов с множественным выбором (аналог чекбоксов) — для "Кто был
/// с клиентом"/"Психотип"/"Причина провала лида".
class _MultiChoiceChips extends StatelessWidget {
  const _MultiChoiceChips({required this.options, required this.values, required this.onToggle});
  final Map<String, String> options;
  final Set<String> values;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: options.entries.map((e) {
        final selected = values.contains(e.key);
        return GestureDetector(
          onTap: () => onToggle(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF4CAF50) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(e.value,
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: selected ? Colors.white : Colors.black54,
                )),
          ),
        );
      }).toList(),
    );
  }
}
