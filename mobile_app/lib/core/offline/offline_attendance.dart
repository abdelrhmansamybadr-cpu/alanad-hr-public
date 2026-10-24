import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';

/// An id that stays the same on this installation. The server uses it to notice one phone shared by two people.
Future<String> phoneId() async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString('phone_id');
  if (id == null || id.length < 16) {
    final r = Random.secure();
    id = List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
    await prefs.setString('phone_id', id);
  }
  return id;
}

/// How many check-ins / check-outs are saved on the phone waiting for a connection.
final pendingAttendanceProvider = StateProvider<int>((ref) => 0);

/// Check-in / check-out taken without a connection. They are saved with the moment they happened and sent
/// later; the server records them at that moment (and marks them as synced offline).
class OfflineAttendance {
  static const _key = 'offline_attendance_v1';

  static Future<List<Map<String, dynamic>>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(items));
    }
  }

  static Future<bool> has(String type) async => (await load()).any((e) => e['type'] == type);

  /// [type] is `check-in` or `check-out`; [evidence] is the position / Wi-Fi / phone id gathered at that moment.
  static Future<int> add(String type, Map<String, dynamic> evidence) async {
    final items = await load();
    items.add({'type': type, 'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'evidence': evidence});
    await _save(items);
    return items.length;
  }

  /// Send everything that is waiting. Stops quietly while the connection is still down.
  /// Returns how many were sent and the first message the server refused with (so the user can be told).
  static Future<({int sent, String? error, int left})> sync(Api api) async {
    final items = await load();
    if (items.isEmpty) return (sent: 0, error: null, left: 0);
    items.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    var sent = 0;
    String? error;
    final keep = <Map<String, dynamic>>[];
    var offline = false;
    for (final it in items) {
      if (offline) {
        keep.add(it);
        continue;
      }
      try {
        await api.post('/attendance/${it['type']}', {...Map<String, dynamic>.from(it['evidence'] as Map), 'clientTs': it['ts']});
        sent++;
      } on ApiException catch (e) {
        if (e.isNetwork || (e.status ?? 0) >= 500) {
          offline = true; // still no connection: try again later
          keep.add(it);
        } else if (e.status != 409) {
          error ??= e.message; // the server refused it for good (e.g. too old): tell the user once
        } // 409 = already recorded, nothing to do
      }
    }
    await _save(keep);
    return (sent: sent, error: error, left: keep.length);
  }
}
