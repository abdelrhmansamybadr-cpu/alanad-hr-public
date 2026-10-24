import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/config.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import 'premium_common.dart';

final fieldVisitsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/field/visits')));
final fieldSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final u = ref.watch(sessionProvider).user;
  if (u == null || !(u.role != 'employee' || u.isTeamLead)) return null;
  try {
    return asMap(await ref.read(apiProvider).get('/field/summary'));
  } catch (_) {
    return null;
  }
});

String _dur(BuildContext c, int minutes) => minutes >= 60 ? c.t('fld.h_m', {'h': minutes ~/ 60, 'm': minutes % 60}) : c.t('fld.m', {'m': minutes});
String _km(int meters) => meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';

/// Where am I? Asks for permission when needed; returns null (and tells the person why) when it cannot.
Future<Position?> _locate(BuildContext context) async {
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    if (context.mounted) toast(context, context.t('fld.no_location_permission'), error: true);
    return null;
  }
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) toast(context, context.t('fld.gps_off'), error: true);
    return null;
  }
  try {
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 20));
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    if (last == null && context.mounted) toast(context, context.t('fld.no_fix'), error: true);
    return last;
  }
}

Future<String?> _takePhoto() async {
  final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1280, imageQuality: 70);
  if (f == null) return null;
  return base64Encode(await f.readAsBytes());
}

// ====================================================================================== list

class FieldVisitsScreen extends ConsumerWidget {
  const FieldVisitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(fieldVisitsProvider);
    final me = ref.watch(sessionProvider).user;
    final canStart = me?.employeeId != null;
    final summary = ref.watch(fieldSummaryProvider).valueOrNull;
    final active = data.valueOrNull?.where((v) => v['status'] == 'active' && v['employeeId'] == me?.employeeId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('fld.title'))),
      floatingActionButton: canStart && active == null && data.hasValue
          ? FloatingActionButton.extended(onPressed: () => showAppSheet(context, title: context.t('fld.start'), child: const _StartSheet()), icon: const Icon(Icons.play_arrow_rounded), label: Text(context.t('fld.start')))
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(fieldVisitsProvider);
          ref.invalidate(fieldSummaryProvider);
          await ref.read(fieldVisitsProvider.future).catchError((_) => <Map<String, dynamic>>[]);
        },
        child: data.when(
          loading: () => const SkeletonList(),
          error: (e, _) => isFeatureOff(e) ? const FeatureOff() : ErrorState(e, onRetry: () => ref.invalidate(fieldVisitsProvider)),
          data: (rows) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), physics: const AlwaysScrollableScrollPhysics(), children: [
            if (active != null)
              AppCard(
                gradient: brandGradient(context),
                onTap: () => context.push('/field/active/${jInt(active, 'id')}'),
                child: Row(children: [
                  const Icon(Icons.directions_walk_rounded, color: Colors.white, size: 30),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('fld.in_progress'), style: const TextStyle(color: Colors.white70)),
                    Text(jStr(active, 'customerName'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                  ])),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ]),
              ),
            if (summary != null && asMapList(summary['people']).isNotEmpty) ...[
              SectionHeader(context.t('fld.week')),
              AppCard(
                child: Column(children: [
                  Row(children: [
                    Expanded(child: _Num(context.t('fld.visits'), '${jInt(asMap(summary['totals']), 'visits')}')),
                    Expanded(child: _Num('km', '${jDouble(asMap(summary['totals']), 'km')}')),
                    Expanded(child: _Num(context.t('fld.time'), _dur(context, jInt(asMap(summary['totals']), 'minutes')))),
                  ]),
                  const Divider(height: 22),
                  for (final p in asMapList(summary['people']))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text(jStr(p, 'employeeName'), style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text('${jInt(p, 'visits')} · ${jDouble(p, 'km')} km · ${context.t('fld.signed_n', {'n': jInt(p, 'signed')})}', style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
                      ]),
                    ),
                ]),
              ),
            ],
            SectionHeader(context.t('fld.history')),
            if (rows.isEmpty) SizedBox(height: 280, child: EmptyState(icon: Icons.pin_drop_rounded, title: context.t('fld.empty'), subtitle: context.t('fld.empty_hint'))),
            for (final v in rows) Padding(padding: const EdgeInsets.only(bottom: 10), child: _VisitTile(v, mine: v['employeeId'] == me?.employeeId)),
          ]),
        ),
      ),
    );
  }
}

class _Num extends StatelessWidget {
  final String label;
  final String value;
  const _Num(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), Text(label, style: TextStyle(color: context.colors.subtext, fontSize: 12))]);
}

class _VisitTile extends StatelessWidget {
  final Map<String, dynamic> v;
  final bool mine;
  const _VisitTile(this.v, {required this.mine});

  @override
  Widget build(BuildContext context) {
    final status = jStr(v, 'status');
    final flags = ((v['flags'] as List?) ?? const []).map((e) => '$e').toList();
    final color = status == 'active' ? context.colors.info : (status == 'cancelled' ? context.colors.subtext : (flags.isEmpty ? context.colors.success : context.colors.warning));
    final started = parseUtc(jStrN(v, 'startedAt'));
    return RowTile(
      leading: IconBadge(status == 'done' ? Icons.task_alt_rounded : (status == 'active' ? Icons.directions_walk_rounded : Icons.cancel_outlined), color: color, size: 42),
      title: jStr(v, 'customerName'),
      subtitle: [if (!mine) jStr(v, 'employeeName'), if (started != null) '${started.day}/${started.month} ${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}', _dur(context, jInt(v, 'minutes')), _km(jInt(v, 'distanceM'))].where((e) => e.isNotEmpty).join(' · '),
      trailing: status == 'active' ? Pill(context.t('fld.s_active'), color: color) : (flags.isNotEmpty ? Pill(context.t('fld.gaps_n', {'n': flags.length}), color: context.colors.warning) : null),
      onTap: () => status == 'active' && mine ? context.push('/field/active/${jInt(v, 'id')}') : context.push('/field/visit/${jInt(v, 'id')}'),
    );
  }
}

// ====================================================================================== start

class _StartSheet extends ConsumerStatefulWidget {
  const _StartSheet();
  @override
  ConsumerState<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends ConsumerState<_StartSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _addr = TextEditingController();
  final _why = TextEditingController();
  String? _photo;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _addr, _why]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _go() async {
    if (_name.text.trim().isEmpty) {
      toast(context, context.t('fld.need_name'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final pos = await _locate(context);
      if (pos == null) return;
      final r = asMap(await ref.read(apiProvider).post('/field/visits', {
        'customer_name': _name.text.trim(),
        'customer_phone': _phone.text.trim(),
        'address': _addr.text.trim(),
        'purpose': _why.text.trim(),
        'lat': pos.latitude,
        'lng': pos.longitude,
        if (_photo != null) 'photo_base64': _photo,
      }));
      ref.invalidate(fieldVisitsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      context.push('/field/active/${jInt(r, 'id')}');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppField(controller: _name, label: context.t('fld.customer'), icon: Icons.storefront_rounded, capitalization: TextCapitalization.words),
        const SizedBox(height: 10),
        AppField(controller: _phone, label: context.t('fld.phone'), icon: Icons.phone_rounded, keyboard: TextInputType.phone),
        const SizedBox(height: 10),
        AppField(controller: _addr, label: context.t('fld.address'), icon: Icons.place_rounded),
        const SizedBox(height: 10),
        AppField(controller: _why, label: context.t('fld.purpose'), icon: Icons.flag_rounded),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () async {
            final p = await _takePhoto();
            if (p != null && mounted) setState(() => _photo = p);
          },
          icon: Icon(_photo == null ? Icons.photo_camera_rounded : Icons.check_circle_rounded, color: _photo == null ? null : context.colors.success),
          label: Text(context.t(_photo == null ? 'fld.take_photo' : 'fld.photo_taken')),
        ),
        const SizedBox(height: 14),
        Text(context.t('fld.start_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 12),
        LoadingButton(label: context.t('fld.start_now'), loading: _busy, icon: Icons.play_arrow_rounded, onPressed: _go),
      ]);
}

// ====================================================================================== active

class FieldActiveScreen extends ConsumerStatefulWidget {
  final int id;
  const FieldActiveScreen({super.key, required this.id});
  @override
  ConsumerState<FieldActiveScreen> createState() => _FieldActiveScreenState();
}

class _FieldActiveScreenState extends ConsumerState<FieldActiveScreen> {
  Map<String, dynamic>? _visit;
  Object? _error;
  Timer? _tick;
  final _buffer = <Map<String, dynamic>>[];
  int _distance = 0;
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sampling = false;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await ref.read(apiProvider).get('/field/visits/${widget.id}'));
      if (!mounted) return;
      setState(() {
        _visit = r;
        _distance = jInt(r, 'distanceM');
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Every 20 seconds note where I am; every 3 notes (or on finish) send them. A failed send keeps them for the next try.
  Future<void> _onTick() async {
    if (!mounted || _visit == null || _visit!['status'] != 'active') return;
    setState(() {}); // keeps the timer on screen moving
    if (DateTime.now().difference(_lastSample).inSeconds < 20 || _sampling) return;
    _sampling = true;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 12));
      _lastSample = DateTime.now();
      _buffer.add({'lat': pos.latitude, 'lng': pos.longitude, 't': DateTime.now().millisecondsSinceEpoch ~/ 1000});
      if (_buffer.length >= 3) await _flush();
    } catch (_) {
      // no fix this time; the next tick tries again
    } finally {
      _sampling = false;
    }
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    try {
      final r = asMap(await ref.read(apiProvider).post('/field/visits/${widget.id}/points', {'points': batch}));
      _buffer.removeRange(0, batch.length);
      if (mounted) setState(() => _distance = jInt(r, 'distanceM', _distance));
    } catch (_) {
      // keep the points, send them with the next batch
    }
  }

  Future<void> _cancel() async {
    final ok = await confirmDialog(context, title: context.t('fld.cancel_q'), message: context.t('fld.cancel_msg'), danger: true, confirmLabel: context.t('fld.cancel'));
    if (!ok) return;
    try {
      await ref.read(apiProvider).post('/field/visits/${widget.id}/cancel');
      ref.invalidate(fieldVisitsProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(appBar: AppBar(), body: ErrorState(_error!, onRetry: () { setState(() => _error = null); _load(); }));
    final v = _visit;
    if (v == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final started = parseUtc(jStrN(v, 'startedAt')) ?? DateTime.now();
    final elapsed = DateTime.now().difference(started);
    final mm = elapsed.inMinutes;
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: Text(jStr(v, 'customerName')), actions: [if (v['status'] == 'active') IconButton(tooltip: context.t('fld.cancel'), icon: const Icon(Icons.close_rounded), onPressed: _cancel)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          gradient: brandGradient(context),
          child: Column(children: [
            Text(context.t('fld.in_progress'), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('${mm.toString().padLeft(2, '0')}:$ss', style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800, fontFeatures: [ui.FontFeature.tabularFigures()])),
            const SizedBox(height: 6),
            Text('${_km(_distance)} · ${context.t('fld.points_n', {'n': _buffer.length})}', style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(children: [
            if (jStrN(v, 'customerPhone') != null) InfoRow(icon: Icons.phone_rounded, label: context.t('fld.phone'), value: jStr(v, 'customerPhone'), onTap: () => launchUrl(Uri.parse('tel:${jStr(v, 'customerPhone')}'))),
            if (jStrN(v, 'address') != null) InfoRow(icon: Icons.place_rounded, label: context.t('fld.address'), value: jStr(v, 'address')),
            if (jStrN(v, 'purpose') != null) InfoRow(icon: Icons.flag_rounded, label: context.t('fld.purpose'), value: jStr(v, 'purpose')),
            InfoRow(icon: Icons.photo_camera_rounded, label: context.t('fld.photo'), value: context.t(v['hasPhoto'] == true ? 'fld.yes' : 'fld.no')),
          ]),
        ),
        const SizedBox(height: 10),
        Text(context.t('fld.foreground_note'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 18),
        LoadingButton(label: context.t('fld.finish'), icon: Icons.task_alt_rounded, onPressed: () async {
          await _flush();
          if (!context.mounted) return;
          final done = await showAppSheet<bool>(context, title: context.t('fld.finish'), child: _FinishSheet(id: widget.id, hasPhoto: v['hasPhoto'] == true));
          if (done == true && context.mounted) {
            ref.invalidate(fieldVisitsProvider);
            ref.invalidate(fieldSummaryProvider);
            context.pushReplacement('/field/visit/${widget.id}');
          }
        }),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------- signature

class SignaturePad extends StatefulWidget {
  final void Function(List<List<Offset>> strokes) onChanged;
  const SignaturePad({super.key, required this.onChanged});
  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];

  void clear() {
    setState(() => _strokes.clear());
    widget.onChanged(_strokes);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          height: 170,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.colors.border)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GestureDetector(
              onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
              onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
              onPanEnd: (_) => widget.onChanged(_strokes),
              child: CustomPaint(painter: _SigPainter(_strokes), size: Size.infinite),
            ),
          ),
        ),
        Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: clear, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(context.t('fld.clear')))),
      ]);
}

class _SigPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SigPainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black..strokeWidth = 3..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) canvas.drawPoints(ui.PointMode.points, s, p);
      for (var i = 1; i < s.length; i++) {
        canvas.drawLine(s[i - 1], s[i], p);
      }
    }
  }

  @override
  bool shouldRepaint(_SigPainter old) => true;
}

Future<String?> _signaturePng(List<List<Offset>> strokes, Size box) async {
  if (strokes.isEmpty) return null;
  const w = 600.0;
  final scale = w / box.width;
  final h = box.height * scale;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
  canvas.scale(scale);
  _SigPainter(strokes).paint(canvas, box);
  final img = await rec.endRecording().toImage(w.round(), h.round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data == null ? null : base64Encode(data.buffer.asUint8List());
}

class _FinishSheet extends ConsumerStatefulWidget {
  final int id;
  final bool hasPhoto;
  const _FinishSheet({required this.id, required this.hasPhoto});
  @override
  ConsumerState<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends ConsumerState<_FinishSheet> {
  List<List<Offset>> _strokes = [];
  final _name = TextEditingController();
  final _notes = TextEditingController();
  final _padKey = GlobalKey<_SignaturePadState>();
  String? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final box = Size(MediaQuery.of(context).size.width - 40, 170);
      final pos = await _locate(context);
      if (pos == null) return;
      final sig = await _signaturePng(_strokes, box);
      await ref.read(apiProvider).post('/field/visits/${widget.id}/finish', {
        'lat': pos.latitude,
        'lng': pos.longitude,
        if (sig != null) 'signature_base64': sig,
        'signed_name': _name.text.trim(),
        'notes': _notes.text.trim(),
        if (_photo != null) 'photo_base64': _photo,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('fld.sign_here'), style: context.text.titleSmall),
        const SizedBox(height: 8),
        SignaturePad(key: _padKey, onChanged: (s) => _strokes = s.map((e) => List<Offset>.from(e)).toList()),
        AppField(controller: _name, label: context.t('fld.signed_name'), icon: Icons.person_rounded),
        const SizedBox(height: 10),
        AppField(controller: _notes, label: context.t('fld.notes'), maxLines: 3),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : () async {
            final p = await _takePhoto();
            if (p != null && mounted) setState(() => _photo = p);
          },
          icon: Icon(_photo != null || widget.hasPhoto ? Icons.check_circle_rounded : Icons.photo_camera_rounded, color: _photo != null || widget.hasPhoto ? context.colors.success : null),
          label: Text(context.t(widget.hasPhoto && _photo == null ? 'fld.photo_have' : (_photo == null ? 'fld.take_photo' : 'fld.photo_taken'))),
        ),
        const SizedBox(height: 16),
        LoadingButton(label: context.t('fld.finish'), loading: _busy, icon: Icons.task_alt_rounded, onPressed: _finish),
      ]);
}

// ====================================================================================== details

class FieldVisitScreen extends ConsumerStatefulWidget {
  final int id;
  const FieldVisitScreen({super.key, required this.id});
  @override
  ConsumerState<FieldVisitScreen> createState() => _FieldVisitScreenState();
}

class _FieldVisitScreenState extends ConsumerState<FieldVisitScreen> {
  late final Future<dynamic> _f = ref.read(apiProvider).get('/field/visits/${widget.id}');

  Widget _img(String kind) {
    final headers = {'Authorization': 'Bearer ${ref.read(apiProvider).token}'};
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network('${AppConfig.baseUrl}/api/field/file/${widget.id}/$kind', headers: headers, height: 190, width: double.infinity, fit: kind == 'signature' ? BoxFit.contain : BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(height: 90, alignment: Alignment.center, color: context.colors.surfaceAlt, child: Icon(Icons.broken_image_outlined, color: context.colors.subtext))),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.t('fld.visit'))),
        body: FutureBuilder<dynamic>(
          future: _f,
          builder: (context, snap) {
            if (snap.hasError) return ErrorState(snap.error!);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final v = asMap(snap.data);
            final route = asMapList(v['route']);
            final flags = ((v['flags'] as List?) ?? const []).map((e) => '$e').toList();
            final lat = v['startLat'];
            final lng = v['startLng'];
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(jStr(v, 'customerName'), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text([jStr(v, 'employeeName'), _dur(context, jInt(v, 'minutes')), _km(jInt(v, 'distanceM'))].where((e) => e.isNotEmpty).join(' · '), style: TextStyle(color: context.colors.subtext)),
              if (flags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [for (final f in flags) Pill(context.t('fld.flag_$f'), color: context.colors.warning, icon: Icons.warning_amber_rounded)]),
              ],
              const SizedBox(height: 14),
              AppCard(
                child: Column(children: [
                  if (jStrN(v, 'customerPhone') != null) InfoRow(icon: Icons.phone_rounded, label: context.t('fld.phone'), value: jStr(v, 'customerPhone')),
                  if (jStrN(v, 'address') != null) InfoRow(icon: Icons.place_rounded, label: context.t('fld.address'), value: jStr(v, 'address')),
                  if (jStrN(v, 'purpose') != null) InfoRow(icon: Icons.flag_rounded, label: context.t('fld.purpose'), value: jStr(v, 'purpose')),
                  if (jStrN(v, 'notes') != null) InfoRow(icon: Icons.notes_rounded, label: context.t('fld.notes'), value: jStr(v, 'notes')),
                  if (jStrN(v, 'signedName') != null) InfoRow(icon: Icons.draw_rounded, label: context.t('fld.signed_name'), value: jStr(v, 'signedName')),
                ]),
              ),
              if (route.length > 1) ...[
                SectionHeader(context.t('fld.route')),
                Container(
                  height: 220,
                  decoration: BoxDecoration(color: context.colors.surfaceAlt, borderRadius: BorderRadius.circular(18)),
                  child: ClipRRect(borderRadius: BorderRadius.circular(18), child: CustomPaint(painter: _RoutePainter(route.map((p) => Offset(jDouble(p, 'lng'), jDouble(p, 'lat'))).toList(), context.scheme.primary, context.colors.success, context.colors.danger), size: Size.infinite)),
                ),
                if (lat != null && lng != null) TextButton.icon(onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.map_rounded), label: Text(context.t('fld.open_maps'))),
              ],
              if (v['hasPhoto'] == true) ...[SectionHeader(context.t('fld.photo')), _img('photo')],
              if (v['hasSignature'] == true) ...[SectionHeader(context.t('fld.signature')), Container(color: Colors.white, child: _img('signature'))],
            ]);
          },
        ),
      );
}

class _RoutePainter extends CustomPainter {
  final List<Offset> pts; // x = lng, y = lat
  final Color line, start, end;
  _RoutePainter(this.pts, this.line, this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    final meanLat = pts.map((p) => p.dy).reduce((a, b) => a + b) / pts.length;
    final k = math.cos(meanLat * math.pi / 180);
    final xs = pts.map((p) => p.dx * k), ys = pts.map((p) => p.dy);
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max), minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final w = math.max(maxX - minX, 1e-6), h = math.max(maxY - minY, 1e-6);
    const pad = 22.0;
    final s = math.min((size.width - pad * 2) / w, (size.height - pad * 2) / h);
    Offset map(Offset p) => Offset(pad + (p.dx * k - minX) * s + ((size.width - pad * 2) - w * s) / 2, size.height - pad - (p.dy - minY) * s - ((size.height - pad * 2) - h * s) / 2);
    final path = Path()..moveTo(map(pts.first).dx, map(pts.first).dy);
    for (final p in pts.skip(1)) {
      path.lineTo(map(p).dx, map(p).dy);
    }
    canvas.drawPath(path, Paint()..color = line..strokeWidth = 4..style = PaintingStyle.stroke..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
    canvas.drawCircle(map(pts.first), 7, Paint()..color = start);
    canvas.drawCircle(map(pts.last), 7, Paint()..color = end);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.pts != pts;
}
