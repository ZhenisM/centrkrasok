import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:centrkrasok/repositories/products/products.dart';
import 'package:centrkrasok/catalog/category/view/category_screen.dart';

/// Корень каталога — как /catalog/ сайта: кнопка «Каталог по брендам»
/// раскрывает плитки брендов (разделы верхнего уровня без служебных с
/// сортировкой ≥ 2000), а ниже — ВСЕ товары каталога с фильтром и
/// сортировкой (тот же экран, что у раздела, только для всего каталога).
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _repository = ProductsRepository(dio: Dio());
  List<Section> _sections = [];

  @override
  void initState() {
    super.initState();
    _repository.getSections().then((s) {
      if (mounted) setState(() => _sections = s);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return CategoryScreen(
      // section_id = 0 — весь каталог (get_products / get_filters так умеют).
      section: Section(id: '0', name: 'Каталог', children: const []),
      allProducts: const [],
      allSections: _sections,
      header: _BrandsBlock(sections: _sections),
    );
  }
}

class _Brand {
  final String id, name, image;
  final int count;
  _Brand(this.id, this.name, this.image, this.count);
}

/// «Каталог по брендам» — зелёная кнопка, раскрывает плитки брендов.
class _BrandsBlock extends StatefulWidget {
  const _BrandsBlock({required this.sections});
  final List<Section> sections;

  @override
  State<_BrandsBlock> createState() => _BrandsBlockState();
}

class _BrandsBlockState extends State<_BrandsBlock> {
  static List<_Brand>? _cache; // на время работы приложения
  bool _open = false;
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    if (_cache != null || _loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Dio().get('https://prons.kz/ajax/centrkrasok/catalog_brands.php',
          options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 20)));
      final list = ((jsonDecode(r.data as String) as Map)['brands'] as List)
          .map((b) => _Brand('${b['id']}', '${b['name']}', '${b['image'] ?? ''}', (b['count'] as num).toInt()))
          .toList();
      _cache = list;
    } catch (_) {
      _error = 'Не удалось загрузить бренды — проверьте интернет';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Section? _find(String id, List<Section> list) {
    for (final s in list) {
      if (s.id == id) return s;
      final f = _find(id, s.children);
      if (f != null) return f;
    }
    return null;
  }

  void _openBrand(_Brand b) {
    final section = _find(b.id, widget.sections) ?? Section(id: b.id, name: b.name, children: const []);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CategoryScreen(section: section, allProducts: const [], allSections: widget.sections),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final brands = _cache;
    final columns = MediaQuery.of(context).size.width >= 576 ? 4 : 3;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          color: const Color(0xFF4CAF50), // общий зелёный приложения
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() => _open = !_open);
              if (_open) _load();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                const Expanded(child: Text('Каталог по брендам',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500))),
                Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white),
              ]),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.grey))),
                TextButton(onPressed: _load, child: const Text('Повторить')),
              ]),
            )
          else if (brands != null)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: brands.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (_, i) {
                final b = brands[i];
                return InkWell(
                  onTap: () => _openBrand(b),
                  borderRadius: BorderRadius.circular(18),
                  child: Column(children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        clipBehavior: Clip.antiAlias,
                        padding: const EdgeInsets.all(6),
                        child: b.image.isEmpty
                            ? Icon(Icons.photo_camera_outlined, color: Colors.grey.shade300, size: 36)
                            : CachedNetworkImage(imageUrl: b.image, fit: BoxFit.contain,
                                errorWidget: (c, u, e) => Icon(Icons.photo_camera_outlined, color: Colors.grey.shade300)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${b.name}(${b.count})',
                        maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1B5E20))),
                  ]),
                );
              },
            ),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }
}
