import 'package:flutter/widgets.dart';

/// Число колонок в сетках товаров по ширине экрана:
/// телефон — 2, планшет вертикально — 3, планшет горизонтально — 4.
/// (iPad mini: 744 pt вертикально → 3, 1133 pt горизонтально → 4.)
int catalogColumns(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  if (w >= 900) return 4;
  if (w >= 576) return 3;
  return 2;
}
