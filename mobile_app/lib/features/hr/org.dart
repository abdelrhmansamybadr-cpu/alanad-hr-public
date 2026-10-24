import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';
import 'department_detail.dart';
import 'package:go_router/go_router.dart';

const swatches = ['#00617A', '#6366F1', '#8B5CF6', '#EC4899', '#EF4444', '#F97316', '#F59E0B', '#10B981', '#14B8A6', '#0EA5E9', '#3B82F6', '#64748B'];

/// Row of preset colours.
class SwatchPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const SwatchPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 10, children: [
        for (final s in swatches)
          GestureDetector(
            onTap: () => onChanged(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: hexColor(s), shape: BoxShape.circle, border: Border.all(color: value.toUpperCase() == s ? context.scheme.onSurface : Colors.transparent, width: 3)),
              child: value.toUpperCase() == s ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
            ),
          ),
      ]);
}

/// Shared "save / delete" handling for the small management sheets.
Future<void> _run(BuildContext context, Future<void> Function() action, {required String done}) async {
  final nav = Navigator.of(context);
  try {
    await action();
    if (context.mounted) toast(context, done);
    nav.pop();
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
}

// ============================================================== departments

class DepartmentsScreen extends ConsumerWidget {
  const DepartmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(departmentsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('org.departments'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showDepartmentForm(context), icon: const Icon(Icons.add_rounded), label: Text(context.t('org.add_department'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(departmentsProvider);
          await ref.read(departmentsProvider.future).catchError((_) => <Department>[]);
        },
        child: AsyncBody<List<Department>>(
          value: list,
          onRetry: () => ref.invalidate(departmentsProvider),
          builder: (items) => items.isEmpty
              ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.account_tree_outlined, title: context.t('org.no_departments'), subtitle: context.t('org.no_departments_hint')))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final d = items[i];
                    return RowTile(
                      leading: IconBadge(Icons.account_tree_rounded, color: colorFor(d.name), size: 46),
                      title: d.name,
                      subtitle: [if ((d.description ?? '').isNotEmpty) d.description!, if (d.headName != null) '${context.t('org.head')}: ${d.headName}'].join(' · '),
                      trailing: Pill(context.t('org.people_count', {'n': d.employeeCount})),
                      onTap: () => context.push('/h/department/${d.id}'),
                    );
                  },
                ),
        ),
      ),
    );
  }

}

// ==================================================================== shifts

const _days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

class ShiftsScreen extends ConsumerWidget {
  const ShiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(shiftsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('org.shifts'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _form(context), icon: const Icon(Icons.add_rounded), label: Text(context.t('org.add_shift'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shiftsProvider);
          await ref.read(shiftsProvider.future).catchError((_) => <Shift>[]);
        },
        child: AsyncBody<List<Shift>>(
          value: list,
          onRetry: () => ref.invalidate(shiftsProvider),
          builder: (items) => items.isEmpty
              ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.schedule_rounded, title: context.t('org.no_shifts'), subtitle: context.t('org.no_shifts_hint')))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final s = items[i];
                    final c = hexColor(s.color);
                    final days = s.days.split(',').where((d) => d.isNotEmpty).toList();
                    return AppCard(
                      onTap: () => _form(context, existing: s),
                      padding: EdgeInsets.zero,
                      child: IntrinsicHeight(
                        child: Row(children: [
                          Container(width: 6, decoration: BoxDecoration(color: c, borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(20)))),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                                  Pill(context.t('org.people_count', {'n': s.assigned}), color: c),
                                ]),
                                const SizedBox(height: 6),
                                Text('${fmtTime(context, s.startTime)} – ${fmtTime(context, s.endTime)}', style: TextStyle(color: context.colors.subtext, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 10),
                                Wrap(spacing: 6, runSpacing: 6, children: [
                                  for (final d in _days)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: days.contains(d) ? c.withValues(alpha: 0.15) : context.colors.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                                      child: Text(context.t('weekday.$d').substring(0, context.isAr ? 3 : 3), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: days.contains(d) ? c : context.colors.subtext)),
                                    ),
                                ]),
                              ]),
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _form(BuildContext context, {Shift? existing}) => showAppSheet(context, title: existing == null ? context.t('org.add_shift') : context.t('common.edit'), child: _ShiftForm(existing: existing));
}

class _ShiftForm extends ConsumerStatefulWidget {
  final Shift? existing;
  const _ShiftForm({this.existing});

  @override
  ConsumerState<_ShiftForm> createState() => _ShiftFormState();
}

class _ShiftFormState extends ConsumerState<_ShiftForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late TimeOfDay _start = _t(widget.existing?.startTime) ?? const TimeOfDay(hour: 9, minute: 0);
  late TimeOfDay _end = _t(widget.existing?.endTime) ?? const TimeOfDay(hour: 17, minute: 0);
  late String _color = widget.existing?.color ?? '#00617A';
  late final Set<String> _sel = (widget.existing?.days ?? 'mon,tue,wed,thu,fri').split(',').where((d) => d.isNotEmpty).toSet();
  bool _busy = false;

  static TimeOfDay? _t(String? v) {
    if (v == null || v.length < 4) return null;
    final p = v.split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
  }

  static String _f(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_sel.isEmpty) return toast(context, context.t('org.pick_days'), error: true);
    setState(() => _busy = true);
    await _run(context, () async {
      final body = {'name': _name.text.trim(), 'startTime': _f(_start), 'endTime': _f(_end), 'color': _color, 'days': _days.where(_sel.contains).join(',')};
      final api = ref.read(apiProvider);
      widget.existing == null ? await api.post('/shifts', body) : await api.put('/shifts/${widget.existing!.id}', body);
      ref.invalidate(shiftsProvider);
    }, done: context.t('common.saved'));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(controller: _name, label: context.t('common.name'), icon: Icons.schedule_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _TimeField(label: context.t('org.starts'), value: _start, onPick: (t) => setState(() => _start = t))),
            const SizedBox(width: 12),
            Expanded(child: _TimeField(label: context.t('org.ends'), value: _end, onPick: (t) => setState(() => _end = t))),
          ]),
          const SizedBox(height: 16),
          Text(context.t('org.working_days'), style: TextStyle(color: context.colors.subtext, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in _days)
              FilterChip(
                label: Text(context.t('weekday.$d')),
                selected: _sel.contains(d),
                showCheckmark: false,
                onSelected: (v) => setState(() => v ? _sel.add(d) : _sel.remove(d)),
                selectedColor: context.scheme.primary,
                labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _sel.contains(d) ? Colors.white : null),
              ),
          ]),
          const SizedBox(height: 16),
          Text(context.t('org.color'), style: TextStyle(color: context.colors.subtext, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SwatchPicker(value: _color, onChanged: (c) => setState(() => _color = c)),
          const SizedBox(height: 22),
          LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
          if (widget.existing != null)
            TextButton(
              onPressed: () async {
                if (!await confirmDialog(context, title: context.t('common.delete'), message: context.t('org.delete_shift_hint'), danger: true, confirmLabel: context.t('common.delete'))) return;
                if (!context.mounted) return;
                await _run(context, () async {
                  await ref.read(apiProvider).delete('/shifts/${widget.existing!.id}');
                  ref.invalidate(shiftsProvider);
                }, done: context.t('common.deleted'));
              },
              child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
            ),
        ]),
      );
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onPick;
  const _TimeField({required this.label, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final t = await showTimePicker(context: context, initialTime: value);
          if (t != null) onPick(t);
        },
        child: InputDecorator(decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.access_time_rounded)), child: Text(value.format(context))),
      );
}

// ================================================================ leave types

class LeaveTypesScreen extends ConsumerWidget {
  const LeaveTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(allLeaveTypesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('org.leave_types'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _form(context), icon: const Icon(Icons.add_rounded), label: Text(context.t('org.add_leave_type'))),
      body: AsyncBody<List<LeaveType>>(
        value: list,
        onRetry: () => ref.invalidate(allLeaveTypesProvider),
        builder: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(context.t('org.leave_types_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)));
            final t = items[i - 1];
            final c = hexColor(t.color);
            return Opacity(
              opacity: t.active ? 1 : 0.5,
              child: RowTile(
                leading: IconBadge(Icons.beach_access_rounded, color: c, size: 46),
                title: t.name,
                subtitle: '${t.daysPerYear == 0 ? context.t('req.unlimited') : context.t('common.days', {'n': t.daysPerYear})} · ${t.paid ? context.t('org.paid') : context.t('org.unpaid')}',
                trailing: t.active ? null : StatusChip('inactive'),
                onTap: () => _form(context, existing: t),
              ),
            );
          },
        ),
      ),
    );
  }

  void _form(BuildContext context, {LeaveType? existing}) => showAppSheet(context, title: existing == null ? context.t('org.add_leave_type') : context.t('common.edit'), child: _LeaveTypeForm(existing: existing));
}

class _LeaveTypeForm extends ConsumerStatefulWidget {
  final LeaveType? existing;
  const _LeaveTypeForm({this.existing});

  @override
  ConsumerState<_LeaveTypeForm> createState() => _LeaveTypeFormState();
}

class _LeaveTypeFormState extends ConsumerState<_LeaveTypeForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _days = TextEditingController(text: '${widget.existing?.daysPerYear ?? 0}');
  late bool _paid = widget.existing?.paid ?? true;
  late bool _active = widget.existing?.active ?? true;
  late String _color = widget.existing?.color ?? '#00617A';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await _run(context, () async {
      final body = {'name': _name.text.trim(), 'daysPerYear': int.tryParse(_days.text.trim()) ?? 0, 'paid': _paid, 'color': _color, if (widget.existing != null) 'isActive': _active};
      final api = ref.read(apiProvider);
      widget.existing == null ? await api.post('/leave-types', body) : await api.put('/leave-types/${widget.existing!.id}', body);
      ref.invalidate(allLeaveTypesProvider);
      ref.invalidate(leaveTypesProvider);
      ref.invalidate(leaveBalanceProvider);
    }, done: context.t('common.saved'));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(controller: _name, label: context.t('common.name'), icon: Icons.beach_access_outlined, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
          const SizedBox(height: 14),
          AppField(controller: _days, label: context.t('org.days_per_year'), icon: Icons.numbers_rounded, keyboard: TextInputType.number, hint: context.t('org.zero_unlimited')),
          const SizedBox(height: 6),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('org.paid_leave')), value: _paid, onChanged: (v) => setState(() => _paid = v)),
          if (widget.existing != null) SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('org.active')), value: _active, onChanged: (v) => setState(() => _active = v)),
          const SizedBox(height: 8),
          SwatchPicker(value: _color, onChanged: (c) => setState(() => _color = c)),
          const SizedBox(height: 22),
          LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
          if (widget.existing != null)
            TextButton(
              onPressed: () async {
                if (!await confirmDialog(context, title: context.t('common.delete'), danger: true, confirmLabel: context.t('common.delete'))) return;
                if (!context.mounted) return;
                await _run(context, () async {
                  await ref.read(apiProvider).delete('/leave-types/${widget.existing!.id}');
                  ref.invalidate(allLeaveTypesProvider);
                  ref.invalidate(leaveTypesProvider);
                }, done: context.t('common.saved'));
              },
              child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
            ),
        ]),
      );
}

// ============================================================ document types

class DocTypesScreen extends ConsumerWidget {
  const DocTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(docTypesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('org.doc_types'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAppSheet(context, title: context.t('org.add_doc_type'), child: const _DocTypeForm()),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('org.add_doc_type')),
      ),
      body: AsyncBody<List<DocType>>(
        value: list,
        onRetry: () => ref.invalidate(docTypesProvider),
        builder: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(context.t('org.doc_types_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)));
            final t = items[i - 1];
            return RowTile(
              leading: IconBadge(Icons.description_rounded, color: context.colors.warning, size: 46),
              title: t.label,
              trailing: IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger),
                onPressed: () async {
                  if (!await confirmDialog(context, title: context.t('common.delete'), message: context.t('org.delete_doc_type_hint'), danger: true, confirmLabel: context.t('common.delete'))) return;
                  try {
                    await ref.read(apiProvider).delete('/documents/types/${t.id}');
                    ref.invalidate(docTypesProvider);
                  } on ApiException catch (e) {
                    if (context.mounted) toast(context, e.message, error: true);
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DocTypeForm extends ConsumerStatefulWidget {
  const _DocTypeForm();

  @override
  ConsumerState<_DocTypeForm> createState() => _DocTypeFormState();
}

class _DocTypeFormState extends ConsumerState<_DocTypeForm> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    await _run(context, () async {
      await ref.read(apiProvider).post('/documents/types', {'label': _name.text.trim()});
      ref.invalidate(docTypesProvider);
    }, done: context.t('common.saved'));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        AppField(controller: _name, label: context.t('org.doc_name'), icon: Icons.description_outlined, capitalization: TextCapitalization.sentences, autofocus: true, onSubmitted: (_) => _save()),
        const SizedBox(height: 20),
        LoadingButton(label: context.t('common.add'), loading: _busy, onPressed: _save),
      ]);
}
