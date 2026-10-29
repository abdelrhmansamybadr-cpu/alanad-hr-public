import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/network/network_probe.dart';
import '../../core/ui/widgets.dart';

/// Lets HR pick the office Wi-Fi from the networks this device can really see right now.
/// A network can only be chosen once this device is connected to it (so it is proven to work and its password is set up):
/// picking one that is not connected tries to join it (when its password is already saved), otherwise asks the person to
/// connect from the system Wi-Fi settings and check again.
Future<WifiNet?> pickWifi(BuildContext context) => showAppSheet<WifiNet>(context, title: context.t('rules.picker_title'), child: const _WifiPicker());

class _WifiPicker extends StatefulWidget {
  const _WifiPicker();

  @override
  State<_WifiPicker> createState() => _WifiPickerState();
}

class _WifiPickerState extends State<_WifiPicker> {
  List<WifiNet> _nets = const [];
  LinkInfo _current = const LinkInfo('none');
  bool _loading = true;
  String? _busySsid; // joining this network now
  WifiNet? _waitFor; // the person must connect to this one first
  String? _note;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final cur = await NetworkProbe.current();
    var nets = await NetworkProbe.scan();
    // the connected network must always be offered, even when the scan does not list it
    if (cur.isWifi && !nets.any((n) => n.ssid == cur.ssid)) nets = [WifiNet(ssid: cur.ssid!, bssid: cur.bssid ?? '', signal: 100, secured: true), ...nets];
    if (!mounted) return;
    setState(() {
      _current = cur;
      _nets = nets;
      _loading = false;
    });
  }

  bool _isConnected(WifiNet n) => _current.isWifi && _current.ssid == n.ssid;

  WifiNet _withCurrentRouter(WifiNet n) => WifiNet(ssid: n.ssid, bssid: _current.bssid ?? n.bssid, signal: n.signal, secured: n.secured);

  Future<void> _choose(WifiNet n) async {
    if (_isConnected(n)) {
      Navigator.of(context).pop(_withCurrentRouter(n));
      return;
    }
    // not connected: join it when this device already knows its password
    setState(() {
      _busySsid = n.ssid;
      _note = context.t('rules.connecting', {'ssid': n.ssid});
      _waitFor = null;
    });
    final tried = await NetworkProbe.tryConnectSaved(n.ssid);
    if (tried) {
      for (var i = 0; i < 6; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final cur = await NetworkProbe.current();
        if (cur.isWifi && cur.ssid == n.ssid) {
          if (!mounted) return;
          setState(() => _current = cur);
          Navigator.of(context).pop(_withCurrentRouter(n));
          return;
        }
      }
    }
    if (!mounted) return;
    // not set up on this device: it has to be joined (with its password) from the system settings first
    setState(() {
      _busySsid = null;
      _note = null;
      _waitFor = n;
    });
  }

  Future<void> _checkAgain() async {
    final n = _waitFor;
    if (n == null) return;
    setState(() => _loading = true);
    final cur = await NetworkProbe.current();
    if (!mounted) return;
    if (cur.isWifi && cur.ssid == n.ssid) {
      Navigator.of(context).pop(WifiNet(ssid: n.ssid, bssid: cur.bssid ?? n.bssid, signal: n.signal, secured: n.secured));
      return;
    }
    setState(() {
      _current = cur;
      _loading = false;
      _note = context.t('rules.still_not', {'ssid': n.ssid});
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wait = _waitFor;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (wait != null) ...[
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.wifi_password_rounded, color: context.scheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(context.t('rules.connect_first_title', {'ssid': wait.ssid}), style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            Text(context.t('rules.connect_first_body'), style: TextStyle(color: c.subtext, height: 1.4)),
            if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600))),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 8, children: [
              FilledButton.icon(onPressed: NetworkProbe.openWifiSettings, icon: const Icon(Icons.settings_rounded), label: Text(context.t('rules.open_wifi_settings'))),
              OutlinedButton.icon(onPressed: _loading ? null : _checkAgain, icon: const Icon(Icons.refresh_rounded), label: Text(context.t('rules.check_again'))),
              TextButton(onPressed: () => setState(() { _waitFor = null; _note = null; }), child: Text(context.t('common.cancel'))),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      Row(children: [
        Expanded(child: Text(_current.isWifi ? '${context.t('rules.connected')}: ${_current.ssid}' : '', style: TextStyle(color: c.subtext, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(tooltip: context.t('common.retry'), onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh_rounded)),
      ]),
      if (_loading)
        Padding(padding: const EdgeInsets.all(24), child: Column(children: [const CircularProgressIndicator(), const SizedBox(height: 12), Text(context.t('rules.scanning'), style: TextStyle(color: c.subtext))]))
      else if (_nets.isEmpty)
        Padding(padding: const EdgeInsets.all(20), child: Text(context.t('rules.none_found'), textAlign: TextAlign.center, style: TextStyle(color: c.subtext, height: 1.4)))
      else
        for (final n in _nets)
          ListTile(
            enabled: _busySsid == null,
            leading: Icon(n.signal > 66 ? Icons.network_wifi_rounded : n.signal > 33 ? Icons.network_wifi_3_bar_rounded : Icons.network_wifi_1_bar_rounded, color: _isConnected(n) ? c.success : c.subtext),
            title: Text(n.ssid, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: _isConnected(n) ? FontWeight.w800 : FontWeight.w600)),
            subtitle: _busySsid == n.ssid ? Text(_note ?? '') : null,
            trailing: _busySsid == n.ssid
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : _isConnected(n)
                    ? Pill(context.t('rules.connected'), color: c.success, icon: Icons.check_rounded)
                    : (n.secured ? Icon(Icons.lock_outline_rounded, size: 18, color: c.subtext) : null),
            onTap: () => _choose(n),
          ),
    ]);
  }
}
