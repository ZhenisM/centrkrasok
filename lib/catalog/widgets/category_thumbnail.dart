import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Миниатюра категории (слева от названия в списках разделов/подразделов).
/// Если картинки нет (не задана в Bitrix, или ещё не закэширована для
/// офлайн-показа) — показываем нейтральную заглушку вместо пустого места,
/// чтобы список не "прыгал" по высоте строк.
class CategoryThumbnail extends StatelessWidget {
  const CategoryThumbnail({super.key, required this.imageUrl, this.size = 44});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: imageUrl == null
          ? Container(
              width: size, height: size,
              color: Colors.grey.shade200,
              child: Icon(Icons.category_outlined, color: Colors.grey.shade400, size: size * 0.5),
            )
          : CachedNetworkImage(
              imageUrl: imageUrl!,
              width: size, height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(width: size, height: size, color: Colors.grey.shade200),
              errorWidget: (_, __, ___) => Container(
                width: size, height: size,
                color: Colors.grey.shade200,
                child: Icon(Icons.category_outlined, color: Colors.grey.shade400, size: size * 0.5),
              ),
            ),
    );
  }
}
