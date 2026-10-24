import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api/api.dart';
import '../../core/session/session.dart';
import 'meeting_call.dart';
import 'meeting_models.dart';
import 'meeting_present.dart';

class _ApiTransport implements MeetingTransport {
  final Api api;
  final int meetingId;
  _ApiTransport(this.api, this.meetingId);

  @override
  Future<void> send(int to, String type, String payload) async {
    await api.post('/meetings/$meetingId/signal', {'to': to, 'type': type, 'payload': payload});
  }
}

/// The meeting the person is in RIGHT NOW. It lives in the app (not in the room screen), so the call keeps going while
/// the room is closed and the person uses other tabs ("minimised"), until they leave or the meeting ends.
class MeetingSession extends ChangeNotifier {
  MeetingSession(this._ref, this.meeting);

  final Ref _ref;
  final Meeting meeting;

  bool joining = true;
  String? error; // server message when joining failed
  bool ended = false;
  bool removed = false;
  Set<int> present = {};
  MeetingCall? call;
  PresentationHub? present_; // "share my screen" (presenter or viewer)
  DateTime? joinedAt;

  Timer? _poll;
  bool _polling = false;
  bool _disposed = false;
  int _lastSignal = 0;

  Api get _api => _ref.read(apiProvider);
  int get myId => _ref.read(sessionProvider).user?.id ?? 0;
  bool get isHost => meeting.createdBy == myId || (_ref.read(sessionProvider).user?.isAdmin ?? false);
  bool get over => ended || removed;

  String nameOf(int id) => meeting.people.where((p) => p.userId == id).map((p) => p.name).firstOrNull ?? '?';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    try {
      // Permissions first (mobile asks here; Windows has no prompt). Refusing is fine: the person can still listen.
      if (Platform.isAndroid || Platform.isIOS) {
        await [Permission.microphone, Permission.camera].request();
      }
      final transport = _ApiTransport(_api, meeting.id);
      final hub = PresentationHub(transport: transport, iceServers: const [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]);
      hub.addListener(_notify);
      present_ = hub;
      final c = MeetingCall(myId: myId, transport: transport, onOther: hub.handle);
      c.addListener(_notify);
      await c.start();
      call = c;
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          await Helper.setSpeakerphoneOn(true); // a meeting should come out of the loudspeaker, not the earpiece
        } catch (_) {}
      }
      final r = await _api.post('/meetings/${meeting.id}/join');
      final m = r is Map ? r : const {};
      _lastSignal = (m['lastSignalId'] as num?)?.toInt() ?? 0;
      present = ((m['present'] as List?) ?? []).map((e) => (e as num).toInt()).toSet()..add(myId);
      await c.syncPresence(present);
      joinedAt = DateTime.now();
      joining = false;
      _notify();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => tick());
    } on ApiException catch (e) {
      joining = false;
      error = e.message;
      await call?.hangUp();
      _notify();
    } catch (e) {
      joining = false;
      error = '$e';
      _notify();
    }
  }

  /// Fetch what happened (call messages, who is present, did it end) - every 2 seconds.
  Future<void> tick() async {
    if (_polling || call == null || _disposed || over) return;
    _polling = true;
    try {
      final r = await _api.get('/meetings/${meeting.id}/poll', query: {'after': _lastSignal});
      if (_disposed || r is! Map) return;
      final signals = ((r['signals'] as List?) ?? [])
          .whereType<Map>()
          .map((s) => IncomingSignal(id: (s['id'] as num).toInt(), from: (s['from'] as num).toInt(), type: s['type'] as String, payload: s['payload'] as String?))
          .toList();
      if (signals.isNotEmpty) _lastSignal = signals.last.id;
      present = ((r['present'] as List?) ?? []).map((e) => (e as num).toInt()).toSet();
      final isEnded = r['status'] == 'ended' || r['status'] == 'cancelled';
      final isRemoved = r['removed'] == true;
      if (isEnded || isRemoved) {
        _poll?.cancel();
        await present_?.hangUp();
        await call?.hangUp();
        ended = isEnded;
        removed = isRemoved;
        _notify();
        return;
      }
      await call!.handleSignals(signals);
      await call!.syncPresence(present);
      await present_?.syncPresence(present, myId); // somebody who joined while I share gets the screen too
      _notify();
    } catch (_) {
      // a missed poll is fine - the next one catches up
    } finally {
      _polling = false;
    }
  }

  /// Leave the meeting (the others stay in it).
  Future<void> leave() async {
    _poll?.cancel();
    await present_?.hangUp();
    await call?.hangUp();
    try {
      await _api.post('/meetings/${meeting.id}/leave');
    } catch (_) {}
    _ref.invalidate(meetingsListProvider);
  }

  Future<void> endForAll() async {
    try {
      await _api.post('/meetings/${meeting.id}/end');
    } catch (_) {}
    await leave();
  }

  /// Returns an error message, or null on success.
  Future<String?> kick(MeetingPerson p) async {
    try {
      await _api.delete('/meetings/${meeting.id}/members/${p.userId}');
      present.remove(p.userId);
      _notify();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    present_?.dispose();
    call?.dispose();
    super.dispose();
  }
}

/// Holds the one meeting a person can be in.
class MeetingSessionHost extends ChangeNotifier {
  MeetingSessionHost(this._ref);

  final Ref _ref;
  MeetingSession? current;

  /// Starts (or re-uses) the session for [m]. Returns false when the person is already in a DIFFERENT live meeting.
  bool enter(Meeting m) {
    final c = current;
    if (c != null && c.meeting.id != m.id && !c.over) return false;
    if (c != null && c.meeting.id != m.id) {
      c.dispose();
      current = null;
    }
    if (current == null) {
      current = MeetingSession(_ref, m)..addListener(notifyListeners);
      current!.start();
    }
    notifyListeners();
    return true;
  }

  /// Leave and forget the session.
  Future<void> leaveCurrent({bool endForAll = false}) async {
    final c = current;
    if (c == null) return;
    current = null;
    notifyListeners();
    if (endForAll) {
      await c.endForAll();
    } else {
      await c.leave();
    }
    c.dispose();
  }

  /// Drop a session that already ended (nothing to leave on the server).
  void clearOver() {
    final c = current;
    if (c == null) return;
    current = null;
    c.present_?.hangUp();
    c.call?.hangUp();
    c.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    current?.dispose();
    super.dispose();
  }
}

final meetingHostProvider = ChangeNotifierProvider<MeetingSessionHost>((ref) {
  final h = MeetingSessionHost(ref);
  // Signing out, or switching to another company of the group, ends the call: a meeting belongs to one company.
  ref.listen<int?>(sessionProvider.select((s) => s.isSignedIn ? s.company?.id : null), (prev, next) {
    if (prev != next) h.leaveCurrent();
  });
  ref.onDispose(h.dispose);
  return h;
});
