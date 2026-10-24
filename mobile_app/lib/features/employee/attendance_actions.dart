import '../../core/offline/offline_attendance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';
import '../rewards/reward_effects.dart';

/// What the phone can prove about where it is: GPS position and the Wi-Fi network it is on.
class Evidence {
  double? lat;
  double? lng;
  String? ssid;
  String? bssid;
  bool mock = false; // the phone says the location is faked
  String? deviceId;

  Map<String, dynamic> toJson() => {
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (ssid != null) 'ssid': ssid,
        if (bssid != null) 'bssid': bssid,
        if (mock) 'mock': true,
        if (deviceId != null) 'deviceId': deviceId,
      };
}

/// Collects position / Wi-Fi name when the company's attendance rule needs them.
/// Throws [ApiException] with a friendly message when something is missing.
Future<Evidence> gatherEvidence(TodayInfo info, {required String noPermission, required String gpsOff, required String noFix, bool quick = false}) async {
  final ev = Evidence()..deviceId = await phoneId();
  final needsLocation = info.locationRequired;
  final needsWifi = info.wifiRequired;
  if (!needsLocation && !needsWifi) return ev;

  // Location permission is needed for GPS and (on Android) to read the Wi-Fi name.
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied && !quick) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
    throw ApiException(noPermission);
  }

  if (needsLocation || needsWifi) {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (needsLocation) throw ApiException(gpsOff);
    }
  }
  if (needsLocation) {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: Duration(seconds: quick ? 12 : 20));
      ev.lat = pos.latitude;
      ev.lng = pos.longitude;
      ev.mock = pos.isMocked;
    } catch (_) {
      final last = quick ? await Geolocator.getLastKnownPosition() : null;
      if (last == null) throw ApiException(noFix);
      ev.lat = last.latitude;
      ev.lng = last.longitude;
      ev.mock = last.isMocked;
    }
  }
  if (needsWifi) {
    if (!quick) await Permission.nearbyWifiDevices.request();
    final info = NetworkInfo();
    ev.ssid = (await info.getWifiName())?.replaceAll('"', '');
    ev.bssid = await info.getWifiBSSID();
  }
  return ev;
}

/// Check in or out. Returns the server's record on success (with today's reward after a check-out).
/// Errors are shown as toasts and null is returned.
Future<AttendanceRecord?> performAttendance(BuildContext context, WidgetRef ref, TodayInfo info, {required bool checkOut}) async {
  final noPermission = context.t('time.err.permission');
  final gpsOff = context.t('time.err.gps_off');
  final noFix = context.t('time.err.no_fix');
  final okOut = context.t('time.checked_out_ok');
  final offlineSaved = context.t('offline.saved');
  final offlineAlready = context.t('offline.already');
  final dayTexts = {for (final k in ['late', 'half_day', 'absent']) k: context.t('time.day_result.$k')};
  String resultText(AttendanceRecord r) {
    switch (r.status) {
      case 'late':
        return context.t('time.result.late', {'n': r.lateMinutes});
      case 'half_day':
        return context.t('time.result.half_day');
      case 'absent':
        return context.t('time.result.absent');
      default:
        return context.t('time.result.present');
    }
  }

  void say(String m, {bool error = false}) {
    if (context.mounted) toast(context, m, error: error);
  }

  Evidence? ev;
  try {
    ev = await gatherEvidence(info, noPermission: noPermission, gpsOff: gpsOff, noFix: noFix);
    final data = await ref.read(apiProvider).post(checkOut ? '/attendance/check-out' : '/attendance/check-in', ev.toJson());
    final rec = AttendanceRecord.fromJson(data);
    ref.invalidate(todayProvider);
    ref.invalidate(myStatsProvider);
    ref.invalidate(attendanceSummaryProvider);
    ref.invalidate(myPointsProvider);
    if (checkOut) {
      say(rec.status == 'present' ? okOut : '$okOut\n${dayTexts[rec.status] ?? ''}');
      final pointsOn = ref.read(sessionProvider).company?.pointsEnabled ?? true;
      if (pointsOn && rec.reward != null && rec.reward!.color != 'none' && context.mounted) {
        await showRewardCelebration(context, rec.reward!);
      }
    } else {
      say(resultText(rec), error: rec.status != 'present');
    }
    return rec;
  } on ApiException catch (e) {
    // No connection: keep the action on the phone with the moment it happened and send it when we are online again.
    if (e.isNetwork && ev != null) {
      final type = checkOut ? 'check-out' : 'check-in';
      if (await OfflineAttendance.has(type)) {
        say(offlineAlready);
        return null;
      }
      final n = await OfflineAttendance.add(type, ev.toJson());
      ref.read(pendingAttendanceProvider.notifier).state = n;
      say(offlineSaved);
      return null;
    }
    say(e.message, error: true);
    return null;
  }
}
