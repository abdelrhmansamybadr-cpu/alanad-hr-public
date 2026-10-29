import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

/// A Wi-Fi network the device can see right now.
class WifiNet {
  final String ssid;
  final String bssid; // the strongest access point of this network
  final int signal; // 0-100
  final bool secured;
  const WifiNet({required this.ssid, required this.bssid, required this.signal, required this.secured});
}

/// What the device is connected to right now.
class LinkInfo {
  /// wifi | wired | none
  final String kind;
  final String? ssid;
  final String? bssid;
  final String? gateway;
  const LinkInfo(this.kind, {this.ssid, this.bssid, this.gateway});

  bool get isWifi => kind == 'wifi' && (ssid ?? '').isNotEmpty;
  bool get isWired => kind == 'wired' && (gateway ?? '').isNotEmpty;
}

/// Reads the real networks of this device: the visible Wi-Fi list, the current connection (Wi-Fi name or cable + gateway),
/// and opens the system Wi-Fi settings. Windows uses `netsh` / PowerShell, Android uses the system scan; elsewhere only the
/// current connection can be read.
class NetworkProbe {
  static bool get _win => !kIsWeb && Platform.isWindows;
  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// True when the device can list the Wi-Fi networks around it.
  static bool get canScan => _win || _android;

  static final _mac = RegExp(r'([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}');

  static Future<String> _run(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args, runInShell: false).timeout(const Duration(seconds: 15));
      return '${r.stdout}';
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------------------------------------- current connection

  static Future<LinkInfo> current() async {
    if (_win) return _currentWindows();
    if (_android) {
      try {
        await Permission.locationWhenInUse.request();
        await Permission.nearbyWifiDevices.request();
        final results = await Connectivity().checkConnectivity();
        final info = NetworkInfo();
        if (results.contains(ConnectivityResult.wifi)) {
          final name = (await info.getWifiName())?.replaceAll('"', '');
          if (name == null || name.isEmpty || name == '<unknown ssid>') return const LinkInfo('wifi');
          return LinkInfo('wifi', ssid: name, bssid: (await info.getWifiBSSID())?.toLowerCase(), gateway: await info.getWifiGatewayIP());
        }
        if (results.contains(ConnectivityResult.ethernet)) return const LinkInfo('wired');
      } catch (_) {}
      return const LinkInfo('none');
    }
    // iOS / macOS / others: only the Wi-Fi name can be read
    try {
      final info = NetworkInfo();
      final name = (await info.getWifiName())?.replaceAll('"', '');
      if (name != null && name.isNotEmpty && name != '<unknown ssid>') return LinkInfo('wifi', ssid: name, bssid: (await info.getWifiBSSID())?.toLowerCase(), gateway: await info.getWifiGatewayIP());
    } catch (_) {}
    return const LinkInfo('none');
  }

  static Future<LinkInfo> _currentWindows() async {
    // the lowest-metric default route says which adapter really carries the traffic, and its gateway
    final route = (await _run('powershell', [
      '-NoProfile',
      '-Command',
      r'''Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1 | ForEach-Object { $a = Get-NetAdapter -InterfaceIndex $_.ifIndex; "$($a.PhysicalMediaType)|$($_.NextHop)" }''',
    ]))
        .trim();
    final parts = route.split('|');
    final media = parts.isNotEmpty ? parts[0].trim() : '';
    final gw = parts.length > 1 ? parts[1].trim() : '';
    final wifi = _parseInterfaces(await _run('netsh', ['wlan', 'show', 'interfaces']));
    final ssid = wifi.$1;
    final bssid = wifi.$2;
    if (media.contains('802.3') && gw.isNotEmpty) return LinkInfo('wired', gateway: gw);
    if (ssid != null) return LinkInfo('wifi', ssid: ssid, bssid: bssid, gateway: gw.isEmpty ? null : gw);
    return const LinkInfo('none');
  }

  /// (ssid, bssid) of the connected Wi-Fi from `netsh wlan show interfaces`; null ssid when not connected.
  static (String?, String?) _parseInterfaces(String out) {
    String? ssid;
    String? bssid;
    for (final raw in out.split('\n')) {
      final line = raw.trim();
      final m = RegExp(r'^(AP\s+)?(BSSID|SSID)\s*:\s*(.*)$').firstMatch(line);
      if (m == null) continue;
      final v = m.group(3)!.trim();
      if (m.group(2) == 'SSID') {
        if (v.isNotEmpty) ssid = v;
      } else if (_mac.hasMatch(v)) {
        bssid = v.toLowerCase().replaceAll('-', ':');
      }
    }
    return (ssid, bssid);
  }

  // ------------------------------------------------------------------------------------------- scan

  /// The Wi-Fi networks visible right now, strongest first. Empty when nothing was found or scanning is not allowed.
  static Future<List<WifiNet>> scan() async {
    if (_win) return _scanWindows();
    if (_android) return _scanAndroid();
    final c = await current();
    return c.isWifi ? [WifiNet(ssid: c.ssid!, bssid: c.bssid ?? '', signal: 100, secured: true)] : [];
  }

  static Future<List<WifiNet>> _scanWindows() async {
    // ask the adapter for a fresh scan; the list follows within a moment
    final out = await _run('netsh', ['wlan', 'show', 'networks', 'mode=bssid']);
    final nets = <String, WifiNet>{};
    String? ssid;
    var secured = true;
    String best = '';
    String? pendingBssid;
    var bestSignal = -1;
    void flush() {
      final name = ssid;
      if (name != null && name.isNotEmpty) {
        final prev = nets[name];
        if (prev == null || bestSignal > prev.signal) nets[name] = WifiNet(ssid: name, bssid: best, signal: bestSignal < 0 ? 0 : bestSignal, secured: secured);
      }
      best = '';
      bestSignal = -1;
      secured = true;
    }

    for (final raw in out.split('\n')) {
      final line = raw.trim();
      final s = RegExp(r'^SSID\s+\d+\s*:\s*(.*)$').firstMatch(line);
      if (s != null) {
        flush();
        ssid = s.group(1)!.trim();
        continue;
      }
      final b = RegExp(r'^BSSID\s+\d+\s*:\s*(.*)$').firstMatch(line);
      if (b != null) {
        // a new access point: the signal line follows
        pendingBssid = b.group(1)!.trim().toLowerCase().replaceAll('-', ':');
        continue;
      }
      if (line.startsWith('Authentication') && line.contains(':')) secured = !line.toLowerCase().contains('open');
      final p = RegExp(r':\s*(\d{1,3})%').firstMatch(line);
      final pb = pendingBssid;
      if (p != null && pb != null) {
        final v = int.parse(p.group(1)!);
        if (v > bestSignal) {
          bestSignal = v;
          best = pb;
        }
        pendingBssid = null;
      }
    }
    flush();
    final list = nets.values.toList()..sort((a, b) => b.signal.compareTo(a.signal));
    return list;
  }

  static Future<List<WifiNet>> _scanAndroid() async {
    try {
      await Permission.locationWhenInUse.request();
      await Permission.nearbyWifiDevices.request();
      final wifi = WiFiScan.instance;
      if (await wifi.canStartScan() == CanStartScan.yes) await wifi.startScan();
      if (await wifi.canGetScannedResults() != CanGetScannedResults.yes) return [];
      final res = await wifi.getScannedResults();
      final nets = <String, WifiNet>{};
      for (final r in res) {
        final name = r.ssid.trim();
        if (name.isEmpty) continue; // hidden network
        final sig = (2 * (r.level + 100)).clamp(0, 100);
        final prev = nets[name];
        if (prev == null || sig > prev.signal) {
          nets[name] = WifiNet(ssid: name, bssid: r.bssid.toLowerCase(), signal: sig, secured: !r.capabilities.contains('ESS') || r.capabilities.contains('WPA') || r.capabilities.contains('WEP') || r.capabilities.contains('SAE'));
        }
      }
      return nets.values.toList()..sort((a, b) => b.signal.compareTo(a.signal));
    } catch (_) {
      return [];
    }
  }

  // ------------------------------------------------------------------------------------------- connect

  /// Tries to join a network that already has a saved profile on this device (its password was set up before).
  /// Returns true when the connection command was accepted; the caller re-reads [current] to confirm.
  static Future<bool> tryConnectSaved(String ssid) async {
    if (!_win) return false;
    final out = await _run('netsh', ['wlan', 'connect', 'name=$ssid', 'ssid=$ssid']);
    return out.toLowerCase().contains('success') || out.contains('بنجاح');
  }

  /// Opens the system Wi-Fi settings so the person can join a network (type its password) there.
  static Future<void> openWifiSettings() async {
    try {
      if (_win) {
        await Process.run('cmd', ['/c', 'start', 'ms-settings:network-wifi']);
      } else if (_android) {
        await const AndroidIntent(action: 'android.settings.WIFI_SETTINGS').launch();
      }
    } catch (_) {}
  }
}
