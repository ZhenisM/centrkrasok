import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:centrkrasok/bitrix/bitrix_service.dart';
import 'package:centrkrasok/customer/customer.dart';
import 'package:centrkrasok/cart/cart_api_service.dart';
import 'package:centrkrasok/cart/cart_local_store.dart';
import 'package:centrkrasok/cart/models/cart_model.dart';


/// Поиск существующего клиента — ОТДЕЛЬНО для контактов («Поиск
/// клиента», по телефону) и для компаний («Поиск компании»), как две
/// страницы сайта /client/search/contact/ и /client/search/company/.
enum CustomerSearchMode { contact, company }

class SearchCustomerScreen extends StatefulWidget {
  const SearchCustomerScreen({super.key, this.mode = CustomerSearchMode.contact, this.initialPhone});
  final CustomerSearchMode mode;
  /// Номер для автопоиска (переход из «Нового лида» при дубле).
  final String? initialPhone;

  @override
  State<SearchCustomerScreen> createState() => _SearchCustomerScreenState();
}

class _SearchCustomerScreenState extends State<SearchCustomerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.mode == CustomerSearchMode.company ? 'Поиск компании' : 'Поиск клиента',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          SizedBox(
            width: 130,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const TextField(
                  style: TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Поиск',
                    hintStyle: TextStyle(color: Colors.white70, fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: Colors.white70, size: 18),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: widget.mode == CustomerSearchMode.contact
                ? _ContactSearchView(initialPhone: widget.initialPhone)
                : const _CompanySearchView(),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------
class _ContactSearchView extends StatefulWidget {
  const _ContactSearchView({this.initialPhone});
  final String? initialPhone;
  @override
  State<_ContactSearchView> createState() => _ContactSearchViewState();
}

class _ContactSearchViewState extends State<_ContactSearchView> {
  final _phoneCtrl     = TextEditingController();
  final _bitrixService = BitrixService(dio: Dio());
  final _cartApiService = CartApiService(dio: Dio());

  bool _loading = false;
  String? _error;
  List<CustomerSearchResult>? _results;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPhone;
    if (p != null && p.isNotEmpty) {
      _phoneCtrl.text = p;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) { setState(() => _error = 'Введите телефон'); return; }
    setState(() { _loading = true; _error = null; _results = null; });
    try {
      final results = await _bitrixService.searchContactsByPhone(phone);
      setState(() { _results = results; _loading = false; });
    } on NoInternetException {
      setState(() { _error = 'Нет интернета'; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _select(CustomerSearchResult match) async {
    setState(() { _loading = true; _error = null; });
    final customer = Customer(
      contactId: match.contactId,
      isCompany: false,
      leadId: null,
      name: match.name,
      lastName: match.lastName,
      phone: match.phone,
      type: CustomerType.client,
      selectedAt: DateTime.now(),
    );
    try {
      await CustomerStorage.setActive(customer);

      final managerId = await CustomerStorage.currentManagerId();
      if (managerId == null) {
        throw CartApiException('Не удалось определить менеджера (не авторизован)');
      }
      final basketId = await _cartApiService.createCart(managerId: managerId, customer: customer);
      await CartLocalStore.upsertCart(
        Cart(
          id: basketId,
          title: customer.fullName,
          status: CartStatus.inProgress,
          dateCreate: DateTime.now(),
          clientInfo: customer.toMultibasketsClientInfo(),
        ),
        makeCurrent: true,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      Navigator.of(context).pushReplacementNamed('/products-list');
    } on NoInternetException {
      setState(() { _error = 'Нет интернета'; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Не удалось создать корзину'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Поле телефона
        _SearchField(
          controller: _phoneCtrl,
          hint: 'Номер телефона',
          keyboardType: TextInputType.phone,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),

        // Кнопка поиск
        _GreenButton(
          label: 'Поиск',
          loading: _loading && _results == null,
          onTap: _search,
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],

        // Результаты
        if (_results != null) ...[
          const SizedBox(height: 16),
          if (_results!.isEmpty)
            const Text('Клиент с таким номером не найден',
              style: TextStyle(color: Colors.grey))
          else
            ..._results!.map((m) => _ContactResultCard(
              result: m,
              loading: _loading,
              onSelect: () => _select(m),
            )),
        ],
      ]),
    );
  }
}

// -------------------------------------------------------
// Карточка результата — контакт
// -------------------------------------------------------
class _ContactResultCard extends StatelessWidget {
  const _ContactResultCard({
    required this.result,
    required this.loading,
    required this.onSelect,
  });
  final CustomerSearchResult result;
  final bool loading;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoRow(label: 'Имя', value: result.fullName),
        _InfoRow(label: 'Телефон', value: result.phone),
        _InfoRow(label: 'Тип', value: 'Клиент'),
        const SizedBox(height: 4),
        _GreenButton(label: 'Выбрать', loading: loading, onTap: onSelect),
        const SizedBox(height: 4),
      ]),
    );
  }
}

// -------------------------------------------------------
// Поиск компании
// -------------------------------------------------------
class _CompanySearchView extends StatefulWidget {
  const _CompanySearchView();
  @override
  State<_CompanySearchView> createState() => _CompanySearchViewState();
}

class _CompanySearchViewState extends State<_CompanySearchView> {
  final _titleCtrl      = TextEditingController();
  final _binCtrl        = TextEditingController();
  final _pronsApi       = PronsApiService(dio: Dio());
  final _cartApiService = CartApiService(dio: Dio());

  bool _loading = false;
  String? _error;
  List<CompanySearchResult>? _results;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _binCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final title = _titleCtrl.text.trim();
    final bin   = _binCtrl.text.trim();
    if (title.isEmpty && bin.isEmpty) {
      setState(() => _error = 'Введите название или БИН/ИИН');
      return;
    }
    setState(() { _loading = true; _error = null; _results = null; });
    try {
      final results = bin.isNotEmpty
          ? await _pronsApi.searchCompanies(query: bin, byBin: true)
          : await _pronsApi.searchCompanies(query: title, byBin: false);
      setState(() { _results = results; _loading = false; });
    } on NoInternetException {
      setState(() { _error = 'Нет интернета'; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Не удалось выполнить поиск'; _loading = false; });
    }
  }

  Future<void> _select(CompanySearchResult match) async {
    setState(() { _loading = true; _error = null; });
    final customer = Customer(
      companyId: match.companyId,
      isCompany: true,
      leadId: null,
      name: match.name,
      // Полное наименование — в lastName (fullName = name + lastName). Если
      // оно совпадает с названием или пустое — не добавляем, иначе название
      // корзины дублируется.
      lastName: match.fullName.trim() == match.name.trim() ? '' : match.fullName,
      phone: match.phone,
      email: match.email,
      bin: match.bin,
      type: CustomerType.client,
      selectedAt: DateTime.now(),
    );
    try {
      await CustomerStorage.setActive(customer);

      final managerId = await CustomerStorage.currentManagerId();
      if (managerId == null) {
        throw CartApiException('Не удалось определить менеджера (не авторизован)');
      }
      final basketId = await _cartApiService.createCart(managerId: managerId, customer: customer);
      await CartLocalStore.upsertCart(
        Cart(
          id: basketId,
          title: customer.fullName,
          status: CartStatus.inProgress,
          dateCreate: DateTime.now(),
          clientInfo: customer.toMultibasketsClientInfo(),
        ),
        makeCurrent: true,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      Navigator.of(context).pushReplacementNamed('/products-list');
    } on NoInternetException {
      setState(() { _error = 'Нет интернета'; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Не удалось создать корзину'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SearchField(
          controller: _titleCtrl,
          hint: 'Наименование',
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 10),
        _SearchField(
          controller: _binCtrl,
          hint: 'БИН/ИИН',
          keyboardType: TextInputType.number,
          maxLength: 12,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),

        _GreenButton(
          label: 'Поиск',
          loading: _loading && _results == null,
          onTap: _search,
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],

        if (_results != null) ...[
          const SizedBox(height: 16),
          if (_results!.isEmpty)
            const Text('Компания не найдена', style: TextStyle(color: Colors.grey))
          else
            ..._results!.map((m) => _CompanyResultCard(
              result: m,
              loading: _loading,
              onSelect: () => _select(m),
            )),
        ],
      ]),
    );
  }
}

// -------------------------------------------------------
// Карточка результата — компания
// -------------------------------------------------------
class _CompanyResultCard extends StatelessWidget {
  const _CompanyResultCard({
    required this.result,
    required this.loading,
    required this.onSelect,
  });
  final CompanySearchResult result;
  final bool loading;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoRow(label: 'Компания', value: result.name),
        if (result.fullName.isNotEmpty && result.fullName != result.name)
          _InfoRow(label: 'Полное наименование', value: result.fullName),
        if (result.bin.isNotEmpty) _InfoRow(label: 'БИН/ИИН', value: result.bin),
        if (result.phone.isNotEmpty) _InfoRow(label: 'Телефон', value: result.phone),
        if (result.email.isNotEmpty) _InfoRow(label: 'Email', value: result.email),
        const SizedBox(height: 4),
        _GreenButton(label: 'Выбрать', loading: loading, onTap: onSelect),
        const SizedBox(height: 4),
      ]),
    );
  }
}

// -------------------------------------------------------
// Общие виджеты
// -------------------------------------------------------

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
          counterText: '',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _GreenButton extends StatelessWidget {
  const _GreenButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });
  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50),
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

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
