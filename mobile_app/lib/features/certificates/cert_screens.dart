import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/responsive.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';
import 'cert_model.dart';
import 'cert_render.dart';

final certTemplatesProvider = FutureProvider.autoDispose<List<CertTemplate>>((ref) async => [for (final m in asMapList(await ref.read(apiProvider).get('/certificates/templates'))) CertTemplate.fromApi(m)]);
final certHistoryProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/certificates')));
final certClosuresProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/certificates/closures')));
final certSamplesProvider = FutureProvider.autoDispose<List<CertTemplate>>((ref) async => [for (final m in asMapList(await ref.read(apiProvider).get('/certificates/samples'))) CertTemplate.fromApi(m)]);

String _defaultTitle(BuildContext c, CertTemplate t) {
  const en = {'experience': 'Certificate of Experience', 'end_of_service': 'End of Service Certificate', 'clearance': 'Clearance Letter', 'custom': 'Certificate'};
  const ar = {'experience': 'شهادة خبرة', 'end_of_service': 'شهادة إنهاء خدمة', 'clearance': 'إخلاء طرف', 'custom': 'شهادة'};
  return (t.lang == 'ar' ? ar : en)[t.kind] ?? (t.lang == 'ar' ? 'شهادة' : 'Certificate');
}

/// A small picture of a design, drawn with sample data (or the given values).
class CertThumb extends ConsumerStatefulWidget {
  final CertTemplate template;
  final Map<String, String>? values;
  const CertThumb(this.template, {super.key, this.values});
  @override
  ConsumerState<CertThumb> createState() => _CertThumbState();
}

class _CertThumbState extends ConsumerState<CertThumb> {
  Map<int, ui.Image> _images = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CertThumb old) {
    super.didUpdateWidget(old);
    if (old.template.bgAssetId != widget.template.bgAssetId || old.template.id != widget.template.id) _load();
  }

  Future<void> _load() async {
    final m = await loadCertImages(ref.read(apiProvider), widget.template);
    if (mounted) setState(() => _images = m);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final laid = layoutCert(t, widget.values ?? sampleCertValues(t.lang), _images);
    return AspectRatio(
      aspectRatio: t.width / t.height,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: context.colors.border), borderRadius: BorderRadius.circular(6)),
        child: ClipRRect(borderRadius: BorderRadius.circular(5), child: CustomPaint(painter: CertPainter(t, laid, _images))),
      ),
    );
  }
}

Future<void> openCertFile(BuildContext context, WidgetRef ref, int id, String serial, {bool share = false}) async {
  try {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$serial.pdf';
    await ref.read(apiProvider).download('/api/certificates/$id/file?type=pdf', path);
    if (share) {
      await Share.shareXFiles([XFile(path, mimeType: 'application/pdf')]);
    } else {
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done && context.mounted) toast(context, context.t('cert.no_viewer'), error: true);
    }
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
}

/// Plan (or do right now) the closing of an employee's account.
Future<bool> showCloseSheet(BuildContext context, WidgetRef ref, {required int employeeId, int? certificateId, String? leaveDate}) async {
  var mode = 'in';
  var days = 7;
  DateTime? date;
  var busy = false;
  final ok = await showAppSheet<bool>(
    context,
    title: context.t('cert.close_title'),
    child: StatefulBuilder(builder: (ctx, set) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ctx.t('cert.close_hint'), style: TextStyle(color: ctx.colors.subtext, height: 1.4)),
        const SizedBox(height: 14),
        SegmentBar(labels: [ctx.t('cert.c_now'), ctx.t('cert.c_in'), ctx.t('cert.c_date')], index: ['now', 'in', 'date'].indexOf(mode), onChanged: (i) => set(() => mode = ['now', 'in', 'date'][i])),
        const SizedBox(height: 14),
        if (mode == 'in')
          Wrap(spacing: 8, children: [
            for (final d in [1, 3, 7, 14, 30]) ChoiceChip(label: Text('$d ${ctx.t('cert.days')}'), selected: days == d, onSelected: (_) => set(() => days = d)),
          ]),
        if (mode == 'date')
          OutlinedButton.icon(
            icon: const Icon(Icons.event_rounded),
            label: Text(date == null ? ctx.t('cert.pick_date') : fmtDate(ctx, date!)),
            onPressed: () async {
              final d = await showDatePicker(context: ctx, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
              if (d != null) set(() => date = d);
            },
          ),
        const SizedBox(height: 18),
        LoadingButton(
          label: ctx.t('cert.close_btn'),
          loading: busy,
          color: mode == 'now' ? ctx.colors.danger : null,
          onPressed: () async {
            if (mode == 'date' && date == null) return toast(ctx, ctx.t('cert.pick_date'), error: true);
            set(() => busy = true);
            try {
              await ref.read(apiProvider).post('/certificates/closures', {
                'employeeId': employeeId,
                if (certificateId != null) 'certificateId': certificateId,
                if (leaveDate != null) 'leaveDate': leaveDate,
                'mode': mode,
                'days': days,
                if (date != null) 'date': ymd(date!),
              });
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            } on ApiException catch (e) {
              if (ctx.mounted) toast(ctx, e.message, error: true);
              set(() => busy = false);
            }
          },
        ),
      ]);
    }),
  );
  if (ok == true) {
    ref.invalidate(certClosuresProvider);
    ref.invalidate(employeesProvider);
    ref.invalidate(certHistoryProvider);
  }
  return ok == true;
}

// =============================================================== the page

class CertificatesScreen extends ConsumerStatefulWidget {
  final int? employeeId;
  const CertificatesScreen({super.key, this.employeeId});
  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('cert.title'))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SegmentBar(labels: [context.t('cert.t_create'), context.t('cert.t_designs'), context.t('cert.t_history')], index: _tab, onChanged: (i) => setState(() => _tab = i))),
        Expanded(child: [_IssuePane(employeeId: widget.employeeId), const _DesignsPane(), const _HistoryPane()][_tab]),
      ]),
    );
  }
}

// ------------------------------------------------------------------ create & send

class _IssuePane extends ConsumerStatefulWidget {
  final int? employeeId;
  const _IssuePane({this.employeeId});
  @override
  ConsumerState<_IssuePane> createState() => _IssuePaneState();
}

class _IssuePaneState extends ConsumerState<_IssuePane> {
  Employee? _emp;
  CertTemplate? _tpl;
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _email = TextEditingController();
  DateTime? _start;
  DateTime _end = DateTime.now();
  bool _sendEmail = true;
  String _closeMode = 'none';
  int _days = 7;
  DateTime? _closeDate;
  bool _busy = false;
  Map<String, dynamic>? _done;
  bool _presetApplied = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _email.dispose();
    super.dispose();
  }

  void _setEmp(Employee e) {
    setState(() {
      _emp = e;
      _start = e.startDate;
      _end = e.terminationDate ?? DateTime.now();
      _email.text = e.email;
      _done = null;
    });
  }

  void _setTpl(CertTemplate t) {
    setState(() {
      _tpl = t;
      _title.text = _defaultTitle(context, t);
    });
  }

  Future<void> _pickEmployee(List<Employee> all) async {
    final e = await showAppSheet<Employee>(
      context,
      title: context.t('cert.pick_emp'),
      child: StatefulBuilder(builder: (ctx, set) {
        var q = '';
        return StatefulBuilder(builder: (ctx, set2) {
          final list = all.where((p) => q.isEmpty || '${p.fullName} ${p.email}'.toLowerCase().contains(q.toLowerCase())).take(80).toList();
          return Column(children: [
            TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: ctx.t('common.search')), onChanged: (v) => set2(() => q = v)),
            const SizedBox(height: 8),
            for (final p in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(name: p.fullName, url: p.avatar, size: 40),
                title: Text(p.fullName),
                subtitle: Text(p.status == 'inactive' ? '${p.position} · ${ctx.t('cert.gone')}' : p.position),
                onTap: () => Navigator.of(ctx).pop(p),
              ),
          ]);
        });
      }),
    );
    if (e != null) _setEmp(e);
  }

  Future<void> _date(DateTime? initial, ValueChanged<DateTime> done) async {
    final d = await showDatePicker(context: context, initialDate: initial ?? DateTime.now(), firstDate: DateTime(1980), lastDate: DateTime(2100));
    if (d != null) setState(() => done(d));
  }

  Map<String, String> _values({String serial = 'CERT-????', DateTime? issue}) {
    final t = _tpl!;
    final e = _emp;
    final company = ref.read(sessionProvider).company?.name ?? '';
    if (e == null) return sampleCertValues(t.lang);
    return buildCertValues(
      firstName: e.firstName, lastName: e.lastName, position: e.position, department: e.departmentName ?? '', company: company,
      serial: serial, issueDate: issue ?? DateTime.now(), startDate: _start, endDate: _end, lang: t.lang, note: _note.text.trim(),
    );
  }

  Future<void> _issue() async {
    final e = _emp, t = _tpl;
    if (e == null || t == null) return;
    if (_sendEmail && !RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim())) return toast(context, context.t('cert.bad_email'), error: true);
    if (_closeMode == 'date' && _closeDate == null) return toast(context, context.t('cert.pick_date'), error: true);
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      final d = asMap(await api.post('/certificates/draft', {'employeeId': e.id, 'templateId': t.id}));
      final issue = DateTime.tryParse(jStr(d, 'issueDate')) ?? DateTime.now();
      final company = jStr(d, 'company');
      final v = buildCertValues(
        firstName: e.firstName, lastName: e.lastName, position: e.position, department: e.departmentName ?? '', company: company.isEmpty ? (ref.read(sessionProvider).company?.name ?? '') : company,
        serial: jStr(d, 'serial'), issueDate: issue, startDate: _start, endDate: _end, lang: t.lang, note: _note.text.trim(),
      );
      final imgs = await loadCertImages(api, t);
      final png = await renderCertPng(t, v, imgs, scale: 1.5);
      final already = e.status == 'inactive';
      final res = asMap(await api.post('/certificates/${jInt(d, 'id')}/issue', {
        'imageData': 'data:image/png;base64,${base64Encode(png)}',
        'title': _title.text.trim(),
        'width': t.width.round(),
        'height': t.height.round(),
        'values': jsonEncode(v),
        'sendEmail': _sendEmail,
        if (_sendEmail && _email.text.trim() != e.email) 'emailTo': _email.text.trim(),
        'leaveDate': ymd(_end),
        'close': (_closeMode == 'none' || already) ? {'mode': 'none'} : {'mode': _closeMode, 'days': _days, if (_closeDate != null) 'date': ymd(_closeDate!)},
      }));
      ref.invalidate(certHistoryProvider);
      ref.invalidate(certClosuresProvider);
      ref.invalidate(employeesProvider);
      if (mounted) {
        setState(() => _done = res);
        toast(context, context.t('cert.created'));
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tpls = ref.watch(certTemplatesProvider);
    final emps = ref.watch(employeesProvider(''));
    return AsyncBody<List<CertTemplate>>(
      value: tpls,
      onRetry: () => ref.invalidate(certTemplatesProvider),
      builder: (templates) {
        if (templates.isEmpty) {
          return EmptyState(icon: Icons.workspace_premium_rounded, title: context.t('cert.no_design'), subtitle: context.t('cert.no_design_hint'));
        }
        if (_tpl == null) WidgetsBinding.instance.addPostFrameCallback((_) => _setTpl(templates.first));
        final all = emps.valueOrNull ?? const <Employee>[];
        if (!_presetApplied && widget.employeeId != null && all.isNotEmpty) {
          _presetApplied = true;
          final e = all.where((p) => p.id == widget.employeeId).firstOrNull;
          if (e != null) WidgetsBinding.instance.addPostFrameCallback((_) => _setEmp(e));
        }
        final t = _tpl ?? templates.first;
        final alreadyOut = _emp?.status == 'inactive';
        final previewCard = AppCard(
            padding: const EdgeInsets.all(10),
            child: _emp == null ? SizedBox(height: 120, child: Center(child: Text(context.t('cert.choose_emp'), style: TextStyle(color: context.colors.subtext)))) : CertThumb(t, values: _values()),
          );
        final formCard = AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: all.isEmpty ? null : () => _pickEmployee(all),
                child: InputDecorator(decoration: InputDecoration(labelText: context.t('cert.employee'), prefixIcon: const Icon(Icons.person_outline_rounded), suffixIcon: const Icon(Icons.arrow_drop_down_rounded)), child: Text(_emp?.fullName ?? context.t('cert.choose'))),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: templates.any((x) => x.id == _tpl?.id) ? _tpl?.id : templates.first.id,
                decoration: InputDecoration(labelText: context.t('cert.design'), prefixIcon: const Icon(Icons.palette_outlined)),
                items: [for (final x in templates) DropdownMenuItem<int?>(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => _setTpl(templates.firstWhere((x) => x.id == v)),
              ),
              const SizedBox(height: 12),
              AppField(controller: _title, label: context.t('cert.title_field'), icon: Icons.title_rounded, onChanged: (_) {}),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _dateBox(context.t('cert.started'), _start, () => _date(_start, (d) => _start = d))),
                const SizedBox(width: 10),
                Expanded(child: _dateBox(context.t('cert.leaving'), _end, () => _date(_end, (d) => _end = d))),
              ]),
              const SizedBox(height: 12),
              AppField(controller: _note, label: context.t('cert.note'), icon: Icons.notes_rounded, maxLines: 2, onChanged: (_) => setState(() {})),
              const Divider(height: 28),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _sendEmail, onChanged: (v) => setState(() => _sendEmail = v), title: Text(context.t('cert.email_it'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              if (_sendEmail) AppField(controller: _email, label: context.t('auth.email.label'), icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress),
              if (_emp != null && !alreadyOut) ...[
                const Divider(height: 28),
                Text(context.t('cert.then_account'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in [('none', 'cert.a_none'), ('now', 'cert.a_now'), ('in', 'cert.a_in'), ('date', 'cert.a_date')]) ChoiceChip(label: Text(context.t(m.$2)), selected: _closeMode == m.$1, onSelected: (_) => setState(() => _closeMode = m.$1)),
                ]),
                if (_closeMode == 'in') ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, children: [for (final d in [1, 3, 7, 14, 30]) ChoiceChip(label: Text('$d ${context.t('cert.days')}'), selected: _days == d, onSelected: (_) => setState(() => _days = d))]),
                ],
                if (_closeMode == 'date') ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded),
                    label: Text(_closeDate == null ? context.t('cert.pick_date') : fmtDate(context, _closeDate!)),
                    onPressed: () async {
                      final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
                      if (d != null) setState(() => _closeDate = d);
                    },
                  ),
                ],
                const SizedBox(height: 8),
                Text(context.t('cert.close_hint'), style: TextStyle(fontSize: 12, color: context.colors.subtext, height: 1.4)),
              ],
              if (alreadyOut) Padding(padding: const EdgeInsets.only(top: 14), child: Text(context.t('cert.already_closed'), style: TextStyle(fontSize: 12, color: context.colors.subtext))),
              const SizedBox(height: 18),
              LoadingButton(label: _sendEmail ? context.t('cert.create_send') : context.t('cert.create'), icon: Icons.send_rounded, loading: _busy, onPressed: _emp == null ? null : _issue),
            ]),
          );
        final resultCard = _done == null ? null : _result();
        // Laptop: the form on the left, the certificate preview next to it. Phone: preview on top, then the form.
        if (context.isDesktop) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 470, child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 12, 40), children: [formCard, if (resultCard != null) ...[const SizedBox(height: 12), resultCard]])),
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 24, 40), children: [previewCard])),
          ]);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
          previewCard,
          const SizedBox(height: 12),
          formCard,
          if (resultCard != null) ...[const SizedBox(height: 12), resultCard],
        ]);
      },
    );
  }

  Widget _dateBox(String label, DateTime? v, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: InputDecorator(decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.event_rounded)), child: Text(v == null ? '—' : fmtDate(context, v), style: const TextStyle(fontSize: 13))),
      );

  Widget _result() {
    final d = _done!;
    final c = asMap(d['certificate']);
    final closure = d['closure'] is Map ? asMap(d['closure']) : null;
    final emailed = d['emailed'] == true;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.check_circle_rounded, color: context.colors.success),
          const SizedBox(width: 8),
          Expanded(child: Text('${jStr(c, 'serial')} — ${context.t('cert.ready')}', style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        if (_sendEmail) Text(emailed ? '${context.t('cert.emailed_to')} ${jStr(c, 'emailedTo')}' : context.t('cert.mail_failed'), style: TextStyle(color: emailed ? context.colors.success : context.colors.warning)),
        const SizedBox(height: 4),
        Text(closure != null ? '${context.t('cert.closing_on')} ${jStr(closure, 'closeAt').replaceFirst('T', ' ').substring(0, 16)}' : (_emp?.status == 'inactive' ? '' : context.t('cert.still_open')), style: TextStyle(color: closure != null ? null : context.colors.warning)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: () => openCertFile(context, ref, jInt(c, 'id'), jStr(c, 'serial')), icon: const Icon(Icons.picture_as_pdf_rounded), label: Text(context.t('cert.open_pdf')))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: () => openCertFile(context, ref, jInt(c, 'id'), jStr(c, 'serial'), share: true), icon: const Icon(Icons.ios_share_rounded), label: Text(context.t('common.share')))),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------ designs

class _DesignsPane extends ConsumerWidget {
  const _DesignsPane();

  Future<void> _edit(BuildContext context, WidgetRef ref, CertTemplate t) async {
    final saved = await context.push<bool>('/h/certificates/design', extra: t);
    if (saved == true) ref.invalidate(certTemplatesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tpls = ref.watch(certTemplatesProvider);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: () => _edit(context, ref, CertTemplate(lang: context.isAr ? 'ar' : 'en')), icon: const Icon(Icons.add_rounded), label: Text(context.t('cert.new_blank')))),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(context.t('cert.from_sample')),
            onPressed: () async {
              final picked = await showAppSheet<CertTemplate>(
                context,
                title: context.t('cert.choose_sample'),
                child: Consumer(builder: (ctx, r, _) {
                  final s = r.watch(certSamplesProvider);
                  return s.when(
                    loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => Text(errorText(ctx, e)),
                    data: (list) => Column(children: [
                      for (final t in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => Navigator.of(ctx).pop(t), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [CertThumb(t), const SizedBox(height: 4), Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700))])),
                        ),
                    ]),
                  );
                }),
              );
              if (picked != null && context.mounted) await _edit(context, ref, picked);
            },
          ),
        ),
      ]),
      const SizedBox(height: 14),
      AsyncBody<List<CertTemplate>>(
        value: tpls,
        onRetry: () => ref.invalidate(certTemplatesProvider),
        builder: (list) => list.isEmpty
            ? Padding(padding: const EdgeInsets.only(top: 40), child: EmptyState(icon: Icons.palette_outlined, title: context.t('cert.no_design'), subtitle: context.t('cert.no_design_hint')))
            : ResponsiveWrap(minTileWidth: 340, children: [
                for (final t in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CertThumb(t),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                          Pill(t.lang == 'ar' ? 'العربية' : 'English'),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          TextButton.icon(onPressed: () => _edit(context, ref, t), icon: const Icon(Icons.edit_rounded, size: 18), label: Text(context.t('common.edit'))),
                          TextButton.icon(onPressed: () => _edit(context, ref, t.copy()..id = null..name = '${t.name} (2)'), icon: const Icon(Icons.copy_rounded, size: 18), label: Text(context.t('cert.duplicate'))),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger),
                            onPressed: () async {
                              if (!await confirmDialog(context, title: context.t('cert.delete_q', {'n': t.name}), message: context.t('cert.delete_hint'), danger: true)) return;
                              try {
                                await ref.read(apiProvider).delete('/certificates/templates/${t.id}');
                                ref.invalidate(certTemplatesProvider);
                              } on ApiException catch (e) {
                                if (context.mounted) toast(context, e.message, error: true);
                              }
                            },
                          ),
                        ]),
                      ]),
                    ),
                  ),
              ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ history + planned closings

class _HistoryPane extends ConsumerWidget {
  const _HistoryPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hist = ref.watch(certHistoryProvider);
    final clos = ref.watch(certClosuresProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(certHistoryProvider);
        ref.invalidate(certClosuresProvider);
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), physics: const AlwaysScrollableScrollPhysics(), children: [
        SectionHeader(context.t('cert.closings'), padding: const EdgeInsets.fromLTRB(4, 6, 4, 8)),
        clos.when(
          loading: () => const SkeletonList(count: 1),
          error: (e, _) => Text(errorText(context, e)),
          data: (list) => list.isEmpty
              ? Padding(padding: const EdgeInsets.all(8), child: Text(context.t('cert.no_closings'), style: TextStyle(color: context.colors.subtext)))
              : ResponsiveWrap(minTileWidth: 420, children: [
                  for (final c in list)
                    AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(jStr(c, 'employeeName'), style: const TextStyle(fontWeight: FontWeight.w800))),
                          Pill(jStr(c, 'status') == 'pending' ? context.t('cert.planned') : context.t('cert.closed'), color: jStr(c, 'status') == 'pending' ? context.colors.warning : context.colors.subtext),
                        ]),
                        Text(jStr(c, 'closeAt').replaceFirst('T', ' ').substring(0, 16), style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
                        if (jStr(c, 'status') == 'pending')
                          Row(children: [
                            TextButton.icon(
                              icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                              label: Text(context.t('cert.close_now')),
                              onPressed: () async {
                                if (!await confirmDialog(context, title: context.t('cert.close_now_q'), danger: true)) return;
                                try {
                                  await ref.read(apiProvider).post('/certificates/closures/${jInt(c, 'id')}/close-now');
                                  ref.invalidate(certClosuresProvider);
                                  ref.invalidate(employeesProvider);
                                  ref.invalidate(certHistoryProvider);
                                } on ApiException catch (e) {
                                  if (context.mounted) toast(context, e.message, error: true);
                                }
                              },
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: Text(context.t('common.cancel')),
                              onPressed: () async {
                                try {
                                  await ref.read(apiProvider).delete('/certificates/closures/${jInt(c, 'id')}');
                                  ref.invalidate(certClosuresProvider);
                                } on ApiException catch (e) {
                                  if (context.mounted) toast(context, e.message, error: true);
                                }
                              },
                            ),
                          ]),
                      ]),
                    ),
                ]),
        ),
        SectionHeader(context.t('cert.issued'), padding: const EdgeInsets.fromLTRB(4, 18, 4, 8)),
        hist.when(
          loading: () => const SkeletonList(count: 2),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(certHistoryProvider)),
          data: (list) => list.isEmpty
              ? Padding(padding: const EdgeInsets.all(8), child: Text(context.t('cert.none_yet'), style: TextStyle(color: context.colors.subtext)))
              : ResponsiveWrap(minTileWidth: 420, children: [
                  for (final c in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        onTap: () => _actions(context, ref, c),
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          Container(width: 42, height: 42, decoration: BoxDecoration(color: context.colors.brandSoft, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.workspace_premium_rounded, color: context.scheme.primary)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(jStr(c, 'employeeName'), style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${jStr(c, 'title')} · ${jStr(c, 'serial')}', style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
                              Text(jStrN(c, 'emailedTo') ?? context.t('cert.not_emailed'), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                            ]),
                          ),
                          const Icon(Icons.more_vert_rounded),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }

  void _actions(BuildContext context, WidgetRef ref, Map<String, dynamic> c) {
    showAppSheet<void>(
      context,
      title: jStr(c, 'serial'),
      child: Column(children: [
        ListTile(leading: const Icon(Icons.picture_as_pdf_rounded), title: Text(context.t('cert.open_pdf')), onTap: () { Navigator.pop(context); openCertFile(context, ref, jInt(c, 'id'), jStr(c, 'serial')); }),
        ListTile(leading: const Icon(Icons.ios_share_rounded), title: Text(context.t('common.share')), onTap: () { Navigator.pop(context); openCertFile(context, ref, jInt(c, 'id'), jStr(c, 'serial'), share: true); }),
        ListTile(
          leading: const Icon(Icons.mail_outline_rounded),
          title: Text(context.t('cert.resend')),
          onTap: () async {
            Navigator.pop(context);
            final ctl = TextEditingController(text: jStrN(c, 'emailedTo') ?? '');
            final to = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(ctx.t('cert.resend')),
                content: TextField(controller: ctl, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: ctx.t('auth.email.label'))),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('common.cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(ctx.t('cert.send')))],
              ),
            );
            if (to == null || to.isEmpty) return;
            try {
              final r = asMap(await ref.read(apiProvider).post('/certificates/${jInt(c, 'id')}/resend', {'emailTo': to}));
              if (context.mounted) toast(context, r['emailed'] == true ? '${context.t('cert.emailed_to')} ${jStr(r, 'to')}' : context.t('cert.mail_failed'), error: r['emailed'] != true);
              ref.invalidate(certHistoryProvider);
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          },
        ),
        if (jStr(c, 'employeeStatus') != 'inactive')
          ListTile(leading: const Icon(Icons.power_settings_new_rounded), title: Text(context.t('cert.plan_close')), onTap: () { Navigator.pop(context); showCloseSheet(context, ref, employeeId: jInt(c, 'employeeId'), certificateId: jInt(c, 'id'), leaveDate: jStrN(c, 'leaveDate')); }),
      ]),
    );
  }
}
