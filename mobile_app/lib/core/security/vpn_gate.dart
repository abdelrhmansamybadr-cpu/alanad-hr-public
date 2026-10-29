import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../i18n/strings.dart';

/// Test builds only: `--dart-define=ALLOW_VPN=true` skips the block (the test phone is reached through a VPN). Normal and
/// release builds never set it.
const bool _allowVpn = bool.fromEnvironment('ALLOW_VPN');

/// On phones the app does not open while a VPN is on: a VPN can hide where the person really is, which would defeat the
/// workplace check for attendance. The block disappears by itself as soon as the VPN is switched off.
class VpnGate extends StatefulWidget {
  final Widget child;
  const VpnGate({super.key, required this.child});

  @override
  State<VpnGate> createState() => _VpnGateState();
}

class _VpnGateState extends State<VpnGate> with WidgetsBindingObserver {
  bool _vpn = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get _phone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    if (!_phone) return;
    WidgetsBinding.instance.addObserver(this);
    _check();
    _sub = Connectivity().onConnectivityChanged.listen((r) => _set(r.contains(ConnectivityResult.vpn)));
  }

  Future<void> _check() async {
    try {
      _set((await Connectivity().checkConnectivity()).contains(ConnectivityResult.vpn));
    } catch (_) {}
  }

  void _set(bool v) {
    if (_allowVpn) return;
    if (mounted && v != _vpn) setState(() => _vpn = v);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_vpn) return widget.child;
    return Directionality(
      textDirection: Localizations.localeOf(context).languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.vpn_lock_rounded, size: 72, color: Color(0xFFDC2626)),
                const SizedBox(height: 20),
                Text(context.t('vpn.title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(context.t('vpn.body'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.5)),
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: _check, icon: const Icon(Icons.refresh_rounded), label: Text(context.t('vpn.retry'))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
