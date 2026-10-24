import '../../core/ui/widgets.dart';
import '../../core/offline/offline_attendance.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/push/background_ping.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../data/providers.dart';
import 'attendance_actions.dart';

/// Where the server last saw the employee while they are checked in.
class ZoneStatus {
  final bool inside;
  final int outMinutes;
  final int? distanceM;
  final String? message;
  final String status; // the day's status after this check
  final String? error; // 'permission' | 'gps' | 'fix' | 'network'
  final DateTime at;
  const ZoneStatus({this.inside = true, this.outMinutes = 0, this.distanceM, this.message, this.status = 'present', this.error, required this.at});
}

final zoneStatusProvider = StateProvider<ZoneStatus?>((ref) => null);

/// Sits around the employee app. While someone is checked in under a location / Wi-Fi rule it sends a
/// heartbeat every few minutes (and when the app comes back to the front) so the server can tell when
/// they leave the workplace and work out the day's status automatically.
class LocationTracker extends ConsumerStatefulWidget {
  final Widget child;
  const LocationTracker({super.key, required this.child});

  @override
  ConsumerState<LocationTracker> createState() => _LocationTrackerState();
}

class _LocationTrackerState extends ConsumerState<LocationTracker> with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _offlineTimer;
  int _intervalMin = 0;
  bool _busy = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OfflineAttendance.load().then((l) {
      if (mounted) ref.read(pendingAttendanceProvider.notifier).state = l.length;
    });
    _offlineTimer = Timer.periodic(const Duration(seconds: 45), (_) => _syncOffline());
  }

  /// Send check-ins / check-outs that were saved while the phone had no connection.
  Future<void> _syncOffline() async {
    if (_syncing || !mounted) return;
    _syncing = true;
    try {
      if ((await OfflineAttendance.load()).isEmpty) {
        if (mounted && ref.read(pendingAttendanceProvider) != 0) ref.read(pendingAttendanceProvider.notifier).state = 0;
        return;
      }
      final r = await OfflineAttendance.sync(ref.read(apiProvider));
      if (!mounted) return;
      ref.read(pendingAttendanceProvider.notifier).state = r.left;
      if (r.sent > 0) {
        ref.invalidate(todayProvider);
        ref.invalidate(myStatsProvider);
        ref.invalidate(attendanceSummaryProvider);
        toast(context, context.t('offline.synced', {'n': r.sent}));
      }
      if (r.error != null) toast(context, r.error!, error: true);
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineTimer?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncOffline();
      if (_timer != null) _ping();
    }
  }

  void _sync(TodayInfo? info) {
    final shouldRun = info != null && info.state == 'checked_in' && info.hasZoneRule && info.trackLocation;
    if (!shouldRun) {
      BackgroundPing.stop();
      _timer?.cancel();
      _timer = null;
      _intervalMin = 0;
      if (ref.read(zoneStatusProvider) != null) Future.microtask(() => ref.read(zoneStatusProvider.notifier).state = null);
      return;
    }
    final every = info.pingIntervalMinutes.clamp(1, 60);
    if (_timer == null || _intervalMin != every) {
      _timer?.cancel();
      _intervalMin = every;
      BackgroundPing.start();       // keep going when the app is closed
      _timer = Timer.periodic(Duration(minutes: every), (_) => _ping());
      Future.delayed(const Duration(seconds: 2), _ping);
    }
  }

  Future<void> _ping() async {
    if (_busy || !mounted) return;
    final info = ref.read(todayProvider).valueOrNull;
    if (info == null || info.state != 'checked_in') return;
    _busy = true;
    // capture texts before any await
    final np = context.t('time.err.permission');
    final go = context.t('time.err.gps_off');
    final nf = context.t('time.err.no_fix');
    try {
      final ev = await gatherEvidence(info, noPermission: np, gpsOff: go, noFix: nf, quick: true);
      final m = asMap(await ref.read(apiProvider).post('/attendance/ping', ev.toJson()));
      if (jStr(m, 'state') == 'open') {
        final before = ref.read(zoneStatusProvider);
        final z = ZoneStatus(
          inside: jBool(m, 'inside', true),
          outMinutes: jInt(m, 'outZoneMinutes'),
          distanceM: jIntN(m, 'distanceM'),
          message: jStrN(m, 'message'),
          status: jStr(m, 'status', 'present'),
          at: DateTime.now(),
        );
        ref.read(zoneStatusProvider.notifier).state = z;
        if (before == null || before.status != z.status) {
          ref.invalidate(todayProvider);
          ref.invalidate(myStatsProvider);
        }
      } else {
        ref.invalidate(todayProvider);
      }
    } on ApiException catch (e) {
      final code = e.message == np ? 'permission' : (e.message == go ? 'gps' : (e.message == nf ? 'fix' : 'network'));
      ref.read(zoneStatusProvider.notifier).state = ZoneStatus(error: code, message: e.message, at: DateTime.now());
    } catch (_) {
      // a failed heartbeat is retried on the next tick
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<TodayInfo>>(todayProvider, (_, next) => _sync(next.valueOrNull));
    // also handle the very first value
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _timer == null) _sync(ref.read(todayProvider).valueOrNull);
    });
    return widget.child;
  }
}
