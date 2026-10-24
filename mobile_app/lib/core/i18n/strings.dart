import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings_auth.dart';
import 'strings_common.dart';
import 'strings_employee.dart';
import 'strings_group.dart';
import 'strings_hr.dart';
import 'strings_meetings.dart';
import 'strings_premium.dart';
import 'strings_v2.dart';

/// All UI text, English and Arabic. Feature files contribute their own maps; they are merged here.
final Map<String, String> _en = {...commonEn, ...authEn, ...employeeEn, ...hrEn, ...v2En, ...groupEn, ...meetingsEn, ...premiumEn};
final Map<String, String> _ar = {...commonAr, ...authAr, ...employeeAr, ...hrAr, ...v2Ar, ...groupAr, ...meetingsAr, ...premiumAr};

extension TrX on BuildContext {
  /// Translate [key] for the current locale. `{name}` placeholders are replaced from [args].
  String t(String key, [Map<String, Object?>? args]) {
    final ar = Localizations.localeOf(this).languageCode == 'ar';
    return trFor(ar ? 'ar' : 'en', key, args);
  }

  bool get isAr => Localizations.localeOf(this).languageCode == 'ar';
}

String trFor(String lang, String key, [Map<String, Object?>? args]) {
  var s = (lang == 'ar' ? _ar[key] : null) ?? _en[key] ?? key;
  if (args != null) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  }
  return s;
}

/// The user's chosen language ("en" / "ar"). Defaults to the device language.
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(_initial()) {
    _load();
  }

  static Locale _initial() {
    final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return Locale(device == 'ar' ? 'ar' : 'en');
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('lang');
    if (saved != null && saved != state.languageCode) state = Locale(saved);
  }

  Future<void> set(String lang) async {
    state = Locale(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', lang);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) => LocaleNotifier());
