import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import 'background_ping.dart';

const _taskName = 'nexus.notifications.check';
const _lastKey = 'push_last_id';
const _enabledKey = 'push_enabled';
const _tokenKey = 'session_token_v2'; // same key the session notifier writes

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;

/// A notification was tapped (app running or in the background). Null in the background worker.
void _onTapped(NotificationResponse r) => PushService._deliver(r.payload);

/// Entry point of the background worker (Android WorkManager, about every 15 minutes).
@pragma('vm:entry-point')
void pushCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      if (task == locationTaskName) {
        await BackgroundPing.run();
      } else {
        await PushService.check();
      }
    } catch (_) {/* try again next time */}
    return true;
  });
}

/// System notifications for new in-app notifications, even when the app is closed.
///
/// There is no Google push service behind this (that would need a Firebase project), so the phone
/// asks the server for anything new: every minute while the app is open and about every 15 minutes
/// in the background.
List _items(dynamic data) {
  final raw = data is String ? jsonDecode(data) : data;
  return (raw is Map ? (raw['items'] ?? (raw['data'] is Map ? raw['data']['items'] : null)) : null) as List? ?? const [];
}

class PushService {
  /// Set by the app: opens the screen a tapped notification points to. {type, data}
  static void Function(Map<String, dynamic> payload)? onTap;
  static Map<String, dynamic>? _pending; // tapped before the app was ready (cold start)
  static bool _launchTapTaken = false;

  static void _deliver(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final m = (jsonDecode(payload) as Map).cast<String, dynamic>();
      if (onTap != null) {
        onTap!(m);
      } else {
        _pending = m;
      }
    } catch (_) {}
  }

  /// The app was opened by tapping a notification: returns it once (call after sign-in).
  static Future<Map<String, dynamic>?> takeLaunchTap() async {
    if (kIsWeb || !Platform.isAndroid || _launchTapTaken) return null;
    _launchTapTaken = true;
    final p = _pending;
    _pending = null;
    if (p != null) return p;
    try {
      await _ensure();
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp == true && d?.notificationResponse?.payload != null) {
        final m = (jsonDecode(d!.notificationResponse!.payload!) as Map).cast<String, dynamic>();
        return m;
      }
    } catch (_) {}
    return null;
  }

  /// The user's own switch (Settings → Notifications). On by default.
  static Future<bool> isEnabled() async => (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? true;

  static Future<void> setEnabled(bool on) async {
    (await SharedPreferences.getInstance()).setBool(_enabledKey, on);
    if (on) {
      await enable();
    } else {
      try {
        await Workmanager().cancelByUniqueName('nexus-notifications');
        await _plugin.cancelAll();
      } catch (_) {}
    }
  }

  static Future<void> _ensure() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(settings: const InitializationSettings(android: android), onDidReceiveNotificationResponse: _onTapped);
    _ready = true;
  }

  /// Call once from main().
  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _ensure();
      await Workmanager().initialize(pushCallbackDispatcher);
    } catch (e) {
      debugPrint('push init: $e');
    }
  }

  /// Ask for permission (Android 13+) and start the background check. Call after sign-in.
  static Future<void> enable() async {
    if (kIsWeb || !Platform.isAndroid || !await isEnabled()) return;
    try {
      await _ensure();
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await check();      // sets the baseline on a fresh install
      await Workmanager().registerPeriodicTask(
        'nexus-notifications',
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (e) {
      debugPrint('push enable: $e');
    }
  }

  /// Stop checking and forget what was shown (sign-out).
  static Future<void> disable() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName('nexus-notifications');
      await _plugin.cancelAll();
      (await SharedPreferences.getInstance()).remove(_lastKey);
    } catch (_) {}
  }

  /// Fetch anything newer than the last one shown and show it. Returns how many were shown.
  static Future<int> check() async {
    if (kIsWeb || !Platform.isAndroid) return 0;
    if (!await isEnabled()) return 0;
    final token = await const FlutterSecureStorage().read(key: _tokenKey);
    if (token == null || token.isEmpty) return 0;
    await _ensure();
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastKey);

    final dio = Dio(BaseOptions(
      baseUrl: '${AppConfig.baseUrl}/api',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      validateStatus: (_) => true,
    ));
    // First run on this phone: remember where we are so old items do not flood the shade.
    if (last == null) {
      final r0 = await dio.get('/notifications', queryParameters: {'limit': 1});
      if ((r0.statusCode ?? 0) != 200) return 0;
      final items0 = _items(r0.data);
      final id0 = items0.isEmpty ? 0 : (int.tryParse('${(items0.first as Map)['id']}') ?? 0);
      await prefs.setInt(_lastKey, id0);
      return 0;
    }

    final res = await dio.get('/notifications', queryParameters: {'unread': 1, 'limit': 20, 'after': last});
    if ((res.statusCode ?? 0) != 200) return 0;
    final items = _items(res.data);
    final ids = <int>[for (final i in items) if (i is Map && i['id'] != null) int.tryParse('${i['id']}') ?? 0];
    if (ids.isEmpty) return 0;
    final newest = ids.reduce((a, b) => a > b ? a : b);

    var shown = 0;
    for (final i in items.reversed) {
      if (i is! Map) continue;
      final id = int.tryParse('${i['id']}') ?? 0;
      if (id <= last) continue;
      await _plugin.show(
        id: id,
        title: '${i['title'] ?? 'Al Anad HR'}',
        body: i['body']?.toString(),
        payload: jsonEncode({'type': '${i['type'] ?? ''}', 'data': i['data'] is Map ? i['data'] : {}}),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'nexus_updates',
            'Updates',
            channelDescription: 'Approvals, requests, points and announcements',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(''),
          ),
        ),
      );
      shown++;
    }
    await prefs.setInt(_lastKey, newest);
    return shown;
  }
}
