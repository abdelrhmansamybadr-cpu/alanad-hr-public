import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// What the call needs from the server: send a call-setup message to one person.
/// (The real one talks to /meetings/{id}/signal; the tests plug in an in-memory one.)
abstract class MeetingTransport {
  Future<void> send(int to, String type, String payload);
}

/// One call-setup message that was sent to me (read from /meetings/{id}/poll).
class IncomingSignal {
  final int id;
  final int from;
  final String type;
  final String? payload;
  const IncomingSignal({required this.id, required this.from, required this.type, required this.payload});
}

/// One other person in the call.
class CallPeer {
  final int userId;
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  RTCDataChannel? channel;
  String sid = '';
  String state = 'connecting'; // connecting | connected | failed
  bool micOn = true;
  bool camOn = false;
  bool hasVideo = false;
  bool rendererReady = false;
  /// video frames decoded from this person so far (> 0 = their picture really arrives)
  int videoFrames = 0;
  final List<RTCIceCandidate> pendingIce = [];
  bool remoteSet = false;

  CallPeer(this.userId);
}

/// The audio / video call of a meeting: a direct connection (WebRTC) from this device to every other person present.
/// The server only passes the small set-up messages, never the media, so it costs nothing to run.
/// The person with the LOWER user id always makes the offer, so two people never offer at the same time.
/// The website (React) speaks exactly the same protocol, so phone, laptop and browser can be in one call.
class MeetingCall extends ChangeNotifier {
  MeetingCall({
    required this.myId,
    required this.transport,
    this.iceServers = const [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    this.getLocalMedia,
    this.onOther,
  });

  final int myId;
  final MeetingTransport transport;
  final List<Map<String, dynamic>> iceServers;

  /// Replaced in tests (no microphone there). Returns null when there is no media - the call still connects.
  final Future<MediaStream?> Function()? getLocalMedia;

  /// Set-up messages that are not about the call itself (screen sharing: present.*).
  final void Function(IncomingSignal signal)? onOther;

  MediaStream? local;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final Map<int, CallPeer> peers = {};
  bool micOn = true;
  bool camOn = false;
  bool hasCamera = false;
  bool hasMic = false;
  /// 'denied' (permission refused / no device) - shown by the screen; the call still works (listen only).
  String? mediaError;
  bool _disposed = false;
  bool _localRendererReady = false;
  final _rng = Random.secure();

  Future<void> start() async {
    await localRenderer.initialize();
    _localRendererReady = true;
    try {
      local = await (getLocalMedia ?? _defaultMedia)();
    } catch (e) {
      mediaError = 'denied';
    }
    final s = local;
    if (s != null) {
      hasCamera = s.getVideoTracks().isNotEmpty;
      hasMic = s.getAudioTracks().isNotEmpty;
      // the camera starts off - turning it on later is just enabling the track (no new negotiation)
      for (final t in s.getVideoTracks()) {
        t.enabled = false;
      }
      localRenderer.srcObject = s;
    } else {
      mediaError ??= 'denied';
    }
    _notify();
  }

  static Future<MediaStream?> _defaultMedia() async {
    try {
      return await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': {'width': 640, 'height': 360, 'frameRate': 24},
      });
    } catch (_) {
      // no camera (or it was refused): audio only
      return await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── presence: who must be connected ────────────────────────────────────────────

  /// Called with everyone present on every poll: connects to newcomers, drops the ones who left.
  Future<void> syncPresence(Set<int> present) async {
    if (_disposed) return;
    for (final id in present) {
      if (id == myId || peers.containsKey(id)) continue;
      final p = CallPeer(id);
      peers[id] = p;
      await _createConnection(p);
      if (myId < id) await _makeOffer(p); // the lower id offers
    }
    for (final id in peers.keys.toList()) {
      if (!present.contains(id)) await _closePeer(id);
    }
    _notify();
  }

  Future<void> _createConnection(CallPeer p, {String? sid}) async {
    p.sid = sid ?? _newSid();
    p.remoteSet = false;
    p.pendingIce.clear();
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    });
    p.pc = pc;
    final s = local;
    if (s != null) {
      for (final t in s.getTracks()) {
        await pc.addTrack(t, s);
      }
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      transport.send(p.userId, 'ice', jsonEncode({'sid': p.sid, 'c': c.toMap()})).catchError((_) {});
    };
    pc.onTrack = (e) async {
      if (e.streams.isEmpty) return;
      if (!p.rendererReady) {
        await p.renderer.initialize();
        p.rendererReady = true;
      }
      p.renderer.srcObject = e.streams.first;
      p.hasVideo = e.track.kind == 'video' || p.hasVideo;
      _notify();
    };
    pc.onConnectionState = (st) {
      p.state = switch (st) {
        RTCPeerConnectionState.RTCPeerConnectionStateConnected => 'connected',
        RTCPeerConnectionState.RTCPeerConnectionStateFailed => 'failed',
        _ => p.state == 'connected' && st == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ? 'connecting' : p.state,
      };
      _notify();
    };
    pc.onDataChannel = (ch) => _attachChannel(p, ch);
  }

  void _attachChannel(CallPeer p, RTCDataChannel ch) {
    p.channel = ch;
    ch.onMessage = (m) {
      if (m.isBinary) return;
      try {
        final j = jsonDecode(m.text);
        if (j is Map<String, dynamic> && j['t'] == 'state') {
          final wasOn = p.camOn;
          p.micOn = j['mic'] != false;
          p.camOn = j['cam'] == true;
          if (p.camOn && !wasOn && p.rendererReady) {
            // make sure the picture is attached to the screen surface now that frames are coming
            final stream = p.renderer.srcObject;
            p.renderer.srcObject = null;
            p.renderer.srcObject = stream;
          }
          _notify();
        }
      } catch (_) {}
    };
    ch.onDataChannelState = (st) {
      if (st == RTCDataChannelState.RTCDataChannelOpen) _sendState(p);
    };
  }

  Future<void> _makeOffer(CallPeer p) async {
    final pc = p.pc;
    if (pc == null) return;
    final ch = await pc.createDataChannel('ctl', RTCDataChannelInit()..ordered = true);
    _attachChannel(p, ch);
    final offer = await pc.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
    await pc.setLocalDescription(offer);
    await transport.send(p.userId, 'offer', jsonEncode({'sid': p.sid, 'd': {'sdp': offer.sdp, 'type': offer.type}}));
  }

  // ── incoming set-up messages ───────────────────────────────────────────────────

  Future<void> handleSignals(List<IncomingSignal> signals) async {
    for (final s in signals) {
      if (_disposed) return;
      try {
        await _handle(s);
      } catch (e) {
        debugPrint('meeting signal ${s.type} from ${s.from} failed: $e');
      }
    }
  }

  Future<void> _applyPendingIce(CallPeer p) async {
    for (final c in p.pendingIce) {
      await p.pc!.addCandidate(c);
    }
    p.pendingIce.clear();
  }

  Future<void> _handle(IncomingSignal s) async {
    final body = s.payload == null || s.payload!.isEmpty ? <String, dynamic>{} : (jsonDecode(s.payload!) as Map<String, dynamic>);
    switch (s.type) {
      case 'offer':
        var p = peers[s.from];
        if (p == null) {
          p = CallPeer(s.from);
          peers[s.from] = p;
        } else if (p.sid != body['sid']) {
          // the other side restarted (rejoined): start clean
          await p.pc?.close();
          p.pc = null;
        }
        if (p.pc == null) await _createConnection(p, sid: body['sid'] as String?);
        p.sid = body['sid'] as String;
        final d = (body['d'] as Map).cast<String, dynamic>();
        await p.pc!.setRemoteDescription(RTCSessionDescription(d['sdp'] as String, d['type'] as String));
        p.remoteSet = true;
        await _applyPendingIce(p);
        final answer = await p.pc!.createAnswer();
        await p.pc!.setLocalDescription(answer);
        await transport.send(s.from, 'answer', jsonEncode({'sid': p.sid, 'd': {'sdp': answer.sdp, 'type': answer.type}}));
      case 'answer':
        final p = peers[s.from];
        if (p == null || p.pc == null || p.sid != body['sid']) return;
        final d = (body['d'] as Map).cast<String, dynamic>();
        await p.pc!.setRemoteDescription(RTCSessionDescription(d['sdp'] as String, d['type'] as String));
        p.remoteSet = true;
        await _applyPendingIce(p);
      case 'ice':
        final p = peers[s.from];
        if (p == null || p.sid != body['sid']) return;
        final c = (body['c'] as Map).cast<String, dynamic>();
        final cand = RTCIceCandidate(c['candidate'] as String?, c['sdpMid'] as String?, (c['sdpMLineIndex'] as num?)?.toInt());
        if (p.remoteSet && p.pc != null) {
          await p.pc!.addCandidate(cand);
        } else {
          p.pendingIce.add(cand); // arrived before the offer/answer was applied: keep until then
        }
      default:
        onOther?.call(s);
    }
    _notify();
  }

  // ── my own controls ────────────────────────────────────────────────────────────

  void setMic(bool on) {
    micOn = on;
    for (final t in local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = on;
    }
    _broadcastState();
    _notify();
  }

  void setCam(bool on) {
    if (!hasCamera) return;
    camOn = on;
    for (final t in local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = on;
    }
    _broadcastState();
    _notify();
  }

  void _sendState(CallPeer p) {
    final ch = p.channel;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) return;
    ch.send(RTCDataChannelMessage(jsonEncode({'t': 'state', 'mic': micOn, 'cam': camOn})));
  }

  void _broadcastState() {
    for (final p in peers.values) {
      _sendState(p);
    }
  }

  /// Bytes of audio + video received from / sent to one person so far (proof that media really flows).
  Future<({int received, int sent})> traffic(int userId) async {
    final pc = peers[userId]?.pc;
    if (pc == null) return (received: 0, sent: 0);
    var rx = 0, tx = 0;
    try {
      for (final r in await pc.getStats()) {
        final v = r.values;
        if (r.type == 'inbound-rtp') {
          rx += (v['bytesReceived'] as num?)?.toInt() ?? 0;
          if ((v['kind'] ?? v['mediaType']) == 'video') peers[userId]?.videoFrames = (v['framesDecoded'] as num?)?.toInt() ?? 0;
        }
        if (r.type == 'outbound-rtp') tx += (v['bytesSent'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return (received: rx, sent: tx);
  }

  // ── closing ────────────────────────────────────────────────────────────────────

  Future<void> _closePeer(int id) async {
    final p = peers.remove(id);
    if (p == null) return;
    try {
      await p.channel?.close();
    } catch (_) {}
    try {
      await p.pc?.close();
    } catch (_) {}
    try {
      p.renderer.srcObject = null;
      if (p.rendererReady) await p.renderer.dispose();
    } catch (_) {}
  }

  Future<void> hangUp() async {
    for (final id in peers.keys.toList()) {
      await _closePeer(id);
    }
    try {
      for (final t in local?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await local?.dispose();
    } catch (_) {}
    local = null;
    try {
      localRenderer.srcObject = null;
      if (_localRendererReady) await localRenderer.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    hangUp();
    super.dispose();
  }

  String _newSid() => List.generate(10, (_) => _rng.nextInt(36).toRadixString(36)).join();
}
