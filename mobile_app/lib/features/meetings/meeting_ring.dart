import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';
import '../../core/desktop/desktop_service.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/push/notification_route.dart';
import '../../core/push/push_service.dart';
import '../../core/session/session.dart';
import 'meeting_session.dart';

const _ringChannel = MethodChannel('alanad/ring');
final bool _androidRing = !kIsWeb && Platform.isAndroid;

class _Ring {
  final int id;
  final String title;
  final String host;
  const _Ring(this.id, this.title, this.host);
}

/// Wraps the whole app:
///  - RINGS when a meeting you are invited to is due (full-screen "incoming meeting" with sound and vibration,
///    Join / Decline) - on the phone and on the laptop;
///  - opens the right screen when a system notification is tapped.
/// The server decides who is rung (invited, not the host, not already in the call, not declined); the app asks every 4 s.
class AppEventsHost extends ConsumerStatefulWidget {
  final Widget child;
  const AppEventsHost({super.key, required this.child});

  @override
  ConsumerState<AppEventsHost> createState() => _AppEventsHostState();
}

class _AppEventsHostState extends ConsumerState<AppEventsHost> {
  Timer? _poll;
  Timer? _beep;
  _Ring? _ring;
  final Set<int> _handled = {};
  bool _launchChecked = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    if (DesktopService.on) {
      DesktopService.onBalloonClick = _onBalloonClick;
      DesktopService.onPopupAction = _onPopupAction;
      _notifPoll = Timer.periodic(const Duration(seconds: 15), (_) => _checkLaptopNotifications());
    }
    PushService.onTap = _onNotificationTap;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _notifPoll?.cancel();
    _beep?.cancel();
    if (DesktopService.on) {
      DesktopService.stopRing();
      DesktopService.hidePopup();
      DesktopService.onBalloonClick = null;
      DesktopService.onPopupAction = null;
    }
    if (PushService.onTap == _onNotificationTap) PushService.onTap = null;
    super.dispose();
  }

  // ---------------------------------------------------------------- notification taps

  void _go(String to) {
    final router = ref.read(routerProvider);
    (to.startsWith('/e/') || to.startsWith('/h/')) ? router.go(to) : router.push(to);
  }

  void _onNotificationTap(Map<String, dynamic> p) {
    final s = ref.read(sessionProvider);
    if (!s.isSignedIn) return;
    _go(routeForNotification(type: '${p['type'] ?? ''}', data: p['data'] is Map ? p['data'] as Map : null, hr: s.user!.isHr));
  }

  // ------------------------------------------------------------------------- ringing

  Future<void> _check() async {
    if (!mounted) return;
    final s = ref.read(sessionProvider);
    if (!s.isSignedIn) {
      _stopRing();
      _syncWatcher(null);
      return;
    }
    _syncWatcher(ref.read(apiProvider).token);
    if (!_launchChecked) {
      _launchChecked = true;
      final tap = await PushService.takeLaunchTap();
      if (tap != null && mounted) _onNotificationTap(tap);
    }
    final inCall = ref.read(meetingHostProvider).current;
    if (inCall != null && !inCall.over) {
      _stopRing();
      return;
    }
    try {
      final data = await ref.read(apiProvider).get('/meetings/ring');
      if (!mounted) return;
      final list = data is List ? data.whereType<Map>().map((e) => asMap(e)).toList() : <Map<String, dynamic>>[];
      final fresh = list.where((m) => !_handled.contains(jInt(m, 'id'))).toList();
      if (fresh.isEmpty) {
        _stopRing();
        return;
      }
      final m = fresh.first;
      final id = jInt(m, 'id');
      if (_ring?.id != id) _startRing(_Ring(id, jStr(m, 'title'), jStr(m, 'hostName')));
    } catch (_) {
      // a missed check is fine, the next one comes in 4 seconds
    }
  }

  String? _watchedToken;

  /// Android: a small background service keeps watching for meeting calls when the app is closed, so the phone still rings.
  /// It gets the current sign-in here and forgets it on sign-out.
  Future<void> _syncWatcher(String? token) async {
    if (DesktopService.on && token != _watchedToken) {
      // Laptop: start with Windows (hidden in the tray) so meetings can ring after a restart; forget notifications on sign-out.
      _watchedToken = token;
      if (token == null) {
        DesktopService.forget();
        DesktopService.stopRing();
      } else {
        DesktopService.setAutoStart(true);
      }
      return;
    }
    if (!_androidRing || token == _watchedToken) return;
    _watchedToken = token;
    try {
      if (token == null) {
        await _ringChannel.invokeMethod('unwatch');
        return;
      }
      await _ringChannel.invokeMethod('watch', {'base': AppConfig.baseUrl, 'token': token, 'appId': AppConfig.appId});
      // once: ask Android not to put the app to sleep, otherwise some phones stop the watcher
      final sp = await SharedPreferences.getInstance();
      if (sp.getBool('battery_asked_v1') != true) {
        await sp.setBool('battery_asked_v1', true);
        await _ringChannel.invokeMethod('batteryExempt');
      }
    } catch (_) {
      _watchedToken = null; // try again at the next check
    }
  }

  void _startRing(_Ring r) {
    _beep?.cancel();
    setState(() => _ring = r);
    void tone() {
      // The phone's own ringtone loops (below) and the laptop has its own looping ring; elsewhere the system alert sound is used.
      if (!_androidRing && !DesktopService.on) SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }

    if (_androidRing) _ringChannel.invokeMethod('start').catchError((_) => false);
    if (DesktopService.on) _ringOnLaptop(r);
    tone();
    _beep = Timer.periodic(const Duration(milliseconds: 1600), (_) => tone());
  }

  /// Laptop: looping ring, and the window comes up in front (even from the tray) with a pop-up notification.
  Future<void> _ringOnLaptop(_Ring r) async {
    final focused = await DesktopService.isFocused();
    if (!mounted) return;
    // The app is closed to the tray, minimized or behind other windows: a card pops up in the top corner of the screen
    // (top-right, or top-left in Arabic) with Join / Decline. When the app is in front, its own ring screen is enough.
    if (!focused) {
      DesktopService.showPopup(
        header: context.t('meet.incoming'),
        title: r.title,
        sub: r.host.isEmpty ? '' : '${context.t('meet.host')}: ${r.host}',
        join: context.t('meet.join'),
        decline: context.t('meet.decline'),
        rtl: Directionality.of(context) == TextDirection.rtl,
      );
    }
    await DesktopService.startRing();
  }

  void _onPopupAction(String action) {
    if (_ring == null) return;
    if (action == 'decline') {
      _decline();
    } else {
      DesktopService.show();
      if (action == 'join') _join();
    }
  }

  // ----------------------------------------------------------------- laptop: new notifications while minimized / in the tray

  Timer? _notifPoll;
  Map<String, dynamic>? _lastBalloon;

  Future<void> _checkLaptopNotifications() async {
    if (!mounted || !ref.read(sessionProvider).isSignedIn) return;
    try {
      final shown = await DesktopService.checkNotifications(ref.read(apiProvider));
      if (shown != null) _lastBalloon = shown;
    } catch (_) {
      // the next check comes in 15 seconds
    }
  }

  void _onBalloonClick() {
    final p = _lastBalloon;
    _lastBalloon = null;
    if (p != null) _onNotificationTap(p);
  }

  void _stopRing() {
    if (DesktopService.on && _beep != null) {
      DesktopService.stopRing();
      DesktopService.hidePopup();
    }
    if (_androidRing && _beep != null) _ringChannel.invokeMethod('stop').catchError((_) => false);
    _beep?.cancel();
    _beep = null;
    if (_ring != null && mounted) setState(() => _ring = null);
  }

  void _join() {
    final r = _ring;
    if (r == null) return;
    _handled.add(r.id);
    _stopRing();
    ref.read(routerProvider).push('/meeting/${r.id}');
  }

  Future<void> _decline() async {
    final r = _ring;
    if (r == null) return;
    _handled.add(r.id);
    _stopRing();
    try {
      await ref.read(apiProvider).post('/meetings/${r.id}/dismiss');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final r = _ring;
    return Stack(children: [
      widget.child,
      if (r != null)
        Positioned.fill(
          child: Material(
            color: const Color(0xF2061B26),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const _Pulse(),
                      const SizedBox(height: 26),
                      Text(context.t('meet.incoming'), style: const TextStyle(color: Colors.white70, fontSize: 15)),
                      const SizedBox(height: 10),
                      Text(r.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                      if (r.host.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('${context.t('meet.host')}: ${r.host}', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                      ],
                      const SizedBox(height: 40),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        _RingBtn(icon: Icons.call_end_rounded, label: context.t('meet.decline'), color: Colors.redAccent, onTap: _decline),
                        _RingBtn(icon: Icons.videocam_rounded, label: context.t('meet.join'), color: context.colors.success, onTap: _join),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _RingBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _RingBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        InkResponse(onTap: onTap, child: CircleAvatar(radius: 36, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 32))),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ]);
}

/// A softly pulsing video icon.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: 110 + 18 * _c.value,
          height: 110 + 18 * _c.value,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10 + 0.08 * _c.value)),
          child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 54),
        ),
      );
}
