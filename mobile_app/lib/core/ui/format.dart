import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../i18n/strings.dart';

/// `#RRGGBB` -> Color (falls back to [fallback]).
Color hexColor(String? hex, [Color fallback = const Color(0xFF00617A)]) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return fallback;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

String colorToHex(Color c) => '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

/// Server-relative file paths (`/uploads/...`) -> absolute URL.
String absUrl(String path) => path.startsWith('http') ? path : '${AppConfig.baseUrl}$path';

String _loc(BuildContext c) => Localizations.localeOf(c).languageCode;

String fmtDate(BuildContext c, DateTime d) => DateFormat.yMMMd(_loc(c)).format(d);
String fmtDayMonth(BuildContext c, DateTime d) => DateFormat.MMMd(_loc(c)).format(d);
String fmtWeekday(BuildContext c, DateTime d) => DateFormat.EEEE(_loc(c)).format(d);
String fmtWeekdayShort(BuildContext c, DateTime d) => DateFormat.E(_loc(c)).format(d);
String fmtMonthYear(BuildContext c, DateTime d) => DateFormat.yMMMM(_loc(c)).format(d);
String fmtLongDate(BuildContext c, DateTime d) => DateFormat.MMMMEEEEd(_loc(c)).format(d);

/// `14:05` or `14:05:33` -> `2:05 PM` (localised). Null -> `--:--`.
String fmtTime(BuildContext c, String? hhmm) {
  if (hhmm == null || hhmm.length < 4) return '--:--';
  final p = hhmm.split(':');
  final dt = DateTime(2000, 1, 1, int.tryParse(p[0]) ?? 0, int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  return DateFormat.jm(_loc(c)).format(dt);
}

String fmtClock(BuildContext c, DateTime d) => DateFormat.jm(_loc(c)).format(d);

String fmtRange(BuildContext c, DateTime a, DateTime b) {
  if (a.year == b.year && a.month == b.month && a.day == b.day) return fmtDate(c, a);
  return '${fmtDayMonth(c, a)} – ${fmtDate(c, b)}';
}

String money(BuildContext c, num v, String currency) {
  final f = NumberFormat.currency(locale: _loc(c), symbol: '', decimalDigits: v == v.roundToDouble() ? 0 : 2);
  return '${f.format(v).trim()} $currency';
}

String compactNumber(BuildContext c, num v) => NumberFormat.compact(locale: _loc(c)).format(v);

/// "5 min ago", "Yesterday", "Sep 3".
String timeAgo(BuildContext c, DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return c.isAr ? 'الآن' : 'Just now';
  if (diff.inMinutes < 60) return c.isAr ? 'منذ ${diff.inMinutes} د' : '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return c.isAr ? 'منذ ${diff.inHours} س' : '${diff.inHours} h ago';
  if (diff.inDays == 1) return c.t('common.yesterday');
  if (diff.inDays < 7) return fmtWeekday(c, d);
  return fmtDayMonth(c, d);
}

String greeting(BuildContext c) {
  final h = DateTime.now().hour;
  if (h < 12) return c.isAr ? 'صباح الخير' : 'Good morning';
  if (h < 17) return c.isAr ? 'مساء الخير' : 'Good afternoon';
  return c.isAr ? 'مساء الخير' : 'Good evening';
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Deterministic pleasant colour from a string (avatars, department dots).
Color colorFor(String seed) {
  const palette = [
    Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B),
    Color(0xFFEF4444), Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF14B8A6),
  ];
  var h = 0;
  for (final u in seed.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Great-circle distance in metres.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dp = rad(lat2 - lat1);
  final dl = rad(lng2 - lng1);
  final a = math.pow(math.sin(dp / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}
