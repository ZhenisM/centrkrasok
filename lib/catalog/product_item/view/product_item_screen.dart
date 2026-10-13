import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:centrkrasok/common/menu/menu_screen.dart';
import 'package:centrkrasok/common/animated_search_bar.dart';
import 'package:centrkrasok/repositories/products/products.dart';
import 'package:centrkrasok/cart/view/add_to_cart_sheet.dart';
import 'package:centrkrasok/cart/view/product_tint_sheet.dart';
import 'package:centrkrasok/catalog/product_list/widgets/product_tile.dart';

class ProductItemScreen extends StatefulWidget {
  const ProductItemScreen({super.key});

  @override
  State<ProductItemScreen> createState() => _ProductItemScreenState();
}

class _ProductItemScreenState extends State<ProductItemScreen> {
  Product? product;
  final _productsRepository = ProductsRepository(dio: Dio());
  final _dio = Dio();
  List<Section>? _sections;

  // Как на карточке сайта: «Наличие на складах» и связанные товары
  // («База», «Фасовка», у Kelly-Moore — «Степень блеска»). Онлайн.
  List<_StoreAmount>? _stores;
  List<_LinkedGroup> _linked = [];
  List<_BaseGroup> _bases = [];
  String _description = '';
  bool _detailLoading = false;
  bool _detailFailed = false;
  String? _loadedFor;
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    try {
      final sections = await _productsRepository.getSections();
      if (!mounted) return;
      setState(() => _sections = sections);
    } catch (_) {
      // молча — меню покажет только "На главную"
    }
  }

  void _menuOpen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          sections: _sections ?? const [],
          products: const [],
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Product) {
      setState(() {
        product = args;
      });
      if (_loadedFor != args.id) _loadDetail(args.id);
    }
  }

  Future<void> _loadDetail(String productId) async {
    _loadedFor = productId;
    setState(() { _detailLoading = true; _detailFailed = false; });
    try {
      final r = await _dio.get(
        'https://prons.kz/ajax/centrkrasok/product_detail.php',
        queryParameters: {'product_id': productId},
        options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 20)),
      );
      final data = jsonDecode(r.data as String) as Map<String, dynamic>;
      if (!mounted || _loadedFor != productId) return;
      setState(() {
        _stores = ((data['stores'] as List?) ?? [])
            .map((e) => _StoreAmount(e['title'].toString(), (e['amount'] as num).toDouble()))
            .toList();
        _linked = ((data['linked'] as List?) ?? []).map((g) => _LinkedGroup(
              g['title'].toString(),
              ((g['items'] as List?) ?? [])
                  .map((i) => _LinkedItem(i['id'].toString(), i['value'].toString(), i['current'] == true))
                  .toList(),
            )).toList();
        _bases = ((data['bases'] as List?) ?? []).map((b) => _BaseGroup(
              b['title'].toString(),
              ((b['ids'] as List?) ?? []).map((e) => e.toString()).toList(),
            )).toList();
        _description = (data['description'] ?? '').toString().trim();
      });
    } catch (e) {
      debugPrint('product_detail: $e');
      if (mounted && _loadedFor == productId) setState(() => _detailFailed = true);
    } finally {
      if (mounted && _loadedFor == productId) setState(() => _detailLoading = false);
    }
  }

  /// Переход на другую базу / фасовку — открываем карточку того товара.
  Future<void> _openLinked(_LinkedItem item) async {
    if (item.current || _openingId != null) return;
    setState(() => _openingId = item.id);
    try {
      final list = await _productsRepository.getProductsByIds([item.id]);
      if (!mounted) return;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось открыть товар — проверьте интернет')));
        return;
      }
      Navigator.of(context).pushReplacementNamed('/products-item', arguments: list.first);
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  String _propValue(String code) => (product!.props[code]?.value ?? '').trim();

  String _fmtAmount(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  String _fmtPrice(double price) {
    final s = price.toStringAsFixed(0).split('');
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₸';
  }

  @override
  Widget build(BuildContext context) {
    if (product == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          product!.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          const CatalogSearchBar(),
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/menu.svg',
              width: 22, height: 22,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            onPressed: _menuOpen,
          ),
        ],
      ),

      // Кнопка "В корзину" сверху, под ней панель навигации (2 иконки).
      // Кнопка визуально слита с панелью — фон/закругление/тень несёт
      // только AppBottomNavBar снизу, чтобы не было видимой границы.
      bottomNavigationBar: Container(
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                // «Колеровать» — как на сайте, только у товаров с color_da.
                if (product != null && canTintProduct(product!)) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showProductTintSheet(context, product!),
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('Колеровать'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4CAF50),
                        side: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => showAddToCartSheet(context, product!),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('В корзину'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ]),
            ),
            const AppBottomNavBar(currentTab: AppBottomTab.catalog),
          ],
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Название товара в теле страницы
          Text(
            product!.name,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Картинка товара
          if (product!.image != null && product!.image!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: product!.image!,
                height: 260,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.image_not_supported_outlined,
                  size: 48,
                  color: Colors.grey,
                ),
              ),
            ),

          const SizedBox(height: 20),

          // 1. Свойства — как на сайте: Артикул, Сегмент, Серия, Укрываемость
          _InfoRow(label: 'Артикул', value: product!.article ?? '—'),
          for (final e in const [['SEGMENT', 'Сегмент'], ['SERIA', 'Серия'], ['UKRYVAEMOST', 'Укрываемость']])
            if (_propValue(e[0]).isNotEmpty) _InfoRow(label: e[1], value: _propValue(e[0])),

          const SizedBox(height: 16),
          // Цена — показываем подтверждённую розничную группу (30 —
          // "Розничная ИСПОЛЬЗОВАТЬ"), а не вообще все типы цен подряд:
          // у части товаров в базе попутно заполнены ещё и партнёрские/
          // прайсовые цены (KASPI, АНД и т.п.), которые тут не нужны.
          if (product!.prices.isNotEmpty) ...[
            ...(() {
              final retail = product!.prices.where((p) => p.typeId == '30').toList();
              return retail.isNotEmpty ? retail : product!.prices;
            })().map(
                  (price) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Цена', style: TextStyle(color: Colors.grey)),
                    Text(
                      _fmtPrice(price.price),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 2. Наличие на складах
          const SizedBox(height: 16),
          const Text('Наличие на складах', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_detailLoading && _stores == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_stores == null)
            Text(_detailFailed ? 'Не удалось загрузить остатки — проверьте интернет' : '—',
                style: const TextStyle(color: Colors.grey))
          else if (_stores!.isEmpty)
            const Text('Остатков нет, товар только под заказ',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500))
          else
            ..._stores!.map((st) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(child: Text(st.title, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                    Text('${_fmtAmount(st.amount)} шт.', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                )),

          // 3. База, 4. Фасовка (и «Степень блеска» у Kelly-Moore)
          ..._linked.map((g) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: g.items.map((it) {
                    final loading = _openingId == it.id;
                    return InkWell(
                      onTap: () => _openLinked(it),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: it.current ? const Color(0xFF2E9E46) : const Color(0xFFC8EFCF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: loading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(it.value,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: it.current ? Colors.white : const Color(0xFF1B5E20),
                                  fontWeight: it.current ? FontWeight.w600 : FontWeight.w500,
                                )),
                      ),
                    );
                  }).toList()),
                ]),
              )),

          const SizedBox(height: 20),

          // Товары той же серии по базам (как блоки «BC» / «BW» на сайте)
          ..._bases.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BaseExpansionTile(group: b, repository: _productsRepository),
              )),

          // Свойства товара — развёртывающийся блок
          if (product!.props.isNotEmpty)
            _PropsExpansionTile(props: product!.props),

          // Описание — как вкладка «Описание» на сайте
          if (_description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ExpansionTile(
                title: const Text('Описание', style: TextStyle(fontWeight: FontWeight.w600)),
                shape: const Border(),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  SelectableText(_description, style: const TextStyle(fontSize: 14, height: 1.45)),
                ],
              ),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// Строка с меткой и значением
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// Развёртывающийся блок со свойствами
class _PropsExpansionTile extends StatelessWidget {
  const _PropsExpansionTile({required this.props});

  final Map<String, Prop> props;

  // Свойства, которые не нужно показывать в характеристиках — данные по
  // ним всё равно приходят и хранятся в product.props как обычно (это
  // чисто витринное решение, не серверное), просто пока не выводим:
  // - "Дополнительные картинки" — заготовка под будущий отдельный блок с доп. фото
  // - "Ссылка на Youtube видео" — заготовка под будущий вывод видео через webview
  // - "Фото отзывы" — пока не выводим
  // Сравниваем по вхождению подстроки, а не по точному совпадению всей
  // строки — реальное название в базе может отличаться формулировкой
  // (например, "Ссылка на Youtube видео", а не просто "Ссылка на youtube").
  static const _hiddenNameSubstrings = [
    'дополнительные картинки',
    'youtube',
    'фото отзывы',
  ];

  // Два РАЗНЫХ свойства с одинаковым отображаемым названием "Инструкция":
  // - INSTRUKSIYA (тип "Файл") — может содержать НЕСКОЛЬКО файлов, значения
  //   склеены через ", " (та же логика склейки, что в get_products.php для
  //   множественных файловых свойств)
  // - INSTRUKTSIYA (тип "Строка") — всегда одна ссылка
  // Различаем именно по коду, а не по названию — оба называются одинаково.
  static const _instructionCodes = {'INSTRUKSIYA', 'INSTRUKTSIYA'};

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final visibleEntries = props.entries.where((entry) {
      final name = entry.value.name.trim().toLowerCase();
      return !_hiddenNameSubstrings.any((s) => name.contains(s));
    }).toList();

    if (visibleEntries.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: const Text(
          'Характеристики',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        shape: const Border(),
        children: [
          const Divider(height: 1),
          ...visibleEntries.map((entry) {
            final isInstruction =
                _instructionCodes.contains(entry.key) &&
                entry.value.value.trim().isNotEmpty;

            // Файловые множественные свойства в get_products.php склеены
            // через ", " — если файлов несколько, тут будет несколько URL.
            final instructionUrls = isInstruction
                ? entry.value.value
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList()
                : const <String>[];

            return Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.value.name,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: isInstruction
                        ? Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              for (int i = 0; i < instructionUrls.length; i++)
                                InkWell(
                                  onTap: () => _openLink(instructionUrls[i]),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.picture_as_pdf_outlined,
                                          color: Colors.redAccent, size: 20),
                                      const SizedBox(width: 6),
                                      Text(
                                        instructionUrls.length > 1
                                            ? 'Файл ${i + 1}'
                                            : 'Открыть',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.blue.shade700,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          )
                        : Text(
                            entry.value.value,
                            style: const TextStyle(fontSize: 13),
                          ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StoreAmount {
  final String title;
  final double amount;
  _StoreAmount(this.title, this.amount);
}

class _LinkedItem {
  final String id;
  final String value;
  final bool current;
  _LinkedItem(this.id, this.value, this.current);
}

class _LinkedGroup {
  final String title;
  final List<_LinkedItem> items;
  _LinkedGroup(this.title, this.items);
}

class _BaseGroup {
  final String title;
  final List<String> ids;
  _BaseGroup(this.title, this.ids);
}

/// Раскрывающийся блок базы («BC», «BW»…) с карточками товаров той же
/// серии — как на сайте. Товары грузятся при первом раскрытии.
class _BaseExpansionTile extends StatefulWidget {
  const _BaseExpansionTile({required this.group, required this.repository});
  final _BaseGroup group;
  final ProductsRepository repository;

  @override
  State<_BaseExpansionTile> createState() => _BaseExpansionTileState();
}

class _BaseExpansionTileState extends State<_BaseExpansionTile> {
  List<Product>? _products;
  bool _loading = false;

  Future<void> _load() async {
    if (_products != null || _loading) return;
    setState(() => _loading = true);
    try {
      final list = await widget.repository.getProductsByIds(widget.group.ids);
      if (mounted) setState(() => _products = list);
    } catch (_) {
      if (mounted) setState(() => _products = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.of(context).size.width >= 576 ? 3 : 2;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: Text(widget.group.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${widget.group.ids.length} товаров', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        shape: const Border(),
        onExpansionChanged: (open) { if (open) _load(); },
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        children: [
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2))
          else if (_products != null && _products!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Не удалось загрузить товары', style: TextStyle(color: Colors.grey)),
            )
          else if (_products != null)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _products!.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.62,
              ),
              itemBuilder: (_, i) => ProductTile(product: _products![i]),
            ),
        ],
      ),
    );
  }
}
