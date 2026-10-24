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

class Loan {
  final int id;
  final int employeeId;
  final String employeeName;
  final String title;
  final double amount;
  final double installment;
  final String startMonth;
  final String status; // active | done | cancelled
  final double paid;
  final double remaining;
  const Loan({required this.id, required this.employeeId, this.employeeName = '', required this.title, required this.amount, required this.installment, this.startMonth = '', this.status = 'active', this.paid = 0, this.remaining = 0});

  factory Loan.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Loan(
      id: jInt(m, 'id'),
      employeeId: jInt(m, 'employeeId'),
      employeeName: jStr(m, 'employeeName'),
      title: jStr(m, 'title'),
      amount: jDouble(m, 'amount'),
      installment: jDouble(m, 'installment'),
      startMonth: jStr(m, 'startMonth'),
      status: jStr(m, 'status', 'active'),
      paid: jDouble(m, 'paid'),
      remaining: jDouble(m, 'remaining'),
    );
  }
}

/// Loans / salary advances. Employee: their own; HR: everyone's (or one employee's when [employeeId] is given).
final loansProvider = FutureProvider.autoDispose.family<List<Loan>, int>((ref, employeeId) async {
  final d = await ref.read(apiProvider).get('/payroll/loans', query: {if (employeeId > 0) 'employeeId': employeeId});
  return d is List ? d.map(Loan.fromJson).toList() : <Loan>[];
});

class _LoanCard extends StatelessWidget {
  final Loan loan;
  final String currency;
  final bool showName;
  final VoidCallback? onTap;
  const _LoanCard({required this.loan, required this.currency, this.showName = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = loan.status == 'done';
    final cancelled = loan.status == 'cancelled';
    final color = cancelled ? context.colors.subtext : (done ? context.colors.success : context.scheme.primary);
    final progress = loan.amount <= 0 ? 0.0 : (loan.paid / loan.amount).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(loan.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Pill(context.t('loans.status.${loan.status}'), color: color),
          ]),
          if (showName && loan.employeeName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(loan.employeeName, style: TextStyle(color: context.colors.subtext))),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress, minHeight: 7, color: color, backgroundColor: context.colors.border)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(context.t('loans.repaid', {'a': money(context, loan.paid, currency), 'b': money(context, loan.amount, currency)}), style: TextStyle(color: context.colors.subtext, fontSize: 12.5))),
            if (!done && !cancelled) Text(context.t('loans.per_month', {'v': money(context, loan.installment, currency)}), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ]),
      ),
    );
  }
}

/// The employee's own loans, shown under their payslips (nothing at all when there are none).
class MyLoansSection extends ConsumerWidget {
  const MyLoansSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider(0)).valueOrNull ?? const <Loan>[];
    final shown = loans.where((l) => l.status != 'cancelled').toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final currency = ref.watch(sessionProvider).company?.currency ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(context.t('loans.mine')),
      for (final l in shown) _LoanCard(loan: l, currency: currency),
    ]);
  }
}

/// HR: every loan in the company, add a new one, stop one.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider(0));
    final currency = ref.watch(sessionProvider).company?.currency ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(context.t('loans.title'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _add(context, ref), icon: const Icon(Icons.add_rounded), label: Text(context.t('loans.add'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(loansProvider(0)),
        child: AsyncBody<List<Loan>>(
          value: loans,
          onRetry: () => ref.invalidate(loansProvider(0)),
          builder: (list) {
            if (list.isEmpty) return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.request_quote_outlined, title: context.t('loans.empty'), subtitle: context.t('loans.empty_hint')))]);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              for (final l in list)
                _LoanCard(
                  loan: l,
                  currency: currency,
                  showName: true,
                  onTap: l.status == 'active'
                      ? () async {
                          if (!await confirmDialog(context, title: context.t('loans.stop'), message: context.t('loans.stop_hint'), danger: true)) return;
                          try {
                            await ref.read(apiProvider).put('/payroll/loans/${l.id}', {'status': 'cancelled'});
                            ref.invalidate(loansProvider(0));
                          } on ApiException catch (e) {
                            if (context.mounted) toast(context, e.message, error: true);
                          }
                        }
                      : null,
                ),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final amount = TextEditingController();
    final inst = TextEditingController();
    final search = TextEditingController();
    Employee? pick;
    String q = '';
    bool busy = false;
    final now = DateTime.now();
    var start = DateTime(now.year, now.month);

    await showAppSheet(
      context,
      title: context.t('loans.add'),
      child: StatefulBuilder(builder: (ctx, setS) => Consumer(builder: (ctx, ref, _) {
        final people = pick == null ? ref.watch(directoryProvider(q)) : null;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (pick == null) ...[
            AppField(controller: search, label: ctx.t('kudos.who'), icon: Icons.search_rounded, onChanged: (v) => setS(() => q = v.trim())),
            SizedBox(
              height: 200,
              child: people!.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text(errorText(ctx, e)),
                data: (list) => ListView(children: [
                  for (final e in list) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Avatar(name: e.fullName, url: e.avatar, size: 32), title: Text(e.fullName), subtitle: Text(e.position), onTap: () => setS(() => pick = e)),
                ]),
              ),
            ),
          ] else ...[
            ListTile(contentPadding: EdgeInsets.zero, leading: Avatar(name: pick!.fullName, url: pick!.avatar, size: 38), title: Text(pick!.fullName, style: const TextStyle(fontWeight: FontWeight.w800)), trailing: TextButton(onPressed: () => setS(() => pick = null), child: Text(ctx.t('kudos.change')))),
            AppField(controller: title, label: ctx.t('loans.what'), icon: Icons.request_quote_outlined, capitalization: TextCapitalization.sentences),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: AppField(controller: amount, label: ctx.t('loans.amount'), keyboard: const TextInputType.numberWithOptions(decimal: true))),
              const SizedBox(width: 10),
              Expanded(child: AppField(controller: inst, label: ctx.t('loans.installment'), keyboard: const TextInputType.numberWithOptions(decimal: true))),
            ]),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3));
                if (d != null) setS(() => start = DateTime(d.year, d.month));
              },
              child: InputDecorator(decoration: InputDecoration(labelText: ctx.t('loans.start'), prefixIcon: const Icon(Icons.event_rounded)), child: Text(fmtMonthYear(ctx, start))),
            ),
            const SizedBox(height: 16),
            LoadingButton(
              label: ctx.t('common.add'),
              loading: busy,
              onPressed: () async {
                final a = double.tryParse(amount.text.trim().replaceAll(',', '.')) ?? 0;
                final i = double.tryParse(inst.text.trim().replaceAll(',', '.')) ?? 0;
                if (title.text.trim().isEmpty || a <= 0 || i <= 0) return;
                final nav = Navigator.of(ctx);
                setS(() => busy = true);
                try {
                  await ref.read(apiProvider).post('/payroll/loans', {'employeeId': pick!.id, 'title': title.text.trim(), 'amount': a, 'installment': i, 'startMonth': '${start.year}-${start.month.toString().padLeft(2, '0')}'});
                  ref.invalidate(loansProvider(0));
                  nav.pop();
                } on ApiException catch (e) {
                  setS(() => busy = false);
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
            ),
          ],
        ]);
      })),
    );
  }
}
