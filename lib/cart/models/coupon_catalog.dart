/// Справочник купонов — 1:1 с массивом $coupons в result_modifier.php
/// компонента sale.basket.basket на сайте. Реальный процент/сумму скидки
/// определяет настройка скидки в Bitrix (админка), привязанная к коду
/// купона — тут только список кодов для выбора и проверка на сервере
/// (\Bitrix\Sale\DiscountCouponsManager::getData), что код существует и
/// активен.
sealed class CouponEntry {
  const CouponEntry();
}

/// Обычный плоский заголовок раздела без своих купонов — на сайте это
/// `['GROUP_TITLE' => '...']` (например "Жума").
class CouponSectionHeader extends CouponEntry {
  const CouponSectionHeader(this.title);
  final String title;
}

/// Именованная группа купонов — на сайте `['NAME' => ..., 'COUPONS' => [...]]`.
class CouponGroup extends CouponEntry {
  const CouponGroup(this.name, this.codes);
  final String name;
  final List<String> codes;
}

const List<CouponEntry> couponCatalog = [
  CouponGroup('Регламентные скидки', ['3%', '5%', '7%', '10%']),
  CouponGroup('На объем', ['V12%', 'V15%', 'V20%', 'V25%']),
  CouponGroup('Вместо бонусов для партнера',
      ['bonus5%', 'bonus10%', 'bonus15%', 'bonus20%', 'bonus25%']),
  CouponGroup('От владельца',
      ['BOSS10%', 'BOSS15%', 'BOSS20%', 'BOSS25%', 'BOSS30%']),
  CouponGroup('Сотрудникам', ['С25%']),
  CouponGroup('Сотрудникам AND', ['AND30%']),
  CouponGroup('ARGILE и PPL', ['ARPL3%', 'ARPL5%', 'ARPL7%']),
  CouponGroup('ORAC', [
    'ORAC3%', 'ORAC7%', 'ORAC5%', 'ORAC10%', 'ORAC15%', 'ORAC20%',
    'ORAC3X', 'ORAC5X', 'ORAC7X', 'ORAC10X', 'ORAC15X', 'ORAC20X',
  ]),
  CouponGroup('Скидка каталога', ['Скидка каталога 15%', 'Скидка каталога 20%']),
  CouponSectionHeader('Жума'),
  CouponGroup('Регламентные скидки Жума',
      ['ZHUMA1.5%', 'ZHUMA2.5%', 'ZHUMA3.5%', 'ZHUMA5%']),
  CouponGroup('Скидка каталога Жума', ['ZHUMA7.5%', 'ZHUMA10%']),
];
