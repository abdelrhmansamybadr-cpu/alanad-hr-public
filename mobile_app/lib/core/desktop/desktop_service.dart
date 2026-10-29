import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../models/json.dart';

/// The Windows app's link to the system (see windows/runner/flutter_window.cpp): it lives in the tray, rings with a real
/// sound, shows a pop-up notification, and can bring its window back. Everything here does nothing on other platforms.
class DesktopService {
  static const _ch = MethodChannel('alanad/desktop');
  static bool get on => !kIsWeb && Platform.isWindows;

  /// Called when the person clicks a pop-up notification (the window is already brought forward).
  static void Function()? onBalloonClick;
  static bool _wired = false;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'balloonClicked') onBalloonClick?.call();
      if (call.method == 'popupAction') onPopupAction?.call('${call.arguments}');
      return null;
    });
  }

  static Future<bool> _call(String m, [Map<String, Object?>? args]) async {
    if (!on) return false;
    _wire();
    try {
      return (await _ch.invokeMethod<bool>(m, args)) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------------------------------- sounds

  static String? _ringPath;
  static String? _chimePath;

  /// A phone-like ring (two bursts, then a pause), 16-bit mono WAV. Made here so no audio file has to ship with the app.
  static Uint8List _wav(List<List<double>> parts, {int rate = 22050}) {
    // each part = [seconds, freqA, freqB, volume]; freq 0 = silence
    final samples = <int>[];
    for (final p in parts) {
      final n = (p[0] * rate).round();
      for (var i = 0; i < n; i++) {
        final t = i / rate;
        var v = 0.0;
        if (p[1] > 0) {
          final edge = math.min(1.0, math.min(i, n - i) / (rate * 0.02)); // 20 ms fade: no clicks
          v = (math.sin(2 * math.pi * p[1] * t) + (p[2] > 0 ? math.sin(2 * math.pi * p[2] * t) : 0)) / (p[2] > 0 ? 2 : 1) * p[3] * edge;
        }
        samples.add((v * 32767).round().clamp(-32768, 32767));
      }
    }
    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static Future<String> _file(String name, Uint8List bytes) async {
    final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  /// Rings (loops) until [stopRing].
  static bool _ringing = false;

  static Future<bool> startRing() async {
    if (!on) return false;
    _ringing = true;
    _ringPath ??= await _file('alanad_ring.wav', _wav([
      [0.45, 440, 480, 0.8], [0.15, 0, 0, 0], [0.45, 440, 480, 0.8], [1.2, 0, 0, 0],
    ]));
    return _call('playLoop', {'path': _ringPath});
  }

  static Future<void> stopRing() async {
    if (!_ringing) return;
    _ringing = false;
    await _call('stopSound');
  }

  /// A short two-note chime for a normal notification. Windows plays one sound at a time, so while a meeting is ringing the
  /// chime is skipped (it would cut the ring off).
  static Future<bool> chime() async {
    if (!on || _ringing) return false;
    _chimePath ??= await _file('alanad_chime.wav', _wav([
      [0.18, 880, 0, 0.7], [0.30, 1175, 0, 0.7],
    ]));
    return _call('playOnce', {'path': _chimePath});
  }

  // ------------------------------------------------------------------------------------------- window and notifications

  /// A pop-up notification from the tray icon (Windows plays its own notification sound).
  static Future<bool> notify(String title, String body) => _call('notify', {'title': title, 'body': body});

  /// Brings the window up in front, even from the tray.
  static Future<bool> show() => _call('show');

  /// True while the app window is the one in front (nothing else to pop up then).
  static Future<bool> isFocused() => _call('isFocused');

  /// The "incoming meeting" card in the top corner of the screen (top-right; top-left when [rtl]).
  static Future<bool> showPopup({required String header, required String title, required String sub, required String join, required String decline, required bool rtl}) =>
      _call('showPopup', {'header': header, 'title': title, 'sub': sub, 'join': join, 'decline': decline, 'rtl': rtl});

  static Future<bool> hidePopup() => _call('hidePopup');

  /// "join" / "decline" / "open" - what the person pressed on the card.
  static void Function(String action)? onPopupAction;

  /// Start with Windows, hidden in the tray, so meetings can ring after a restart.
  static Future<bool> setAutoStart(bool v) => _call('setAutoStart', {'on': v});

  // ------------------------------------------------------------------------------------------- new notifications

  static const _lastKey = 'desktop_last_notification_v1';

  /// Shows (pop-up plus chime) the notifications that arrived since the last check. The first check after sign-in only remembers
  /// where we are, so old items never flood the screen. Returns the last notification shown, if any (to open when clicked).
  static Future<Map<String, dynamic>?> checkNotifications(Api api) async {
    if (!on) return null;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastKey);
    if (last == null) {
      final m = asMap(await api.get('/notifications?limit=1'));
      final items = asMapList(m['items']);
      await prefs.setInt(_lastKey, items.isEmpty ? 0 : jInt(items.first, 'id'));
      return null;
    }
    final m = asMap(await api.get('/notifications?unread=1&limit=20&after=$last'));
    final items = asMapList(m['items']).where((i) => jInt(i, 'id') > last).toList();
    if (items.isEmpty) return null;
    final newest = items.map((i) => jInt(i, 'id')).reduce(math.max);
    await prefs.setInt(_lastKey, newest);
    final first = items.first;
    final more = items.length > 1 ? ' (+${items.length - 1})' : '';
    await notify('${jStr(first, 'title').isEmpty ? 'Al Anad HR' : jStr(first, 'title')}$more', jStr(first, 'body'));
    await chime();
    return {'type': jStr(first, 'type'), 'data': first['data'] is Map ? first['data'] : <String, dynamic>{}};
  }

  /// Sign-out: forget where we were.
  static Future<void> forget() async {
    if (!on) return;
    (await SharedPreferences.getInstance()).remove(_lastKey);
  }
}
