import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:centrkrasok/bitrix/bitrix_service.dart';
import 'package:centrkrasok/customer/customer.dart';

Future<bool?> showNewCustomerDialog(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFF3F2F7),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const NewCustomerSheet(),
  );
}

class NewCustomerSheet extends StatefulWidget {
  const NewCustomerSheet({super.key});

  @override
  State<NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends State<NewCustomerSheet> {
  final _formKey          = GlobalKey<FormState>();
  final _nameController   = TextEditingController();
  final _phoneController  = TextEditingController();
  final _commentController = TextEditingController();

  final _bitrixService  = BitrixService(dio: Dio());

  CustomerType _type     = CustomerType.client;
  String       _sourceId = defaultSourceId;
  bool         _loading  = false;
  String?      _error;

  List<CustomerSearchResult>? _existingMatches;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _loading = true; _error = null; _existingMatches = null; });

    final name  = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    try {
      final matches = await _bitrixService.searchContactsByPhone(phone);
      if (matches.isNotEmpty) {
        setState(() { _existingMatches = matches; _loading = false; });
        return;
      }

      final contactId = await _bitrixService.createContact(name: name, phone: phone);
      final leadId = await _bitrixService.createLead(
        contactId: contactId,
        name: name,
        phone: phone,
        type: _type,
        comment: _commentController.text.trim(),
        sourceId: _sourceId,
      );

      final customer = Customer(
        contactId: contactId,
        isCompany: false,
        leadId: leadId,
        name: name,
        phone: phone,
        type: _type,
        selectedAt: DateTime.now(),
      );
      await _finalizeCustomerSelection(customer);
    } on NoInternetException {
      setState(() { _error = 'Нет интернета'; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _selectExisting(CustomerSearchResult match) async {
    setState(() { _loading = true; _error = null; });
    final customer = Customer(
      contactId: match.contactId,
      isCompany: false,
      leadId: null,
      name: match.name,
      lastName: match.lastName,
      phone: match.phone,
      type: _type,
      selectedAt: DateTime.now(),
    );
    try {
      await _finalizeCustomerSelection(customer);
    } on NoInternetException {
      setState(() { _error = 'Нет интернета'; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Не удалось создать корзину'; _loading = false; });
    }
  }

  Future<void> _finalizeCustomerSelection(Customer customer) async {
    await CustomerStorage.setActive(customer);
    // Корзина в centrkrasok пока не реализована (логика мультикорзины
    // будет переделана отдельно) — просто сохраняем клиента и сразу
    // переходим в каталог.
    // final managerId = await CustomerStorage.currentManagerId();
    // if (managerId != null) {
    //   await _cartApiService.createCart(managerId: managerId, customer: customer);
    // }
    if (!mounted) return;
    Navigator.of(context).pop(true);
    Navigator.of(context).pushReplacementNamed('/products-list');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        color: const Color(0xFFF3F2F7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: _existingMatches != null
              ? _buildExistingMatches()
              : _buildForm(),
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // Форма анкеты
  // -------------------------------------------------------
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Хвостик
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

          // Заголовок
          const Text(
            'Анкета лида',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Имя
          _WhiteInput(
            controller: _nameController,
            hint: 'Имя *',
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажите имя' : null,
          ),
          const SizedBox(height: 10),

          // Телефон
          _WhiteInput(
            controller: _phoneController,
            hint: 'Телефон *',
            keyboardType: TextInputType.phone,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажите телефон' : null,
          ),
          const SizedBox(height: 16),

          // Тип клиента
          const Text(
            'Тип клиента',
            style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(children: [
              Expanded(child: _RadioChip(
                label: 'Клиент',
                selected: _type == CustomerType.client,
                onTap: () => setState(() => _type = CustomerType.client),
              )),
              Expanded(child: _RadioChip(
                label: 'Дизайнер',
                selected: _type == CustomerType.designer,
                onTap: () => setState(() => _type = CustomerType.designer),
              )),
            ]),
          ),
          const SizedBox(height: 16),

          // Источник
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButtonFormField<String>(
                value: _sourceId,
                decoration: const InputDecoration(
                  labelText: 'Источник (необязательно)',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                isExpanded: true,
                items: leadSources.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _sourceId = v ?? defaultSourceId),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Комментарий
          _WhiteInput(
            controller: _commentController,
            hint: 'Комментарий',
            maxLines: 3,
            borderRadius: 16,
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],

          const SizedBox(height: 20),

          // Кнопка создать
          GestureDetector(
            onTap: _loading ? null : _submit,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                borderRadius: BorderRadius.circular(28),
              ),
              alignment: Alignment.center,
              child: _loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Создать',
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
    );
  }

  // -------------------------------------------------------
  // Найден существующий клиент
  // -------------------------------------------------------
  Widget _buildExistingMatches() {
    return Column(
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
        const Text(
          'Клиент с таким номером уже существует',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._existingMatches!.map((m) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoRow(label: 'Имя', value: m.fullName),
            _InfoRow(label: 'Телефон', value: m.phone),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _loading ? null : () => _selectExisting(m),
              child: Container(
                height: 46,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(28),
                ),
                alignment: Alignment.center,
                child: _loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Выбрать',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ]),
        )),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _loading ? null : () => setState(() => _existingMatches = null),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Отмена',
              style: TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------
// Белый инпут без бордера, полукруглый
// -------------------------------------------------------
class _WhiteInput extends StatelessWidget {
  const _WhiteInput({
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.borderRadius = 28.0,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final int maxLines;
  final double borderRadius;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
      ),
    );
  }
}

// -------------------------------------------------------
// Радио-чип переключатель
// -------------------------------------------------------
class _RadioChip extends StatelessWidget {
  const _RadioChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4CAF50) : Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------
// Строка информации в карточке
// -------------------------------------------------------
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15)),
      ]),
    );
  }
}
