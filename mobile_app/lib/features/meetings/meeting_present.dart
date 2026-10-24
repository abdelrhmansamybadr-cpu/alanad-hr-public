import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'meeting_call.dart';

class _Out {
  final int userId;
  final String sid;
  RTCPeerConnection? pc;
  bool remoteSet = false;
  final List<RTCIceCandidate> pending = [];
  _Out(this.userId, this.sid);
}

/// "Share my screen with the meeting". Same direct-connection technique as the call, on its OWN connections so starting or
/// stopping the screen never disturbs the audio / video call:
///   present.offer / present.answer / present.ice / present.stop    (the website speaks exactly the same)
/// The presenter captures the screen ONCE and offers it to everybody in the call (and to people who join later);
/// every viewer answers and shows it above the call tiles. One person presents at a time.
class PresentationHub extends ChangeNotifier {
  PresentationHub({required this.transport, required this.iceServers, this.capture});

  final MeetingTransport transport;
  final List<Map<String, dynamic>> iceServers;
  final Future<MediaStream> Function()? capture;

  /// Capturing the screen works on the laptop apps. (Phones can watch; sharing from a phone is not built.)
  static bool get canShare => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  // ── presenter side ──
  bool presenting = false;
  MediaStream? _stream;
  final Map<int, _Out> _out = {};
  String? error;

  // ── viewer side ──
  int? presenterId;
  RTCPeerConnection? _inPc;
  String _inSid = '';
  bool _inRemoteSet = false;
  final List<RTCIceCandidate> _inPending = [];
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool _rendererReady = false;
  bool get watching => presenterId != null && _rendererReady && renderer.srcObject != null;
  bool _disposed = false;
  final _rng = Random.secure();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _newSid() => List.generate(10, (_) => _rng.nextInt(36).toRadixString(36)).join();

  static Future<MediaStream> _defaultCapture() async {
    final sources = await desktopCapturer.getSources(types: [SourceType.Screen]);
    if (sources.isEmpty) throw 'no screen to share';
    return navigator.mediaDevices.getDisplayMedia({
      'video': {
        'deviceId': {'exact': sources.first.id},
        'mandatory': {'frameRate': 15.0},
      },
      'audio': false,
    });
  }

  // ─────────────────────────────────────────────────────────────────── presenter

  Future<void> startPresenting(Set<int> present, int myId) async {
    if (presenting) return;
    if (presenterId != null) {
      error = 'busy';
      _notify();
      return;
    }
    error = null;
    try {
      _stream = await (capture ?? _defaultCapture)();
    } catch (e) {
      error = 'capture';
      _notify();
      return;
    }
    presenting = true;
    _notify();
    // if the system's own "stop sharing" control ends the capture, follow it
    for (final t in _stream!.getVideoTracks()) {
      t.onEnded = () => stopPresenting();
    }
    await syncPresence(present, myId);
  }

  Future<void> stopPresenting() async {
    if (!presenting) return;
    presenting = false;
    for (final o in _out.values.toList()) {
      transport.send(o.userId, 'present.stop', jsonEncode({'sid': o.sid})).catchError((_) {});
      try {
        await o.pc?.close();
      } catch (_) {}
    }
    _out.clear();
    try {
      for (final t in _stream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _stream?.dispose();
    } catch (_) {}
    _stream = null;
    _notify();
  }

  /// Offer the screen to every person present who does not have it yet; drop those who left. Also clears a viewer whose
  /// presenter has left the call.
  Future<void> syncPresence(Set<int> present, int myId) async {
    if (_disposed) return;
    if (presenterId != null && !present.contains(presenterId)) await _clearViewer();
    if (!presenting) return;
    for (final id in present) {
      if (id == myId || _out.containsKey(id)) continue;
      await _offerTo(id);
    }
    for (final id in _out.keys.toList()) {
      if (!present.contains(id)) {
        try {
          await _out.remove(id)?.pc?.close();
        } catch (_) {}
      }
    }
    _notify();
  }

  Future<void> _offerTo(int id) async {
    final out = _Out(id, _newSid());
    _out[id] = out;
    final pc = await createPeerConnection({'iceServers': iceServers, 'sdpSemantics': 'unified-plan'});
    out.pc = pc;
    for (final t in _stream!.getVideoTracks()) {
      await pc.addTrack(t, _stream!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      transport.send(id, 'present.ice', jsonEncode({'sid': out.sid, 'c': c.toMap()})).catchError((_) {});
    };
    final offer = await pc.createOffer({'offerToReceiveVideo': false, 'offerToReceiveAudio': false});
    await pc.setLocalDescription(offer);
    await transport.send(id, 'present.offer', jsonEncode({'sid': out.sid, 'd': {'sdp': offer.sdp, 'type': offer.type}}));
  }

  // ──────────────────────────────────────────────────────────────── set-up messages

  Future<void> handle(IncomingSignal s) async {
    if (_disposed || !s.type.startsWith('present.')) return;
    final body = s.payload == null || s.payload!.isEmpty ? <String, dynamic>{} : (jsonDecode(s.payload!) as Map<String, dynamic>);
    try {
      switch (s.type) {
        case 'present.offer':
          await _onOffer(s.from, body);
        case 'present.answer':
          final o = _out[s.from];
          if (o == null || o.pc == null || o.sid != body['sid']) return;
          final d = (body['d'] as Map).cast<String, dynamic>();
          await o.pc!.setRemoteDescription(RTCSessionDescription(d['sdp'] as String, d['type'] as String));
          o.remoteSet = true;
          for (final c in o.pending) {
            await o.pc!.addCandidate(c);
          }
          o.pending.clear();
        case 'present.ice':
          final c = (body['c'] as Map).cast<String, dynamic>();
          final cand = RTCIceCandidate(c['candidate'] as String?, c['sdpMid'] as String?, (c['sdpMLineIndex'] as num?)?.toInt());
          final o = _out[s.from];
          if (o != null && o.sid == body['sid']) {
            // I am the presenter: this is the viewer's network info
            o.remoteSet && o.pc != null ? await o.pc!.addCandidate(cand) : o.pending.add(cand);
          } else if (s.from == presenterId && body['sid'] == _inSid) {
            // I am the viewer: this is the presenter's network info
            _inRemoteSet && _inPc != null ? await _inPc!.addCandidate(cand) : _inPending.add(cand);
          }
        case 'present.stop':
          if (s.from == presenterId && body['sid'] == _inSid) await _clearViewer();
          _out.remove(s.from)?.pc?.close();
      }
    } catch (e) {
      debugPrint('present signal ${s.type} failed: $e');
    }
    _notify();
  }

  // ─────────────────────────────────────────────────────────────────────── viewer

  Future<void> _onOffer(int from, Map<String, dynamic> body) async {
    if (presenting) return; // I am presenting myself: ignore a second presenter
    if (presenterId != null && presenterId != from) return; // one presenter at a time
    if (presenterId == from && _inSid != body['sid']) await _clearViewer(); // the presenter restarted
    if (!_rendererReady) {
      await renderer.initialize();
      _rendererReady = true;
    }
    _inSid = body['sid'] as String;
    _inRemoteSet = false;
    _inPending.clear();
    presenterId = from;
    final pc = await createPeerConnection({'iceServers': iceServers, 'sdpSemantics': 'unified-plan'});
    _inPc = pc;
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      transport.send(from, 'present.ice', jsonEncode({'sid': _inSid, 'c': c.toMap()})).catchError((_) {});
    };
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) renderer.srcObject = e.streams.first;
      _notify();
    };
    final d = (body['d'] as Map).cast<String, dynamic>();
    await pc.setRemoteDescription(RTCSessionDescription(d['sdp'] as String, d['type'] as String));
    _inRemoteSet = true;
    for (final c in _inPending) {
      await pc.addCandidate(c);
    }
    _inPending.clear();
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await transport.send(from, 'present.answer', jsonEncode({'sid': _inSid, 'd': {'sdp': answer.sdp, 'type': answer.type}}));
    _notify();
  }

  Future<void> _clearViewer() async {
    presenterId = null;
    _inSid = '';
    _inRemoteSet = false;
    _inPending.clear();
    try {
      await _inPc?.close();
    } catch (_) {}
    _inPc = null;
    renderer.srcObject = null;
    _notify();
  }

  /// Leave everything (called when the call ends).
  Future<void> hangUp() async {
    await stopPresenting();
    await _clearViewer();
  }

  @override
  void dispose() {
    _disposed = true;
    hangUp();
    if (_rendererReady) renderer.dispose();
    super.dispose();
  }
}
