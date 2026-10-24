import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/ui/widgets.dart';
import 'meeting_models.dart';
import 'meeting_present.dart';
import 'meeting_session.dart';

const _bg = Color(0xFF0B1220);

/// Pop when there is somewhere to go back to; otherwise (opened from a notification) land on the meetings list.
void _back(BuildContext context) => context.canPop() ? context.pop() : context.go('/meetings');
const _tileBg = Color(0xFF16213A);

/// The call screen. Leaving it with the back arrow only "minimises": the call itself lives in [MeetingSession] (app level)
/// and keeps going until the person presses Leave or the meeting ends.
class MeetingRoomScreen extends ConsumerStatefulWidget {
  final int id;
  const MeetingRoomScreen({super.key, required this.id});

  @override
  ConsumerState<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends ConsumerState<MeetingRoomScreen> {
  Timer? _clock;
  final Map<int, String> _traffic = {};
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 2), (_) => _refreshTraffic());
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _refreshTraffic() async {
    final call = ref.read(meetingHostProvider).current?.call;
    if (call == null || !mounted) return;
    final next = <int, String>{};
    for (final id in call.peers.keys) {
      final t = await call.traffic(id);
      final frames = call.peers[id]?.videoFrames ?? 0;
      next[id] = '↓${(t.received / 1024).round()} KB  ↑${(t.sent / 1024).round()} KB${frames > 0 ? '  ▶$frames' : ''}';
    }
    if (mounted) {
      setState(() => _traffic
        ..clear()
        ..addAll(next));
    }
  }

  void _enter(Meeting m) {
    if (_entered) return;
    _entered = true;
    final ok = ref.read(meetingHostProvider).enter(m);
    if (!ok) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        toast(context, context.t('meet.already_in'), error: true);
        _back(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(meetingHostProvider);
    final meeting = ref.watch(meetingProvider(widget.id));
    final session = host.current?.meeting.id == widget.id ? host.current : null;

    if (session == null) {
      return meeting.when(
        data: (m) {
          // an old / cancelled / not-yet-open meeting (e.g. from an old notification): say so instead of trying to join
          if (m.isOver) return _Centered(text: m.status == 'cancelled' ? context.t('meet.cancelled') : context.t('meet.ended'), icon: Icons.call_end_rounded, onBack: () => _back(context));
          if (!m.canJoin) return _Centered(text: context.t('meet.not_yet'), icon: Icons.schedule_rounded, onBack: () => _back(context));
          WidgetsBinding.instance.addPostFrameCallback((_) => _enter(m));
          return _Centered(text: context.t('meet.joining'), busy: true);
        },
        loading: () => _Centered(text: context.t('meet.joining'), busy: true),
        error: (e, _) => _Centered(text: '$e', onBack: () => _back(context)),
      );
    }
    if (session.joining) return _Centered(text: context.t('meet.joining'), busy: true);
    if (session.error != null) {
      return _Centered(text: session.error!, onBack: () {
        host.clearOver();
        _back(context);
      });
    }
    if (session.over) {
      return _Centered(
        text: session.removed ? context.t('meet.you_removed') : context.t('meet.ended'),
        icon: Icons.call_end_rounded,
        onBack: () {
          host.clearOver();
          _back(context);
        },
      );
    }
    return _Room(session: session, traffic: _traffic);
  }
}

class _Centered extends StatelessWidget {
  final String text;
  final bool busy;
  final IconData? icon;
  final VoidCallback? onBack;
  const _Centered({required this.text, this.busy = false, this.icon, this.onBack});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(backgroundColor: _bg, foregroundColor: Colors.white, leading: BackButton(onPressed: onBack ?? () => _back(context))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (busy) const CircularProgressIndicator(color: Colors.white) else Icon(icon ?? Icons.error_outline_rounded, color: Colors.white70, size: 44),
              const SizedBox(height: 18),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
              if (onBack != null) ...[
                const SizedBox(height: 22),
                FilledButton(onPressed: onBack, child: Text(context.t('meet.back'))),
              ],
            ]),
          ),
        ),
      );
}

class _Room extends ConsumerWidget {
  final MeetingSession session;
  final Map<int, String> traffic;
  const _Room({required this.session, required this.traffic});

  String _timer() {
    final s = DateTime.now().difference(session.joinedAt ?? DateTime.now()).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = session.call!;
    final peers = call.peers.values.toList()..sort((a, b) => a.userId.compareTo(b.userId));
    final tiles = <Widget>[
      _Tile(name: '${session.nameOf(session.myId)} (${context.t('meet.you')})', avatarName: session.nameOf(session.myId), renderer: call.localRenderer, showVideo: call.camOn && call.hasCamera, micOn: call.micOn, mirror: true),
      for (final p in peers)
        _Tile(
          name: session.nameOf(p.userId),
          renderer: p.renderer,
          showVideo: p.hasVideo && p.camOn && p.rendererReady,
          micOn: p.micOn,
          state: p.state,
          info: traffic[p.userId],
        ),
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        leading: IconButton(tooltip: context.t('meet.minimise'), icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30), onPressed: () => _back(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(session.meeting.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text('${_timer()} · ${context.t('meet.people_n', {'n': session.present.length})}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [IconButton(icon: const Icon(Icons.people_alt_rounded), onPressed: () => showAppSheet(context, title: context.t('meet.people'), child: _PeopleList(session: session)))],
      ),
      body: Column(children: [
        if (call.mediaError != null)
          Container(width: double.infinity, color: const Color(0xFF7C2D12), padding: const EdgeInsets.all(10), child: Text(context.t('meet.no_mic'), style: const TextStyle(color: Colors.white, fontSize: 12.5))),
        if (session.present_?.presenting ?? false)
          Container(
            width: double.infinity,
            color: const Color(0xFF0C4A6E),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              const Icon(Icons.screen_share_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(context.t('meet.you_share'), style: const TextStyle(color: Colors.white, fontSize: 13))),
              TextButton(onPressed: () => session.present_!.stopPresenting(), child: Text(context.t('meet.stop_share'), style: const TextStyle(color: Colors.white))),
            ]),
          ),
        if (session.present_?.watching ?? false)
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                RTCVideoView(session.present_!.renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
                Positioned(
                  left: 10,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                    child: Text(context.t('meet.sharing', {'name': session.nameOf(session.present_!.presenterId ?? 0)}), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ]),
            ),
          ),
        Expanded(
          flex: (session.present_?.watching ?? false) ? 2 : 1,
          child: LayoutBuilder(builder: (context, c) {
            final n = tiles.length;
            final wide = c.maxWidth > c.maxHeight;
            final cols = n <= 1 ? 1 : (wide ? (n <= 4 ? 2 : 3) : (n <= 2 ? 1 : 2));
            final rows = (n / cols).ceil();
            final w = (c.maxWidth - 8 * (cols + 1)) / cols;
            final h = (c.maxHeight - 8 * (rows + 1)) / rows;
            return GridView.count(
              padding: const EdgeInsets.all(8),
              crossAxisCount: cols,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: w / (h <= 0 ? 1 : h),
              physics: const NeverScrollableScrollPhysics(),
              children: tiles,
            );
          }),
        ),
        if (peers.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(context.t('meet.waiting'), style: const TextStyle(color: Colors.white70))),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _RoundBtn(icon: call.micOn ? Icons.mic_rounded : Icons.mic_off_rounded, label: context.t('meet.mic'), active: call.micOn, onTap: call.hasMic ? () => call.setMic(!call.micOn) : null),
              const SizedBox(width: 14),
              _RoundBtn(icon: call.camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded, label: context.t('meet.cam'), active: call.camOn, onTap: call.hasCamera ? () => call.setCam(!call.camOn) : null),
              const SizedBox(width: 14),
              if (PresentationHub.canShare && session.present_ != null) ...[
                _RoundBtn(
                  icon: session.present_!.presenting ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
                  label: session.present_!.presenting ? context.t('meet.stop_share') : context.t('meet.share'),
                  active: !session.present_!.presenting,
                  onTap: session.present_!.watching && !session.present_!.presenting
                      ? null // somebody else is sharing: one presenter at a time
                      : () => session.present_!.presenting ? session.present_!.stopPresenting() : session.present_!.startPresenting(session.present, session.myId),
                ),
                const SizedBox(width: 14),
              ],
              _RoundBtn(icon: Icons.call_end_rounded, label: context.t('meet.leave'), danger: true, onTap: () => _leave(context, ref)),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final host = ref.read(meetingHostProvider);
    final router = GoRouter.of(context);
    var endAll = false;
    if (session.isHost) {
      endAll = await confirmDialog(context, title: context.t('meet.end_all'), message: context.t('meet.end_all_q'), confirmLabel: context.t('meet.end_all'), danger: true);
    }
    await host.leaveCurrent(endForAll: endAll);
    router.canPop() ? router.pop() : router.go('/meetings');
  }
}

class _Tile extends StatelessWidget {
  final String name;
  final String? avatarName; // the name without the "(You)" suffix, for the initials
  final RTCVideoRenderer renderer;
  final bool showVideo;
  final bool micOn;
  final bool mirror;
  final String? state;
  final String? info;
  const _Tile({required this.name, this.avatarName, required this.renderer, required this.showVideo, required this.micOn, this.mirror = false, this.state, this.info});

  @override
  Widget build(BuildContext context) {
    final failed = state == 'failed';
    final connecting = state == 'connecting';
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: _tileBg,
        child: Stack(fit: StackFit.expand, children: [
          if (showVideo)
            RTCVideoView(renderer, mirror: mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            Center(child: Avatar(name: (avatarName ?? name).isEmpty ? '?' : (avatarName ?? name), size: 72)),
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Row(children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                  child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                ),
              ),
              if (!micOn) ...[const SizedBox(width: 6), const Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 18)],
            ]),
          ),
          if (connecting || failed)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: failed ? Colors.redAccent : Colors.black54, borderRadius: BorderRadius.circular(10)),
                child: Text(failed ? context.t('meet.failed') : context.t('meet.connecting'), style: const TextStyle(color: Colors.white, fontSize: 11.5)),
              ),
            ),
          if (info != null && !connecting && !failed)
            Positioned(top: 8, right: 8, child: Text(info!, style: const TextStyle(color: Colors.white38, fontSize: 10.5))),
        ]),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool danger;
  final VoidCallback? onTap;
  const _RoundBtn({required this.icon, required this.label, this.active = true, this.danger = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = danger ? Colors.redAccent : (active ? Colors.white24 : Colors.white);
    final fg = danger ? Colors.white : (active ? Colors.white : Colors.black87);
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        InkResponse(
          onTap: onTap,
          child: CircleAvatar(radius: 28, backgroundColor: bg, child: Icon(icon, color: fg)),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }
}

class _PeopleList extends ConsumerWidget {
  final MeetingSession session;
  const _PeopleList({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = session.meeting.active;
    return Column(children: [
      for (final p in people)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Stack(children: [
            Avatar(name: p.name, size: 38),
            Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 6, backgroundColor: session.present.contains(p.userId) ? Colors.green : Colors.grey)),
          ]),
          title: Text(p.userId == session.myId ? '${p.name} (${context.t('meet.you')})' : p.name),
          subtitle: p.isHost ? Text(context.t('meet.host')) : null,
          trailing: session.isHost && !p.isHost && p.userId != session.myId
              ? IconButton(
                  tooltip: context.t('meet.remove'),
                  icon: Icon(Icons.person_remove_rounded, color: context.colors.danger),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final err = await session.kick(p);
                    if (!context.mounted) return;
                    toast(context, err ?? context.t('meet.removed_toast', {'name': p.name}), error: err != null);
                    nav.pop();
                  },
                )
              : null,
        ),
    ]);
  }
}
