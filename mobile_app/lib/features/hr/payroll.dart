import 'package:go_router/go_router.dart';
import '../common/payslips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

class PayrollScreen extends ConsumerStatefulWidget {
  const PayrollScreen({super.key});

  @override
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final m = asMap(await ref.read(apiProvider).post('/payroll/generate', {'month': _ym(_month), 'recalculate': true}));
      ref.invalidate(payslipsProvider);
      ref.invalidate(hrStatsProvider);
      final n = jInt(m, 'created') + jInt(m, 'updated');
      if (mounted) toast(context, n == 0 ? context.t('payroll.none_created') : context.t('payroll.created', {'n': n}));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payAll(int pending) async {
    if (!await confirmDialog(context, title: context.t('payroll.pay_all'), message: context.t('payroll.pay_all_confirm', {'n': pending}), confirmLabel: context.t('payroll.pay_all'))) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/payroll/pay-all', {'month': _ym(_month)});
      ref.invalidate(payslipsProvider);
      ref.invalidate(hrStatsProvider);
      if (mounted) toast(context, context.t('payroll.paid_ok'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = _ym(_month);
    final slips = ref.watch(payslipsProvider(key));
    final currency = ref.watch(sessionProvider).company?.currency ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(context.t('payroll.title')), actions: [IconButton(tooltip: context.t('loans.title'), icon: const Icon(Icons.request_quote_outlined), onPressed: () => context.push('/h/loans'))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showAppSheet(context, title: context.t('payroll.add'), child: _SlipForm(month: key)), icon: const Icon(Icons.add_rounded), label: Text(context.t('payroll.add'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(payslipsProvider(key));
          await ref.read(payslipsProvider(key).future).catchError((_) => <Payslip>[]);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), physics: const AlwaysScrollableScrollPhysics(), children: [
          Row(children: [
            IconButton.filledTonal(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(child: Center(child: Text(fmtMonthYear(context, _month), style: context.text.titleMedium))),
            IconButton.filledTonal(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          const SizedBox(height: 12),
          AsyncBody<List<Payslip>>(
            value: slips,
            onRetry: () => ref.invalidate(payslipsProvider(key)),
            builder: (all) {
              final items = all.where((p) => p.status != 'cancelled').toList();
              final total = items.fold<double>(0, (a, p) => a + p.net);
              final paid = items.where((p) => p.status == 'paid').length;
              final pending = items.where((p) => p.status == 'pending').length;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(gradient: brandGradient(context), borderRadius: BorderRadius.circular(24)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('payroll.total'), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(money(context, total, currency), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Pill(context.t('payroll.n_paid', {'n': paid}), color: Colors.white, icon: Icons.check_circle_rounded),
                      const SizedBox(width: 8),
                      Pill(context.t('payroll.n_pending', {'n': pending}), color: Colors.white, icon: Icons.hourglass_bottom_rounded),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: LoadingButton(label: context.t('payroll.generate'), icon: Icons.auto_awesome_rounded, outlined: true, loading: _busy, onPressed: _generate)),
                  const SizedBox(width: 12),
                  Expanded(child: LoadingButton(label: context.t('payroll.pay_all'), icon: Icons.payments_rounded, loading: _busy, onPressed: pending == 0 ? null : () => _payAll(pending))),
                ]),
                const SizedBox(height: 6),
                Text(context.t('payroll.generate_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                SectionHeader(context.t('payroll.payslips')),
                if (items.isEmpty)
                  Padding(padding: const EdgeInsets.only(top: 20), child: EmptyState(icon: Icons.receipt_long_rounded, title: context.t('payroll.empty'), subtitle: context.t('payroll.empty_hint')))
                else
                  for (final p in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RowTile(
                        leading: Avatar(name: p.employeeName, size: 46),
                        title: p.employeeName,
                        subtitle: money(context, p.net, currency),
                        trailing: StatusChip(p.status),
                        onTap: () => showAppSheet(context, title: p.employeeName, child: _SlipActions(slip: p, currency: currency)),
                      ),
                    ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

class _SlipActions extends ConsumerStatefulWidget {
  final Payslip slip;
  final String currency;
  const _SlipActions({required this.slip, required this.currency});

  @override
  ConsumerState<_SlipActions> createState() => _SlipActionsState();
}

class _SlipActionsState extends ConsumerState<_SlipActions> {
  late final _bonus = TextEditingController(text: widget.slip.bonus == 0 ? '' : widget.slip.bonus.toStringAsFixed(0));
  late final _ded = TextEditingController(text: widget.slip.deductions == 0 ? '' : widget.slip.deductions.toStringAsFixed(0));
  bool _busy = false;

  @override
  void dispose() {
    _bonus.dispose();
    _ded.dispose();
    super.dispose();
  }

  Future<void> _put(Map<String, dynamic> body, String done) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/payroll/${widget.slip.id}', body);
      ref.invalidate(payslipsProvider);
      ref.invalidate(hrStatsProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, done);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slip;
    final editable = s.status == 'pending';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: Text(fmtMonthYear(context, DateTime(int.tryParse(s.month.split('-').first) ?? 2000, int.tryParse(s.month.split('-').last) ?? 1)), style: TextStyle(color: context.colors.subtext))), StatusChip(s.status)]),
      const SizedBox(height: 10),
      InfoRow(icon: Icons.payments_outlined, label: context.t('pay.base'), value: money(context, s.base, widget.currency)),
      if (editable) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: AppField(controller: _bonus, label: context.t('pay.bonus'), keyboard: const TextInputType.numberWithOptions(decimal: true))),
          const SizedBox(width: 12),
          Expanded(child: AppField(controller: _ded, label: context.t('pay.deductions'), keyboard: const TextInputType.numberWithOptions(decimal: true))),
        ]),
        const SizedBox(height: 16),
        LoadingButton(label: context.t('common.save'), outlined: true, loading: _busy, onPressed: () => _put({'bonus': double.tryParse(_bonus.text.trim()) ?? 0, 'deductions': double.tryParse(_ded.text.trim()) ?? 0}, context.t('common.saved'))),
        const SizedBox(height: 10),
        LoadingButton(label: context.t('payroll.mark_paid'), icon: Icons.check_circle_rounded, loading: _busy, onPressed: () => _put({'status': 'paid'}, context.t('payroll.paid_ok'))),
      ] else ...[
        InfoRow(icon: Icons.add_circle_outline_rounded, label: context.t('pay.bonus'), value: money(context, s.bonus, widget.currency)),
        InfoRow(icon: Icons.remove_circle_outline_rounded, label: context.t('pay.deductions'), value: money(context, s.deductions, widget.currency)),
        InfoRow(icon: Icons.account_balance_wallet_outlined, label: context.t('pay.net'), value: money(context, s.net, widget.currency)),
      ],
      const SizedBox(height: 10),
      PrintPayslipButton(payslipId: s.id),
      const SizedBox(height: 6),
      TextButton(
        onPressed: () async {
          final nav = Navigator.of(context);
          if (!await confirmDialog(context, title: context.t('common.delete'), danger: true, confirmLabel: context.t('common.delete'))) return;
          try {
            await ref.read(apiProvider).delete('/payroll/${s.id}');
            ref.invalidate(payslipsProvider);
            nav.pop();
          } on ApiException catch (e) {
            if (context.mounted) toast(context, e.message, error: true);
          }
        },
        child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
      ),
    ]);
  }
}

class _SlipForm extends ConsumerStatefulWidget {
  final String month;
  const _SlipForm({required this.month});

  @override
  ConsumerState<_SlipForm> createState() => _SlipFormState();
}

class _SlipFormState extends ConsumerState<_SlipForm> {
  int? _employee;
  final _base = TextEditingController();
  final _bonus = TextEditingController();
  final _ded = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _base.dispose();
    _bonus.dispose();
    _ded.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_employee == null) return toast(context, context.t('payroll.pick_employee'), error: true);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/payroll', {'employeeId': _employee, 'month': widget.month, if (_base.text.trim().isNotEmpty) 'baseSalary': double.tryParse(_base.text.trim()), 'bonus': double.tryParse(_bonus.text.trim()) ?? 0, 'deductions': double.tryParse(_ded.text.trim()) ?? 0});
      ref.invalidate(payslipsProvider);
      ref.invalidate(hrStatsProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, context.t('common.saved'));
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = (ref.watch(employeesProvider('')).valueOrNull ?? const <Employee>[]).where((e) => e.status != 'inactive').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<int>(
        initialValue: _employee,
        decoration: InputDecoration(labelText: context.t('payroll.employee'), prefixIcon: const Icon(Icons.person_outline_rounded)),
        items: [for (final e in people) DropdownMenuItem(value: e.id, child: Text(e.fullName))],
        onChanged: (v) => setState(() {
          _employee = v;
          final emp = people.firstWhere((e) => e.id == v);
          if (emp.salary != null) _base.text = emp.salary!.toStringAsFixed(0);
        }),
      ),
      const SizedBox(height: 14),
      AppField(controller: _base, label: context.t('pay.base'), icon: Icons.payments_outlined, keyboard: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: AppField(controller: _bonus, label: context.t('pay.bonus'), keyboard: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 12),
        Expanded(child: AppField(controller: _ded, label: context.t('pay.deductions'), keyboard: const TextInputType.numberWithOptions(decimal: true))),
      ]),
      const SizedBox(height: 20),
      LoadingButton(label: context.t('common.create'), loading: _busy, onPressed: _save),
    ]);
  }
}
