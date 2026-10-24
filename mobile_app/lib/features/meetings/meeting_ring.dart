import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/push/notification_route.dart';
import '../../core/push/push_service.dart';
import '../../core/session/session.dart';
import 'meeting_session.dart';

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
    PushService.onTap = _onNotificationTap;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _beep?.cancel();
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
      return;
    }
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

  void _startRing(_Ring r) {
    _beep?.cancel();
    setState(() => _ring = r);
    void tone() {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }

    tone();
    _beep = Timer.periodic(const Duration(milliseconds: 1600), (_) => tone());
  }

  void _stopRing() {
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
