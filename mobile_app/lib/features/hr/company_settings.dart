import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../common/profile_widgets.dart';
import 'org.dart';

const _moduleKeys = ['employees', 'departments', 'leaves', 'attendance', 'shifts', 'payroll', 'recruitment', 'talent_pool', 'reviews', 'announcements', 'documents', 'requests'];
const _currencies = ['EGP', 'SAR', 'AED', 'KWD', 'QAR', 'BHD', 'OMR', 'JOD', 'USD', 'EUR', 'GBP'];
const _zones = ['Africa/Cairo', 'Asia/Riyadh', 'Asia/Dubai', 'Asia/Kuwait', 'Asia/Qatar', 'Asia/Bahrain', 'Asia/Muscat', 'Asia/Amman', 'Asia/Beirut', 'Africa/Casablanca', 'Africa/Tunis', 'Africa/Algiers', 'Europe/London', 'Europe/Paris', 'Europe/Istanbul', 'America/New_York', 'UTC'];
const _days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

class CompanySettingsScreen extends ConsumerStatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  ConsumerState<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends ConsumerState<CompanySettingsScreen> {
  late final Company _c = ref.read(sessionProvider).company!;
  late final _name = TextEditingController(text: _c.name);
  late String _primary = colorToHex(Color(_c.primary));
  late String _accent = colorToHex(Color(_c.accent));
  late final Set<String> _weekend = _c.weekendDays.toSet();
  late String _currency = _currencies.contains(_c.currency) ? _c.currency : 'EGP';
  late String _zone = _zones.contains(_c.timezone) ? _c.timezone : 'Africa/Cairo';
  late int _grace = _c.lateGraceMinutes;
  late final Set<String> _modules = (_c.modules ?? _moduleKeys).toSet();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Sends a test message to the signed-in admin so they know invitation and password e-mails will arrive.
  Future<void> _testEmail() async {
    final ok = context.t('company.test_email_ok');
    final bad = context.t('company.test_email_failed');
    try {
      final m = asMap(await ref.read(apiProvider).post('/company/test-email', {}));
      if (mounted) toast(context, m['emailed'] == true ? '$ok ${jStr(m, 'to')}' : bad, error: m['emailed'] != true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast(context, context.t('common.required'), error: true);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/company', {
        'name': _name.text.trim(),
        'primaryColor': _primary,
        'accentColor': _accent,
        'weekendDays': _days.where(_weekend.contains).toList(),
        'currency': _currency,
        'timezone': _zone,
        'lateGraceMinutes': _grace,
        'modules': _modules.length == _moduleKeys.length ? null : _moduleKeys.where(_modules.contains).toList(),
      });
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) toast(context, context.t('company.saved'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logo() async {
    final ok = context.t('company.logo_updated');
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    try {
      await ref.read(apiProvider).upload('/company/logo', path);
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) toast(context, ok);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(sessionProvider).company ?? _c;
    final previewPrimary = hexColor(_primary);
    final previewAccent = hexColor(_accent, const Color(0xFFC88453));

    return Scaffold(
      appBar: AppBar(title: Text(context.t('company.title'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        // ---- identity
        AppCard(
          child: Column(children: [
            Row(children: [
              GestureDetector(
                onTap: _logo,
                child: Stack(children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(color: context.colors.brandSoft, borderRadius: BorderRadius.circular(22)),
                    child: company.logoUrl == null ? Icon(Icons.business_rounded, size: 34, color: context.scheme.primary) : ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.network(absUrl(company.logoUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.business_rounded, size: 34, color: context.scheme.primary))),
                  ),
                  PositionedDirectional(end: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: context.scheme.primary, shape: BoxShape.circle, border: Border.all(color: context.scheme.surface, width: 2.5)), child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white))),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(child: AppField(controller: _name, label: context.t('auth.company.name'), icon: Icons.business_rounded)),
            ]),
          ]),
        ),

        // ---- brand
        SectionHeader(context.t('company.brand')),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('company.brand_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)),
            const SizedBox(height: 14),
            Text(context.t('company.primary'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SwatchPicker(value: _primary, onChanged: (v) => setState(() => _primary = v)),
            const SizedBox(height: 18),
            Text(context.t('company.accent'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SwatchPicker(value: _accent, onChanged: (v) => setState(() => _accent = v)),
            const SizedBox(height: 18),
            Container(
              height: 64,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [previewPrimary, previewAccent]), borderRadius: BorderRadius.circular(18)),
              child: Center(child: Text(_name.text.isEmpty ? company.name : _name.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
            ),
          ]),
        ),

        // ---- work week
        SectionHeader(context.t('company.workweek')),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('company.weekend'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in _days)
                FilterChip(
                  label: Text(context.t('weekday.$d')),
                  selected: _weekend.contains(d),
                  showCheckmark: false,
                  onSelected: (v) => setState(() => v ? _weekend.add(d) : _weekend.remove(d)),
                  selectedColor: context.scheme.primary,
                  labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _weekend.contains(d) ? Colors.white : null),
                ),
            ]),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _zone,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.t('company.timezone'), prefixIcon: const Icon(Icons.public_rounded)),
              items: [for (final z in _zones) DropdownMenuItem(value: z, child: Text(z))],
              onChanged: (v) => setState(() => _zone = v ?? _zone),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: InputDecoration(labelText: context.t('common.currency'), prefixIcon: const Icon(Icons.attach_money_rounded)),
              items: [for (final c in _currencies) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.t('company.grace'), style: const TextStyle(fontWeight: FontWeight.w700)), Text(context.t('company.grace_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))])),
              IconButton.filledTonal(onPressed: _grace <= 0 ? null : () => setState(() => _grace = (_grace - 5).clamp(0, 240)), icon: const Icon(Icons.remove_rounded)),
              SizedBox(width: 54, child: Center(child: Text(context.t('common.min', {'n': _grace}), style: const TextStyle(fontWeight: FontWeight.w800)))),
              IconButton.filledTonal(onPressed: () => setState(() => _grace = (_grace + 5).clamp(0, 240)), icon: const Icon(Icons.add_rounded)),
            ]),
          ]),
        ),

        // ---- modules
        SectionHeader(context.t('company.modules')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(8), child: Text(context.t('company.modules_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4))),
            for (final m in _moduleKeys) SwitchListTile(dense: true, title: Text(context.t('module.$m')), value: _modules.contains(m), onChanged: (v) => setState(() => v ? _modules.add(m) : _modules.remove(m))),
          ]),
        ),
        const SizedBox(height: 20),
        LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
        SectionHeader(context.t('company.more')),
        MenuGroup(children: [
          MenuItem(icon: Icons.pin_drop_rounded, color: const Color(0xFF10B981), label: context.t('rules.title'), onTap: () => context.push('/h/attendance-rules')),
          MenuItem(icon: Icons.mark_email_read_outlined, color: const Color(0xFF6366F1), label: context.t('company.test_email'), onTap: _testEmail),
        ]),
      ]),
    );
  }
}

// ============================================================ attendance rules

final _rulesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/attendance-rules')));

class AttendanceRulesScreen extends ConsumerWidget {
  const AttendanceRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(_rulesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('rules.title'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showAppSheet(context, title: context.t('rules.add'), child: const _RuleForm()), icon: const Icon(Icons.add_rounded), label: Text(context.t('rules.add'))),
      body: AsyncBody<List<Map<String, dynamic>>>(
        value: rules,
        onRetry: () => ref.invalidate(_rulesProvider),
        builder: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(context.t('rules.hint2'), style: TextStyle(color: context.colors.subtext, height: 1.4)));
            final r = items[i - 1];
            final active = jBool(r, 'isActive');
            return RowTile(
              leading: IconBadge(Icons.pin_drop_rounded, color: active ? context.colors.success : context.colors.subtext, size: 46),
              title: jStr(r, 'name'),
              subtitle: [
                if (jBool(r, 'locationEnabled')) context.t('rules.radius_m', {'n': (jDouble(r, 'locationRadiusKm') * 1000).round()}),
                if (jBool(r, 'wifiEnabled')) 'Wi-Fi ${jStr(r, 'wifiSsid')}',
                if (jBool(r, 'locationEnabled') && jBool(r, 'wifiEnabled')) context.t(jStr(r, 'matchMode') == 'all' ? 'rules.mode_all' : 'rules.mode_any'),
                if (!jBool(r, 'locationEnabled') && !jBool(r, 'wifiEnabled')) context.t('rules.anywhere'),
              ].join(' · '),
              trailing: active ? StatusChip('active') : null,
              onTap: () => showAppSheet(context, title: jStr(r, 'name'), child: _RuleForm(existing: r)),
            );
          },
        ),
      ),
    );
  }
}

class _RuleForm extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  const _RuleForm({this.existing});

  @override
  ConsumerState<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends ConsumerState<_RuleForm> {
  late final _name = TextEditingController(text: widget.existing == null ? '' : jStr(widget.existing!, 'name'));
  late final _lat = TextEditingController(text: widget.existing?['locationLat']?.toString() ?? '');
  late final _lng = TextEditingController(text: widget.existing?['locationLng']?.toString() ?? '');
  late final _radius = TextEditingController(text: widget.existing == null || widget.existing!['locationRadiusKm'] == null ? '200' : (jDouble(widget.existing!, 'locationRadiusKm') * 1000).round().toString());
  late final _ssid = TextEditingController(text: widget.existing == null ? '' : jStr(widget.existing!, 'wifiSsid'));
  late final _bssid = TextEditingController(text: widget.existing == null ? '' : jStr(widget.existing!, 'wifiBssid'));
  late bool _both = widget.existing != null && jStr(widget.existing!, 'matchMode') == 'all';
  bool _wifiBusy = false;
  late bool _loc = widget.existing != null && jBool(widget.existing!, 'locationEnabled');
  late bool _wifi = widget.existing != null && jBool(widget.existing!, 'wifiEnabled');
  late bool _active = widget.existing == null ? true : jBool(widget.existing!, 'isActive');
  bool _busy = false;
  bool _locating = false;

  @override
  void dispose() {
    for (final c in [_name, _lat, _lng, _radius, _ssid, _bssid]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _here() async {
    final denied = context.t('time.err.permission');
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw ApiException(denied);
      final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 20));
      _lat.text = p.latitude.toStringAsFixed(6);
      _lng.text = p.longitude.toStringAsFixed(6);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, context.t('time.err.no_fix'), error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Fill the Wi-Fi fields from the network this phone is connected to right now.
  Future<void> _thisWifi() async {
    final none = context.t('rules.wifi_unreadable');
    setState(() => _wifiBusy = true);
    try {
      await Permission.locationWhenInUse.request();
      await Permission.nearbyWifiDevices.request();
      final info = NetworkInfo();
      final name = (await info.getWifiName())?.replaceAll('"', '');
      final id = await info.getWifiBSSID();
      if (name == null || name.isEmpty || name == '<unknown ssid>') {
        if (mounted) toast(context, none, error: true);
      } else {
        _ssid.text = name;
        _bssid.text = (id ?? '').toLowerCase();
      }
    } catch (_) {
      if (mounted) toast(context, none, error: true);
    } finally {
      if (mounted) setState(() => _wifiBusy = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast(context, context.t('common.required'), error: true);
    if (_loc && (double.tryParse(_lat.text) == null || double.tryParse(_lng.text) == null)) return toast(context, context.t('rules.need_location'), error: true);
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final body = {
        'name': _name.text.trim(),
        'isActive': _active,
        'locationEnabled': _loc,
        'locationLat': _loc ? double.tryParse(_lat.text) : null,
        'locationLng': _loc ? double.tryParse(_lng.text) : null,
        'locationRadiusKm': _loc ? (double.tryParse(_radius.text) ?? 200) / 1000 : null,
        'wifiEnabled': _wifi,
        'wifiSsid': _wifi ? _ssid.text.trim() : null,
        'wifiBssid': _wifi ? _bssid.text.trim() : null,
        'matchMode': _both ? 'all' : 'any',
      };
      final api = ref.read(apiProvider);
      widget.existing == null ? await api.post('/attendance-rules', body) : await api.put('/attendance-rules/${jInt(widget.existing!, 'id')}', body);
      ref.invalidate(_rulesProvider);
      if (mounted) toast(context, context.t('common.saved'));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppField(controller: _name, label: context.t('common.name'), icon: Icons.label_outline_rounded),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('rules.active')), subtitle: Text(context.t('rules.active_hint')), value: _active, onChanged: (v) => setState(() => _active = v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('rules.require_location')), value: _loc, onChanged: (v) => setState(() => _loc = v)),
        if (_loc) ...[
          Row(children: [
            Expanded(child: AppField(controller: _lat, label: context.t('rules.lat'), keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true))),
            const SizedBox(width: 12),
            Expanded(child: AppField(controller: _lng, label: context.t('rules.lng'), keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true))),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _locating ? null : _here, icon: _locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded), label: Text(context.t('rules.use_here')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46))),
          const SizedBox(height: 12),
          AppField(controller: _radius, label: context.t('rules.radius'), icon: Icons.radar_rounded, keyboard: TextInputType.number),
        ],
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('rules.require_wifi')), value: _wifi, onChanged: (v) => setState(() => _wifi = v)),
        if (_wifi) ...[
          AppField(controller: _ssid, label: context.t('rules.ssid'), icon: Icons.wifi_rounded),
          const SizedBox(height: 12),
          AppField(controller: _bssid, label: '${context.t('rules.bssid')} (${context.t('common.optional')})', icon: Icons.router_outlined),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _wifiBusy ? null : _thisWifi, icon: _wifiBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find_rounded), label: Text(context.t('rules.use_wifi')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46))),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.t('rules.bssid_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.35))),
        ],
        if (_loc && _wifi) SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('rules.both')), subtitle: Text(_both ? context.t('rules.both_on') : context.t('rules.both_off')), value: _both, onChanged: (v) => setState(() => _both = v)),
        const SizedBox(height: 18),
        LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
        if (widget.existing != null)
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              if (!await confirmDialog(context, title: context.t('common.delete'), danger: true, confirmLabel: context.t('common.delete'))) return;
              try {
                await ref.read(apiProvider).delete('/attendance-rules/${jInt(widget.existing!, 'id')}');
                ref.invalidate(_rulesProvider);
                nav.pop();
              } on ApiException catch (e) {
                if (context.mounted) toast(context, e.message, error: true);
              }
            },
            child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
          ),
      ]);
}
