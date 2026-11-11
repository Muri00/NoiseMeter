import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'en.dart';

/// Език на приложението: български (основен) или английски.
///
/// Текстовете в кода са на български и служат като ключ за превода: tr('Вход') дава
/// "Sign in", когато е избран английски. Ако за даден текст липсва превод, се показва
/// българският. Стойностите се вмъкват чрез {име}: tr('Точки: {n}', {'n': 3}).
class AppLanguage extends ChangeNotifier {
  static const supported = ['bg', 'en'];
  static const _prefsKey = 'language';

  /// Текущият език - чете се от tr(), включително извън widget-ите (съобщения за грешки).
  static String current = 'bg';

  String get code => current;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && supported.contains(saved)) current = saved;
    notifyListeners();
  }

  Future<void> set(String lang) async {
    if (!supported.contains(lang) || lang == current) return;
    current = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, lang);
    notifyListeners();
  }
}

String tr(String bg, [Map<String, Object?>? args]) {
  var text = AppLanguage.current == 'en' ? (en[bg] ?? bg) : bg;
  args?.forEach((key, value) => text = text.replaceAll('{$key}', '${value ?? ''}'));
  return text;
}

/// Име на периода от денонощието.
String periodName(String? period) => switch (period) {
      'day' => tr('Ден (07–19 ч)'),
      'evening' => tr('Вечер (19–23 ч)'),
      'night' => tr('Нощ (23–07 ч)'),
      _ => tr('Автоматично (по часа)'),
    };
