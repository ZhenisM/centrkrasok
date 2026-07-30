import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:centrkrasok/repositories/products/models/product.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:centrkrasok/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:centrkrasok/common/menu/menu_screen.dart';
import 'package:centrkrasok/common/animated_search_bar.dart';
import 'package:centrkrasok/repositories/products/products.dart';

class ProductItemScreen extends StatefulWidget {
  const ProductItemScreen({super.key});

  @override
  State<ProductItemScreen> createState() => _ProductItemScreenState();
}

class _ProductItemScreenState extends State<ProductItemScreen> {
  Product? product;
  final _productsRepository = ProductsRepository(dio: Dio());
  List<Section>? _sections;

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
    }
  }

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
            icon: const Icon(Icons.menu_outlined),
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
              child: FilledButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Корзина скоро будет доступна')),
                ),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('В корзину'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
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

          // Основная информация
          _InfoRow(label: 'Артикул', value: product!.article ?? '—'),
          if (product!.brend != null) _InfoRow(label: 'Бренд', value: product!.brend!),
          _InfoRow(label: 'ID товара', value: product!.id),
          _InfoRow(label: 'ID категории', value: product!.sectionId),

          const SizedBox(height: 20),

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
            const SizedBox(height: 12),
          ],

          // Свойства товара — развёртывающийся блок
          if (product!.props.isNotEmpty)
            _PropsExpansionTile(props: product!.props),

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
