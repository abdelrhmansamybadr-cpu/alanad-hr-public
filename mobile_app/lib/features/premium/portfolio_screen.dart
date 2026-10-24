import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/ui/widgets.dart';
import 'premium_common.dart';

final portfolioProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => asMap(await ref.read(apiProvider).get('/portfolio')));

Color _levelColor(BuildContext c, String level) => level == 'high' ? c.colors.danger : (level == 'medium' ? c.colors.warning : c.colors.success);

/// Owner dashboard: every company side by side, most in need of attention first. Each score lists why it is what it is.
class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(portfolioProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('pf.title'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(portfolioProvider);
          await ref.read(portfolioProvider.future).catchError((_) => <String, dynamic>{});
        },
        child: data.when(
          loading: () => const SkeletonList(),
          error: (e, _) => isFeatureOff(e) ? const FeatureOff() : ErrorState(e, onRetry: () => ref.invalidate(portfolioProvider)),
          data: (d) {
            final t = asMap(d['totals']);
            final companies = asMapList(d['companies']);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), physics: const AlwaysScrollableScrollPhysics(), children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.5,
                children: [
                  StatTile(icon: Icons.business_rounded, color: context.scheme.primary, value: '${jInt(t, 'companies')}', label: context.t('pf.companies')),
                  StatTile(icon: Icons.groups_rounded, color: context.colors.info, value: '${jInt(t, 'headcount')}', label: context.t('pf.people')),
                  StatTile(icon: Icons.hourglass_top_rounded, color: context.colors.warning, value: '${jInt(t, 'waitingApprovals')}', label: context.t('pf.waiting')),
                  StatTile(icon: Icons.logout_rounded, color: context.colors.danger, value: '${jInt(t, 'leavers90d')}', label: context.t('pf.leavers')),
                ],
              ),
              const SizedBox(height: 6),
              for (final c in companies) Padding(padding: const EdgeInsets.only(top: 12), child: _CompanyPortfolio(c)),
              const SizedBox(height: 14),
              Text(context.t('pf.footer'), style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.4)),
            ]);
          },
        ),
      ),
    );
  }
}

class _CompanyPortfolio extends StatelessWidget {
  final Map<String, dynamic> c;
  const _CompanyPortfolio(this.c);

  @override
  Widget build(BuildContext context) {
    final att = asMap(c['attention']);
    final level = jStr(att, 'level', 'low');
    final color = _levelColor(context, level);
    final why = asMapList(att['why']);
    final over = asMapList(c['overloadedManagers']);
    final cur = jStr(c, 'currency');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProgressRing(value: jInt(att, 'score') / 100, color: color, size: 62, stroke: 7, child: Text('${jInt(att, 'score')}', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 17))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(jStr(c, 'name'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Pill(context.t('pf.level_$level'), color: color),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Kpi(Icons.groups_rounded, '${jInt(c, 'headcount')}', context.t('pf.people')),
          _Kpi(Icons.payments_rounded, money(jDouble(c, 'payrollNetLastMonth'), cur), jStrN(c, 'payrollPeriod') ?? context.t('pf.no_payroll')),
          _Kpi(Icons.alarm_rounded, '${jDouble(c, 'lateRate').toStringAsFixed(0)}%', context.t('pf.late')),
          _Kpi(Icons.person_off_rounded, '${jDouble(c, 'absentRate').toStringAsFixed(0)}%', context.t('pf.absent')),
          _Kpi(Icons.logout_rounded, '${jInt(c, 'leavers90d')}', context.t('pf.leavers_90')),
          _Kpi(Icons.hourglass_top_rounded, '${jInt(c, 'waitingApprovals')}', context.t('pf.waiting')),
        ]),
        if (why.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(context.t('pf.why'), style: TextStyle(color: context.colors.subtext, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final w in why)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 34, child: Text('+${jInt(w, 'points')}', style: TextStyle(color: color, fontWeight: FontWeight.w800))),
                Expanded(child: Text(context.isAr ? jStr(w, 'ar') : jStr(w, 'en'), style: const TextStyle(height: 1.35))),
              ]),
            ),
        ],
        if (over.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(context.t('pf.overloaded'), style: TextStyle(color: context.colors.subtext, fontSize: 12, fontWeight: FontWeight.w800)),
          for (final m in over) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${jStr(m, 'name')} · ${context.t('pf.reports_n', {'n': jInt(m, 'reports')})}')),
        ],
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Kpi(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) => Container(
        width: 104,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: context.colors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 15, color: context.colors.subtext), const SizedBox(width: 5), Expanded(child: Text(label, style: TextStyle(color: context.colors.subtext, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}
