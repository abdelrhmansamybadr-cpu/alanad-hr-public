import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import 'premium_common.dart';

final coachProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => asMap(await ref.read(apiProvider).get('/coach/weekly')));

Color _sevColor(BuildContext c, String s) => s == 'high' ? c.colors.danger : (s == 'medium' ? c.colors.warning : c.colors.info);

IconData _codeIcon(String code) => switch (code) {
      'lateness_rising' => Icons.alarm_rounded,
      'absences' => Icons.person_off_rounded,
      'overtime_heavy' => Icons.battery_alert_rounded,
      'approvals_waiting' => Icons.hourglass_top_rounded,
      'probation_ending' => Icons.fact_check_rounded,
      'no_recognition' => Icons.favorite_border_rounded,
      'no_break' => Icons.beach_access_rounded,
      'anniversary' => Icons.cake_rounded,
      _ => Icons.tips_and_updates_rounded,
    };

/// Manager coach: this week's advice, from real patterns in attendance, requests and recognition.
class CoachScreen extends ConsumerWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(coachProvider);
    final isHr = (ref.watch(sessionProvider).user?.role ?? 'employee') != 'employee';
    return Scaffold(
      appBar: AppBar(title: Text(context.t('coach.title'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(coachProvider);
          await ref.read(coachProvider.future).catchError((_) => <String, dynamic>{});
        },
        child: data.when(
          loading: () => const SkeletonList(),
          error: (e, _) => isFeatureOff(e) ? const FeatureOff() : ErrorState(e, onRetry: () => ref.invalidate(coachProvider)),
          data: (d) {
            final tips = asMapList(d['tips']);
            final sum = asMap(d['summary']);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), physics: const AlwaysScrollableScrollPhysics(), children: [
              AppCard(
                gradient: brandGradient(context),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t(jStr(d, 'scope') == 'company' ? 'coach.scope_company' : 'coach.scope_team', {'n': jInt(d, 'headcount')}), style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(tips.isEmpty ? context.t('coach.all_good') : context.t('coach.n_tips', {'n': tips.length}), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final s in ['high', 'medium', 'low'])
                      if (jInt(sum, s) > 0) Pill('${context.t('coach.sev_$s')} · ${jInt(sum, s)}', color: Colors.white),
                  ]),
                ]),
              ),
              if (tips.isEmpty) SizedBox(height: 260, child: EmptyState(icon: Icons.sentiment_satisfied_alt_rounded, title: context.t('coach.all_good'), subtitle: context.t('coach.all_good_hint'))),
              const SizedBox(height: 8),
              for (final t in tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TipCard(tip: t, canOpenPerson: isHr),
                ),
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.t('coach.footer'), style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.4))),
            ]);
          },
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final Map<String, dynamic> tip;
  final bool canOpenPerson;
  const _TipCard({required this.tip, required this.canOpenPerson});

  @override
  Widget build(BuildContext context) {
    final color = _sevColor(context, jStr(tip, 'severity'));
    final empId = jIntN(tip, 'employeeId');
    final name = jStrN(tip, 'employeeName');
    return AppCard(
      onTap: canOpenPerson && empId != null ? () => context.push('/h/employee/$empId') : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconBadge(_codeIcon(jStr(tip, 'code')), color: color, size: 42),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (name != null) Text(name, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
            Text(pick(context, tip, 'title'), style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.arrow_circle_right_rounded, size: 16, color: context.colors.subtext),
              const SizedBox(width: 6),
              Expanded(child: Text(pick(context, tip, 'action'), style: TextStyle(color: context.colors.subtext, height: 1.4, fontSize: 13.5))),
            ]),
          ]),
        ),
      ]),
    );
  }
}
