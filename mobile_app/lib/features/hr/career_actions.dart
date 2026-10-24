import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../common/career_org.dart';
import '../data/providers.dart';
import '../rewards/point_orb.dart';
import '../rewards/rewards_screen.dart';

// ============================================================== promote / raise / transfer

Future<void> showPromoteSheet(BuildContext context, Employee e, {String type = 'promotion'}) {
  return showAppSheet(context, title: context.t('promote.title', {'name': e.firstName}), child: _PromoteForm(employee: e, type: type));
}

class _PromoteForm extends ConsumerStatefulWidget {
  final Employee employee;
  final String type;
  const _PromoteForm({required this.employee, required this.type});

  @override
  ConsumerState<_PromoteForm> createState() => _PromoteFormState();
}

class _PromoteFormState extends ConsumerState<_PromoteForm> {
  late String _type = widget.type;
  late final _position = TextEditingController(text: widget.employee.position);
  late final _salary = TextEditingController(text: widget.employee.salary == null ? '' : widget.employee.salary!.toStringAsFixed(widget.employee.salary! % 1 == 0 ? 0 : 2));
  final _note = TextEditingController();
  int? _dept;
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _dept = widget.employee.departmentId;
  }

  @override
  void dispose() {
    _position.dispose();
    _salary.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final e = widget.employee;
    final newPos = _position.text.trim();
    final newSalary = double.tryParse(_salary.text.trim());
    final body = <String, dynamic>{
      'type': _type,
      if (newPos.isNotEmpty && newPos != e.position) 'position': newPos,
      if (newSalary != null && newSalary != e.salary) 'salary': newSalary,
      if (_dept != null && _dept != e.departmentId) 'departmentId': _dept,
      'effectiveDate': ymd(_date),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    };
    if (!body.containsKey('position') && !body.containsKey('salary') && !body.containsKey('departmentId')) {
      return toast(context, context.t('promote.nothing'), error: true);
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).post('/employees/${e.id}/promote', body);
      ref.invalidate(employeeProvider(e.id));
      ref.invalidate(promotionsProvider(e.id));
      ref.invalidate(employeesProvider);
      if (mounted) toast(context, context.t('promote.done'));
      nav.pop();
    } on ApiException catch (err) {
      if (mounted) toast(context, err.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final depts = ref.watch(departmentsProvider).valueOrNull ?? const <Department>[];
    final currency = ref.watch(sessionProvider).company?.currency ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in ['promotion', 'raise', 'transfer', 'demotion'])
          ChoiceChip(
            selected: _type == t,
            showCheckmark: false,
            avatar: Icon(promotionIcon(t), size: 18, color: _type == t ? Colors.white : null),
            label: Text(context.t('career.type.$t')),
            selectedColor: promotionColor(context, t),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _type == t ? Colors.white : null),
            onSelected: (_) => setState(() => _type = t),
          ),
      ]),
      const SizedBox(height: 16),
      AppField(controller: _position, label: context.t('promote.new_position'), icon: Icons.work_outline_rounded, capitalization: TextCapitalization.words),
      const SizedBox(height: 14),
      AppField(controller: _salary, label: '${context.t('promote.new_salary')} ($currency)', icon: Icons.payments_outlined, keyboard: const TextInputType.numberWithOptions(decimal: true), formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]),
      const SizedBox(height: 14),
      DropdownButtonFormField<int?>(
        initialValue: depts.any((d) => d.id == _dept) ? _dept : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.t('people.department'), prefixIcon: const Icon(Icons.account_tree_outlined)),
        items: [for (final d in depts) DropdownMenuItem<int?>(value: d.id, child: Text(d.name))],
        onChanged: (v) => setState(() => _dept = v),
      ),
      const SizedBox(height: 14),
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 730)));
          if (d != null) setState(() => _date = d);
        },
        child: InputDecorator(decoration: InputDecoration(labelText: context.t('promote.effective'), prefixIcon: const Icon(Icons.event_rounded)), child: Text(fmtDate(context, _date))),
      ),
      const SizedBox(height: 14),
      AppField(controller: _note, label: context.t('promote.note'), icon: Icons.notes_rounded, maxLines: 2),
      const SizedBox(height: 8),
      Text(context.t('promote.hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.4)),
      const SizedBox(height: 18),
      LoadingButton(label: context.t('promote.confirm'), loading: _busy, onPressed: _save),
    ]);
  }
}

// ==================================================================== leave the company

Future<void> showTerminateSheet(BuildContext context, Employee e) => showAppSheet(context, title: context.t('terminate.title', {'name': e.firstName}), child: _TerminateForm(employee: e));

class _TerminateForm extends ConsumerStatefulWidget {
  final Employee employee;
  const _TerminateForm({required this.employee});

  @override
  ConsumerState<_TerminateForm> createState() => _TerminateFormState();
}

class _TerminateFormState extends ConsumerState<_TerminateForm> {
  final _reason = TextEditingController();
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final nav = Navigator.of(context);
    if (!await confirmDialog(context, title: context.t('terminate.confirm_title'), message: context.t('terminate.confirm_msg'), danger: true, confirmLabel: context.t('terminate.confirm'))) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/employees/${widget.employee.id}/terminate', {'date': ymd(_date), 'reason': _reason.text.trim()});
      ref.invalidate(employeeProvider(widget.employee.id));
      ref.invalidate(employeesProvider);
      ref.invalidate(departmentsProvider);
      ref.invalidate(hrStatsProvider);
      if (mounted) toast(context, context.t('people.deactivated'));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('terminate.hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)),
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _date = d);
          },
          child: InputDecorator(decoration: InputDecoration(labelText: context.t('terminate.last_day'), prefixIcon: const Icon(Icons.event_busy_rounded)), child: Text(fmtDate(context, _date))),
        ),
        const SizedBox(height: 14),
        AppField(controller: _reason, label: context.t('terminate.reason'), icon: Icons.notes_rounded, maxLines: 3),
        const SizedBox(height: 18),
        LoadingButton(label: context.t('terminate.confirm'), loading: _busy, color: context.colors.danger, onPressed: _go),
      ]);
}

// ======================================================= one employee's points (HR)

class EmployeePointsScreen extends ConsumerWidget {
  final int employeeId;
  final String name;
  const EmployeePointsScreen({super.key, required this.employeeId, this.name = ''});

  Future<void> _give(BuildContext context, WidgetRef ref, PointKind kind) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('rewards.give_${kind.name}')),
        content: TextField(controller: note, maxLength: 120, decoration: InputDecoration(hintText: ctx.t('rewards.give_note'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.t('common.save'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).post('/points/adjust', {'employeeId': employeeId, 'color': kind.name, 'note': note.text.trim()});
      ref.invalidate(employeePointsProvider(employeeId));
      if (context.mounted) toast(context, context.t('common.saved'));
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, PointEntry e) async {
    final excuse = !e.voided;
    if (!await confirmDialog(context, title: context.t(excuse ? 'rewards.excuse' : 'rewards.restore'), message: context.t(excuse ? 'rewards.excuse_hint' : 'rewards.restore_hint'), confirmLabel: context.t('common.confirm'))) return;
    try {
      await ref.read(apiProvider).put('/points/${e.id}', {'voided': excuse});
      ref.invalidate(employeePointsProvider(employeeId));
    } on ApiException catch (err) {
      if (context.mounted) toast(context, err.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pts = ref.watch(employeePointsProvider(employeeId));
    return Scaffold(
      appBar: AppBar(title: Text(name.isEmpty ? context.t('rewards.title') : name)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(employeePointsProvider(employeeId));
          await ref.read(employeePointsProvider(employeeId).future).catchError((_) => const PointsSummary());
        },
        child: AsyncBody<PointsSummary>(
          value: pts,
          onRetry: () => ref.invalidate(employeePointsProvider(employeeId)),
          loading: const Padding(padding: EdgeInsets.all(16), child: Skeleton(height: 300, radius: 28)),
          builder: (s) => PointsBody(
            summary: s,
            onEntryTap: (e) => _toggle(context, ref, e),
            footer: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('rewards.manage'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(context.t('rewards.manage_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.4)),
                const SizedBox(height: 14),
                Row(children: [
                  for (final k in PointKind.values) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _give(context, ref, k),
                        style: OutlinedButton.styleFrom(side: BorderSide(color: k.base.withValues(alpha: 0.6)), padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: k.base)),
                          const SizedBox(width: 6),
                          Text('+1', style: TextStyle(color: k.base == PointKind.black.base ? context.scheme.onSurface : k.base, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                    if (k != PointKind.black) const SizedBox(width: 8),
                  ],
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
