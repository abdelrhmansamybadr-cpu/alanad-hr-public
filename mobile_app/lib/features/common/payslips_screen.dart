import '../hr/loans.dart';
import '../../core/api/api.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

DateTime _monthOf(String ym) {
  final p = ym.split('-');
  return DateTime(int.tryParse(p[0]) ?? DateTime.now().year, p.length > 1 ? int.tryParse(p[1]) ?? 1 : 1);
}

/// The signed-in employee's payslips.
class PayslipsScreen extends ConsumerWidget {
  const PayslipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slips = ref.watch(payslipsProvider(''));
    final currency = ref.watch(sessionProvider).company?.currency ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(context.t('home.qa.payslips'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(payslipsProvider(''));
          await ref.read(payslipsProvider('').future).catchError((_) => <Payslip>[]);
        },
        child: AsyncBody<List<Payslip>>(
          value: slips,
          onRetry: () => ref.invalidate(payslipsProvider('')),
          builder: (items) {
            final visible = items.where((p) => p.status != 'cancelled').toList();
            if (visible.isEmpty) {
              return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.receipt_long_rounded, title: context.t('pay.empty'), subtitle: context.t('pay.empty_hint')))]);
            }
            final latest = visible.first;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), physics: const AlwaysScrollableScrollPhysics(), children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: brandGradient(context), borderRadius: BorderRadius.circular(24)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtMonthYear(context, _monthOf(latest.month)), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(money(context, latest.net, currency), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Pill(context.t('status.${latest.status}'), color: Colors.white),
                ]),
              ),
              SectionHeader(context.t('pay.history')),
              for (final p in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RowTile(
                    leading: Container(
                      width: 48,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: context.colors.brandSoft, borderRadius: BorderRadius.circular(14)),
                      child: Column(children: [
                        Text(_monthOf(p.month).month.toString().padLeft(2, '0'), style: TextStyle(color: context.scheme.primary, fontWeight: FontWeight.w800, fontSize: 18)),
                        Text('${_monthOf(p.month).year}', style: TextStyle(color: context.scheme.primary, fontSize: 10)),
                      ]),
                    ),
                    title: fmtMonthYear(context, _monthOf(p.month)),
                    subtitle: money(context, p.net, currency),
                    trailing: StatusChip(p.status),
                    onTap: () => showPayslip(context, p, currency),
                  ),
                ),
              const MyLoansSection(),
            ]);
          },
        ),
      ),
    );
  }
}

Future<void> showPayslip(BuildContext context, Payslip p, String currency) {
  Widget line(String label, num v, {Color? color, bool bold = false, String sign = ''}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: bold ? null : context.colors.subtext, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text('$sign${money(context, v, currency)}', style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 18 : 15, color: color)),
        ]),
      );
  return showAppSheet(
    context,
    title: '${context.t('pay.payslip')} · ${fmtMonthYear(context, _monthOf(p.month))}',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (p.employeeName.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Avatar(name: p.employeeName, size: 40), const SizedBox(width: 12), Expanded(child: Text(p.employeeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))), StatusChip(p.status)])),
      line(context.t('pay.base'), p.base),
      if (p.lines.isEmpty) ...[
        line(context.t('pay.bonus'), p.bonus, color: context.colors.success, sign: p.bonus > 0 ? '+' : ''),
        line(context.t('pay.deductions'), p.deductions, color: context.colors.danger, sign: p.deductions > 0 ? '−' : ''),
      ] else ...[
        for (final l in p.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(child: Text(paylineLabel(context, l), style: TextStyle(color: context.colors.subtext))),
              Text('${l.amount >= 0 ? '+' : '−'}${money(context, l.amount.abs(), currency)}', style: TextStyle(fontWeight: FontWeight.w600, color: l.amount >= 0 ? context.colors.success : context.colors.danger)),
            ]),
          ),
        if (p.stats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(context.t('payline.stats', {'w': p.stats['working_days'] ?? p.stats['workingDays'] ?? 0, 'a': p.stats['absent_days'] ?? p.stats['absentDays'] ?? 0, 'h': p.stats['half_days'] ?? p.stats['halfDays'] ?? 0}), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
          ),
      ],
      Divider(color: context.colors.border),
      line(context.t('pay.net'), p.net, bold: true, color: context.scheme.primary),
      if (p.paidAt != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.t('pay.paid_on', {'date': fmtDate(context, p.paidAt!)}), style: TextStyle(color: context.colors.subtext, fontSize: 13))),
      const SizedBox(height: 12),
      PrintPayslipButton(payslipId: p.id),
    ]),
  );
}


/// "Insurance", "Income tax", "Loan: laptop"... and for attendance lines the count in brackets.
String paylineLabel(BuildContext context, PayLine l) {
  if (l.key == 'insurance' || l.key == 'tax') return context.t('payline.${l.key}');
  if (l.key.startsWith('loan_')) return '${context.t('payline.loan')}: ${l.label.replaceFirst(RegExp(r'^Loan:\s*'), '')}';
  final qty = l.qty == l.qty.roundToDouble() ? l.qty.toInt() : l.qty.toStringAsFixed(1);
  return '${context.t('payline.${l.key}')}${l.key == 'perfect' ? '' : ' ($qty)'}';
}

/// Opens the printable payslip in the browser (print -> save as PDF). The link is signed and lasts 10 minutes.
class PrintPayslipButton extends ConsumerStatefulWidget {
  final int payslipId;
  const PrintPayslipButton({super.key, required this.payslipId});

  @override
  ConsumerState<PrintPayslipButton> createState() => _PrintPayslipButtonState();
}

class _PrintPayslipButtonState extends ConsumerState<PrintPayslipButton> {
  bool _busy = false;

  Future<void> _open() async {
    final lang = context.isAr ? 'ar' : 'en';
    final failed = context.t('pay.print_failed');
    setState(() => _busy = true);
    try {
      final d = await ref.read(apiProvider).get('/payroll/${widget.payslipId}/link', query: {'lang': lang});
      final url = (d is Map ? d['url'] : null)?.toString();
      if (url == null || !await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) throw ApiException(failed);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, failed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: _busy ? null : _open,
        icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_rounded),
        label: Text(context.t('pay.print')),
      );
}
