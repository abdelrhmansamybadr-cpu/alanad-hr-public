/// Tolerant JSON readers: a missing / null / wrongly-typed field yields a default instead of a crash.
Map<String, dynamic> asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> asMapList(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

String jStr(Map m, String k, [String d = '']) {
  final v = m[k];
  return v == null ? d : v.toString();
}

String? jStrN(Map m, String k) {
  final v = m[k];
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int jInt(Map m, String k, [int d = 0]) {
  final v = m[k];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? d;
  return d;
}

int? jIntN(Map m, String k) {
  final v = m[k];
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double jDouble(Map m, String k, [double d = 0]) {
  final v = m[k];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? d;
  return d;
}

double? jDoubleN(Map m, String k) {
  final v = m[k];
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool jBool(Map m, String k, [bool d = false]) {
  final v = m[k];
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return d;
}

/// Parses `2026-09-30` or `2026-09-30 14:05:00` (server local time) into a DateTime, or null.
DateTime? jDate(Map m, String k) {
  final v = m[k];
  if (v == null) return null;
  final raw = v.toString().replaceFirst(' ', 'T');
  // "created at" moments are stored by the server in UTC; show them in the phone's own time.
  if (k == 'createdAt' && raw.length > 10 && !raw.endsWith('Z') && !raw.contains('+')) return DateTime.tryParse('${raw}Z')?.toLocal();
  return DateTime.tryParse(raw);
}
