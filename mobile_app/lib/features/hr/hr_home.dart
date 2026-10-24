import 'wellbeing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';
import '../group/group_screens.dart';

class HrHome extends ConsumerWidget {
  const HrHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user!;
    final company = session.company!;
    final stats = ref.watch(hrStatsProvider);
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(hrStatsProvider);
            await ref.read(hrStatsProvider.future).catchError((_) => const HrStats());
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), physics: const AlwaysScrollableScrollPhysics(), children: [
            Row(children: [
              GestureDetector(onTap: () => context.go('/h/more'), child: Avatar(name: user.name, url: user.avatar, size: 48, ring: true)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(greeting(context), style: TextStyle(color: context.colors.subtext, fontSize: 13)),
                  Text(user.firstName, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ]),
              ),
              // Company chip; inside a company group it opens the company switcher
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: (session.group?.canSwitch ?? false) ? () => showCompanySwitcher(context, ref) : null,
                child: Container(
                  constraints: BoxConstraints(maxWidth: (session.group?.canSwitch ?? false) ? 150 : 110),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: context.colors.brandSoft, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(company.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.scheme.primary, fontWeight: FontWeight.w700, fontSize: 12))),
                    if (session.group?.canSwitch ?? false) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.unfold_more_rounded, size: 16, color: context.scheme.primary),
                    ],
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              NotificationBell(count: unread, onTap: () => context.push('/inbox')),
            ]),
            const SizedBox(height: 18),
            AsyncBody<HrStats>(
              value: stats,
              onRetry: () => ref.invalidate(hrStatsProvider),
              loading: const Column(children: [Skeleton(height: 200, radius: 24), SizedBox(height: 14), Skeleton(height: 100, radius: 20), SizedBox(height: 14), Skeleton(height: 160, radius: 20)]),
              builder: (s) => _Dashboard(s: s),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  final HrStats s;
  const _Dashboard({required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(sessionProvider).company?.currency ?? '';
    final rate = s.total == 0 ? 0.0 : s.present / s.total;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ---- today's attendance hero
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(gradient: brandGradient(context), borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: context.scheme.primary.withValues(alpha: 0.3), blurRadius: 22, offset: const Offset(0, 10))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('hrhome.today'), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(width: 72, height: 72, child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: rate), duration: const Duration(milliseconds: 800), curve: Curves.easeOutCubic, builder: (_, v, __) => CircularProgressIndicator(value: v, strokeWidth: 7, strokeCap: StrokeCap.round, color: Colors.white, backgroundColor: Colors.white24))),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${(rate * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(context.t('hrhome.in'), style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                ]),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(runSpacing: 8, spacing: 8, children: [
                _HeroStat('${s.present}', context.t('status.present')),
                _HeroStat('${s.late}', context.t('status.late')),
                _HeroStat('${s.halfDay}', context.t('status.half_day')),
                _HeroStat('${s.absent}', context.t('status.absent')),
              ]),
            ),
          ]),
          if (s.notIn > 0 || s.onLeave > 0 || s.outsideNow > 0) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (s.notIn > 0) Pill(context.t('board.not_in_n', {'n': s.notIn}), color: Colors.white, icon: Icons.hourglass_empty_rounded),
              if (s.onLeave > 0) Pill('${s.onLeave} ${context.t('status.on_leave')}', color: Colors.white, icon: Icons.beach_access_rounded),
              if (s.outsideNow > 0) Pill(context.t('board.outside_n', {'n': s.outsideNow}), color: Colors.white, icon: Icons.directions_walk_rounded),
            ]),
          ],
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => context.go('/h/attendance'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: 0.5)), minimumSize: const Size.fromHeight(38)),
            child: Text(context.t('hrhome.open_board')),
          ),
        ]),
      ),
      const SizedBox(height: 16),

      // ---- KPI grid
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 72),
        children: [
          StatTile(icon: Icons.people_alt_rounded, color: context.scheme.primary, value: '${s.total}', label: context.t('hrhome.employees'), onTap: () => context.go('/h/people')),
          StatTile(icon: Icons.fact_check_rounded, color: s.pendingApprovals > 0 ? context.colors.warning : context.colors.success, value: '${s.pendingApprovals}', label: context.t('hrhome.pending'), onTap: () => context.go('/h/approvals')),
          StatTile(icon: Icons.work_outline_rounded, color: context.colors.info, value: '${s.openPositions}', label: context.t('hrhome.open_jobs'), onTap: () => context.push('/h/recruitment')),
          StatTile(icon: Icons.payments_rounded, color: const Color(0xFF10B981), value: compactNumber(context, s.payroll), label: '${context.t('hrhome.payroll')} ($currency)', onTap: () => context.push('/h/payroll')),
        ],
      ),

      if (s.pendingCorrections > 0) ...[
        const SizedBox(height: 14),
        AppCard(
          onTap: () => context.go('/h/approvals'),
          color: context.colors.warning.withValues(alpha: 0.12),
          child: Row(children: [
            IconBadge(Icons.edit_calendar_rounded, color: context.colors.warning),
            const SizedBox(width: 14),
            Expanded(child: Text(context.t('hrhome.corrections', {'n': s.pendingCorrections}), style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35))),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ],

      const WellbeingCard(),

      // ---- 7 day trend
      SectionHeader(context.t('hrhome.trend')),
      AppCard(child: _TrendChart(days: s.trend, total: s.total)),

      // ---- top performers
      if (s.topPerformers.isNotEmpty && (ref.watch(sessionProvider).company?.pointsEnabled ?? true)) ...[
        SectionHeader(context.t('hrhome.top'), action: context.t('common.view_all'), onAction: () => context.push('/h/rewards')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(children: [
            for (final p in s.topPerformers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(width: 24, child: Text('${p.rank}', style: TextStyle(fontWeight: FontWeight.w900, color: p.rank == 1 ? const Color(0xFFF59E0B) : context.colors.subtext))),
                  Avatar(name: p.name, url: p.avatar, size: 32),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${context.t('rewards.level')} ${p.level}${p.levelName.isEmpty ? '' : ' · ${p.levelName}'}', style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                  ])),
                  Icon(Icons.local_fire_department_rounded, color: const Color(0xFFFB923C), size: 18),
                  const SizedBox(width: 2),
                  Text('${p.streak}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
      ],

      // ---- departments
      if (s.departments.isNotEmpty) ...[
        SectionHeader(context.t('hrhome.by_department'), action: context.t('common.view_all'), onAction: () => context.push('/h/departments')),
        AppCard(
          child: Column(children: [
            for (final d in s.departments.take(5)) _DeptBar(name: d.key, count: d.value, max: s.departments.first.value == 0 ? 1 : s.departments.first.value),
          ]),
        ),
      ],

      // ---- upcoming
      if (s.events.isNotEmpty) ...[
        SectionHeader(context.t('hrhome.upcoming')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(children: [
            for (final e in s.events.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Avatar(name: e.name, url: e.avatar, size: 32),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(e.type == 'birthday' ? context.t('hrhome.birthday') : context.t('hrhome.anniversary', {'n': e.years ?? 0}), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                  ])),
                  Icon(e.type == 'birthday' ? Icons.cake_rounded : Icons.emoji_events_rounded, size: 18, color: e.type == 'birthday' ? const Color(0xFFEC4899) : context.colors.warning),
                  const SizedBox(width: 8),
                  Text(e.inDays == 0 ? context.t('common.today') : fmtDayMonth(context, e.date), style: TextStyle(color: context.colors.subtext, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ),
      ],

      // ---- quick actions
      SectionHeader(context.t('hrhome.quick')),
      Wrap(spacing: 0, runSpacing: 10, children: [
        _Quick(Icons.person_add_alt_1_rounded, context.t('hrhome.q_add'), () => context.push('/h/employee/new')),
        _Quick(Icons.campaign_rounded, context.t('hrhome.q_announce'), () => context.push('/announcements')),
        _Quick(Icons.hub_rounded, context.t('more.org'), () => context.push('/org')),
        _Quick(Icons.payments_rounded, context.t('hrhome.q_payroll'), () => context.push('/h/payroll')),
        _Quick(Icons.celebration_rounded, context.t('me.holidays'), () => context.push('/holidays')),
      ]),
    ]);
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  const _HeroStat(this.value, this.label);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 66,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Quick(this.icon, this.label, this.onTap);

  /// App-icon style: a small rounded square with the name under it, four to a row.
  @override
  Widget build(BuildContext context) => SizedBox(
        width: (MediaQuery.of(context).size.width - 32) / 4,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              IconBadge(icon, color: context.scheme.primary, size: 46),
              const SizedBox(height: 5),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
}
class _DeptBar extends StatelessWidget {
  final String name;
  final int count;
  final int max;
  const _DeptBar({required this.name, required this.count, required this.max});

  @override
  Widget build(BuildContext context) {
    final color = colorFor(name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(width: 92, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: max == 0 ? 0 : count / max),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 10, color: color, backgroundColor: color.withValues(alpha: 0.12)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('$count', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<DayCount> days;
  final int total;
  const _TrendChart({required this.days, required this.total});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return SizedBox(height: 90, child: Center(child: Text(context.t('hrhome.no_trend'), style: TextStyle(color: context.colors.subtext))));
    }
    final peak = [total, ...days.map((d) => d.present)].reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in days)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('${d.present}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.colors.subtext)),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: d.present / peak),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Container(
                  width: 22,
                  height: 90 * v + 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [context.scheme.primary, context.scheme.secondary]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(fmtWeekdayShort(context, d.date), style: TextStyle(fontSize: 11, color: context.colors.subtext)),
            ]),
          ),
      ]),
    );
  }
}
