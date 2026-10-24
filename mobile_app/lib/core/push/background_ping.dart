import '../offline/offline_attendance.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import '../models/models.dart';

const locationTaskName = 'nexus.location.ping';
const _uniqueName = 'nexus-location';
const _askedKey = 'bg_location_asked';

/// Keeps the "am I at work?" heartbeat going while the app is closed.
///
/// Android lets a background job run about every 15 minutes. The server counts the gap between two
/// heartbeats as time inside / outside the work zone (capped by its own maximum gap, 30 minutes by
/// default), so this is enough to notice someone who walked away from the workplace.
class BackgroundPing {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Start while the employee is checked in under a location / Wi-Fi rule.
  /// Asks (once) for "Allow all the time" so the job may read the position with the app closed.
  static Future<void> start() async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) != true) {
        await prefs.setBool(_askedKey, true);
        if (await Permission.location.isGranted) await Permission.locationAlways.request();
      }
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        locationTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('background ping start: $e');
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await Workmanager().cancelByUniqueName(_uniqueName);
    } catch (_) {}
  }

  /// One heartbeat, run by the background worker. Cancels itself when the day is no longer open.
  static Future<void> run() async {
    final token = await const FlutterSecureStorage().read(key: 'session_token_v2');
    if (token == null || token.isEmpty) return stop();

    final dio = Dio(BaseOptions(
      baseUrl: '${AppConfig.baseUrl}/api',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      validateStatus: (_) => true,
    ));

    final r = await dio.get('/attendance/today');
    if ((r.statusCode ?? 0) == 401) return stop();
    if ((r.statusCode ?? 0) != 200) return;
    final info = TodayInfo.fromJson(r.data is String ? jsonDecode(r.data as String) : r.data);
    if (info.state != 'checked_in' || !info.hasZoneRule || !info.trackLocation) return stop();

    final body = <String, dynamic>{'deviceId': await phoneId()};
    if (info.locationRequired) {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 20));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return;
      body['lat'] = pos.latitude;
      body['lng'] = pos.longitude;
      if (pos.isMocked) body['mock'] = true;
    }
    if (info.wifiRequired) {
      final ni = NetworkInfo();
      body['ssid'] = (await ni.getWifiName())?.replaceAll('"', '');
      body['bssid'] = await ni.getWifiBSSID();
    }
    await dio.post('/attendance/ping', data: body);
  }
}
