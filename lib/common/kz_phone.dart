import 'package:flutter/services.dart';

/// Телефон Казахстана: 10 цифр после +7.
class KzPhone {
  KzPhone._();

  static const hint = '+7 (___) ___-__-__';

  /// 10 цифр номера без +7 (или меньше, если номер ещё вводят).
  static String national(String text) {
    var d = text.replaceAll(RegExp(r'\D'), '');
    if (text.trimLeft().startsWith('+7')) {
      d = d.substring(1); // «7» из префикса +7
    } else if (d.length == 11 && (d.startsWith('7') || d.startsWith('8'))) {
      d = d.substring(1); // вставили 8 777 … или 7 777 …
    }
    // Номера Казахстана после +7 начинаются с 7 (777…, 727…). Ведущую 8 —
    // привычку набирать «8 777…» — пропускаем.
    if (d.startsWith('8')) d = d.substring(1);
    return d.length > 10 ? d.substring(0, 10) : d;
  }

  static bool isComplete(String text) => national(text).length == 10;

  /// +77770150595 — для поиска и сохранения в Bitrix24.
  static String e164(String text) => '+7${national(text)}';

  /// +7 (777) 015-05-95 — для показа.
  static String format(String nationalDigits) {
    final d = nationalDigits;
    if (d.isEmpty) return '';
    final b = StringBuffer('+7 (');
    for (var i = 0; i < d.length; i++) {
      if (i == 3) b.write(') ');
      if (i == 6 || i == 8) b.write('-');
      b.write(d[i]);
    }
    return b.toString();
  }
}

/// Маска +7 (777) 015-05-95 при вводе. Понимает вставку номера в любом виде
/// (8 777…, +7 777…, 777…), а стирание скобки или дефиса стирает цифру перед ним.
class KzPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = KzPhone.national(newValue.text);
    final oldDigits = KzPhone.national(oldValue.text);
    // Стёрли символ маски (скобку, пробел, дефис) — цифры не изменились:
    // убираем последнюю цифру, иначе маска «вернёт» символ и стереть не получится.
    if (newValue.text.length < oldValue.text.length && digits == oldDigits && digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
    }
    final text = KzPhone.format(digits);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
