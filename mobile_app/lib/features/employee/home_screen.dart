import '../common/day_explain.dart';
import '../../core/offline/offline_attendance.dart';
import '../kudos/kudos.dart';
import '../onboarding/onboarding.dart';
import 'dart:async';

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
import '../rewards/rewards_widgets.dart';
import 'attendance_actions.dart';
import 'location_tracker.dart';

class EmployeeHome extends ConsumerWidget {
  const EmployeeHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user!;
    final company = ref.watch(sessionProvider).company!;
    final stats = ref.watch(myStatsProvider);
    final today = ref.watch(todayProvider);
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    Future<void> refresh() async {
      ref.invalidate(myStatsProvider);
      ref.invalidate(todayProvider);
      await Future.wait([ref.read(myStatsProvider.future).catchError((_) => const MyStats()), ref.read(todayProvider.future).catchError((_) => TodayInfo(date: '', serverTime: DateTime.now(), state: 'ready'))]);
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // ---- header
              Row(children: [
                GestureDetector(onTap: () => context.go('/e/me'), child: Avatar(name: user.name, url: user.avatar, size: 48, ring: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(greeting(context), style: TextStyle(color: context.colors.subtext, fontSize: 13)),
                    Text(user.firstName, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                ),
                _CompanyChip(company: company),
                const SizedBox(width: 8),
                NotificationBell(count: unread, onTap: () => context.go('/e/inbox')),
              ]),
              const SizedBox(height: 18),

              // ---- attendance hero
              today.when(
                data: (t) => AttendanceHero(info: t),
                loading: () => const Skeleton(height: 210, radius: 24),
                error: (e, _) => AppCard(child: ErrorState(e, onRetry: () => ref.invalidate(todayProvider))),
              ),
              const SizedBox(height: 18),

              AppCard(
                onTap: () => context.push('/assistant'),
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  IconBadge(Icons.auto_awesome_rounded, color: context.scheme.primary, size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.t('assistant.card'), style: const TextStyle(fontWeight: FontWeight.w800)), Text(context.t('assistant.card_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))])),
                  const Icon(Icons.chevron_right_rounded),
                ]),
              ),
              const SizedBox(height: 14),
              const OnboardingCard(),
              const KudosCard(),

              // ---- reward points
              stats.maybeWhen(
                data: (s) => company.pointsEnabled && s.points != null
                    ? Padding(padding: const EdgeInsets.only(bottom: 18), child: RewardsCard(brief: s.points!, onTap: () => context.push('/rewards')))
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),

              // ---- team approvals (team leads)
              stats.maybeWhen(
                data: (s) => s.isTeamLead && s.pendingApprovals > 0
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: AppCard(
                          onTap: () => context.push('/approvals'),
                          color: context.colors.brandSoft,
                          child: Row(children: [
                            IconBadge(Icons.fact_check_rounded, color: context.scheme.primary),
                            const SizedBox(width: 14),
                            Expanded(child: Text(context.t('home.team_waiting', {'n': s.pendingApprovals}), style: const TextStyle(fontWeight: FontWeight.w700))),
                            const Icon(Icons.chevron_right_rounded),
                          ]),
                        ),
                      )
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),

              // ---- quick actions
              const _QuickActions(),

              // ---- everything below needs the stats call
              stats.when(
                data: (s) => _StatsSections(stats: s),
                loading: () => const Padding(padding: EdgeInsets.only(top: 24), child: Column(children: [Skeleton(height: 110, radius: 20), SizedBox(height: 14), Skeleton(height: 90, radius: 20)])),
                error: (e, _) => Padding(padding: const EdgeInsets.only(top: 24), child: ErrorState(e, onRetry: () => ref.invalidate(myStatsProvider))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyChip extends StatelessWidget {
  final Company company;
  const _CompanyChip({required this.company});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 110),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: context.colors.brandSoft, borderRadius: BorderRadius.circular(20)),
        child: Text(company.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

// ============================================================ attendance hero card

class AttendanceHero extends ConsumerStatefulWidget {
  final TodayInfo info;
  const AttendanceHero({super.key, required this.info});

  @override
  ConsumerState<AttendanceHero> createState() => _AttendanceHeroState();
}

class _AttendanceHeroState extends ConsumerState<AttendanceHero> {
  Timer? _tick;
  late Duration _offset; // server time - device time, so the clock matches the company's time zone
  DateTime _now = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sync();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now().add(_offset)));
  }

  @override
  void didUpdateWidget(covariant AttendanceHero old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    // server time is given with the company's UTC offset; compare wall clock digits
    final s = widget.info.serverTime;
    final deviceNow = DateTime.now();
    _offset = DateTime(s.year, s.month, s.day, s.hour, s.minute, s.second).difference(deviceNow);
    _now = deviceNow.add(_offset);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _press(bool checkOut) async {
    final confirmTitle = context.t('time.confirm_out');
    final confirmLabel = context.t('time.check_out');
    if (checkOut && !await confirmDialog(context, title: confirmTitle, confirmLabel: confirmLabel)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    await performAttendance(context, ref, widget.info, checkOut: checkOut);
    if (mounted) setState(() => _busy = false);
  }

  String _elapsed(String? checkIn) {
    if (checkIn == null) return '';
    final p = checkIn.split(':');
    final start = DateTime(_now.year, _now.month, _now.day, int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0);
    final d = _now.difference(start);
    if (d.isNegative) return '';
    return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final rec = info.record;
    final state = info.state;
    final blocked = info.onLeave != null;

    String statusText;
    if (blocked) {
      statusText = context.t('time.on_leave_today', {'type': info.onLeave});
    } else if (state == 'checked_out') {
      statusText = context.t('time.done_today', {'hours': (rec?.hoursWorked ?? 0).toStringAsFixed(1)});
    } else if (state == 'checked_in') {
      statusText = context.t('time.since', {'time': fmtTime(context, rec?.checkIn), 'elapsed': _elapsed(rec?.checkIn)});
    } else if (info.holiday != null) {
      statusText = context.t('time.holiday', {'name': info.holiday});
    } else if (info.isWeekend) {
      statusText = context.t('time.weekend');
    } else {
      statusText = context.t('time.not_checked_in');
    }

    return Container(
      decoration: BoxDecoration(
        gradient: brandGradient(context),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: context.scheme.primary.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${fmtWeekdayShort(context, _now)}, ${fmtDayMonth(context, _now)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          if (info.shiftStart != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.schedule_rounded, size: 14, color: Colors.white),
                const SizedBox(width: 5),
                Text('${fmtTime(context, info.shiftStart)} – ${fmtTime(context, info.shiftEnd)}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
        const SizedBox(height: 10),
        Text(fmtClock(context, _now), style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1)),
        const SizedBox(height: 4),
        Text(statusText, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
        if (ref.watch(pendingAttendanceProvider) > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.cloud_off_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(context.t('offline.pending'), style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3))),
            ]),
          ),
        ],
        if (rec != null) ...[
          const SizedBox(height: 10),
          _StatusPills(rec: rec),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white, padding: EdgeInsets.zero, minimumSize: const Size(0, 34), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: () => showAppSheet(context, title: context.t('why.title'), child: DayExplainView(date: ymd(rec.date))),
              icon: const Icon(Icons.help_outline_rounded, size: 17),
              label: Text(context.t('why.button'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        if (state == 'checked_in' && info.hasZoneRule) ...[
          const SizedBox(height: 10),
          _ZoneBanner(info: info, zone: ref.watch(zoneStatusProvider), rec: rec),
        ],
        const SizedBox(height: 18),
        if (blocked || state == 'checked_out')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(blocked ? Icons.beach_access_rounded : Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text(blocked ? context.t('time.enjoy') : context.t('time.see_you'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]),
          )
        else
          FilledButton.icon(
            onPressed: _busy ? null : () => _press(state == 'checked_in'),
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                : Icon(state == 'checked_in' ? Icons.logout_rounded : Icons.login_rounded),
            label: Text(state == 'checked_in' ? context.t('time.check_out') : context.t('time.check_in')),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: state == 'checked_in' ? context.colors.danger : context.scheme.primary,
              disabledBackgroundColor: Colors.white70,
            ),
          ),
        if ((info.locationRequired || info.wifiRequired) && state != 'checked_in') ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(info.locationRequired ? Icons.location_on_outlined : Icons.wifi_rounded, size: 14, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                info.locationRequired && info.wifiRequired
                    ? context.t(info.matchMode == 'all' ? 'time.rule_both_all' : 'time.rule_both_any', {'ssid': info.wifiSsid ?? ''})
                    : info.wifiRequired
                        ? context.t('time.rule_wifi', {'ssid': info.wifiSsid ?? ''})
                        : context.t('time.rule_location'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, height: 1.35),
              ),
            ),
          ]),
        ],
        if (state == 'ready' && !blocked && info.isWorkday) ...[
          const SizedBox(height: 10),
          Text(context.t('time.auto_note', {'grace': info.lateGraceMinutes}), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5, height: 1.35)),
        ],
      ]),
    );
  }
}

// ================================================================== quick actions

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.beach_access_rounded, context.t('home.qa.leave'), const Color(0xFF6366F1), () => context.go('/e/requests')),
      (Icons.receipt_long_rounded, context.t('home.qa.payslips'), const Color(0xFF10B981), () => context.push('/payslips')),
      (Icons.folder_copy_rounded, context.t('home.qa.documents'), const Color(0xFFF59E0B), () => context.push('/documents')),
      (Icons.people_alt_rounded, context.t('home.qa.directory'), const Color(0xFF0EA5E9), () => context.push('/directory')),
    ];
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: items[i].$4,
            child: Column(children: [
              Container(
                height: 60,
                decoration: BoxDecoration(color: items[i].$3.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
                child: Center(child: Icon(items[i].$1, color: items[i].$3, size: 28)),
              ),
              const SizedBox(height: 8),
              Text(items[i].$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      ],
    ]);
  }
}

// ================================================================ stats sections

class _StatsSections extends ConsumerWidget {
  final MyStats stats;
  const _StatsSections({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = <Widget>[];

    // leave balances
    final limited = stats.balances.where((b) => !b.unlimited).toList();
    if (limited.isNotEmpty) {
      children.add(SectionHeader(context.t('home.leave_balance'), action: context.t('common.view_all'), onAction: () => context.go('/e/requests')));
      children.add(SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: limited.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => _BalanceCard(b: limited[i]),
        ),
      ));
    }

    // this month
    children.add(SectionHeader(context.t('home.this_month')));
    children.add(Row(children: [
      Expanded(child: _MiniStat(icon: Icons.check_circle_outline_rounded, color: context.colors.success, value: '${stats.monthPresent}', label: context.t('home.days_present'))),
      const SizedBox(width: 10),
      Expanded(child: _MiniStat(icon: Icons.timer_outlined, color: context.colors.warning, value: '${stats.monthLate}', label: context.t('home.days_late'))),
      const SizedBox(width: 10),
      Expanded(child: _MiniStat(icon: Icons.access_time_rounded, color: context.colors.info, value: stats.monthHours.toStringAsFixed(0), label: context.t('home.hours'))),
    ]));

    // who is out
    if (stats.onLeaveToday.isNotEmpty) {
      children.add(SectionHeader(context.t('home.out_today')));
      children.add(AppCard(
        child: SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stats.onLeaveToday.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, i) {
              final p = stats.onLeaveToday[i];
              return SizedBox(
                width: 56,
                child: Column(children: [
                  Avatar(name: p.name, url: p.avatar, size: 42),
                  const SizedBox(height: 6),
                  Text(p.name.split(' ').first, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              );
            },
          ),
        ),
      ));
    }

    // next holiday
    if (stats.nextHoliday != null) {
      final h = stats.nextHoliday!;
      final days = DateTime(h.date.year, h.date.month, h.date.day).difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays;
      children.add(const SizedBox(height: 14));
      children.add(AppCard(
        onTap: () => context.push('/holidays'),
        child: Row(children: [
          IconBadge(Icons.celebration_rounded, color: context.colors.warning),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(fmtLongDate(context, h.date), style: TextStyle(color: context.colors.subtext, fontSize: 13)),
          ])),
          Pill(days <= 0 ? context.t('common.today') : context.t('home.in_days', {'n': days}), color: context.colors.warning),
        ]),
      ));
    }

    // announcements
    if (stats.announcements.isNotEmpty) {
      children.add(SectionHeader(context.t('home.announcements'), action: context.t('common.view_all'), onAction: () => context.push('/announcements')));
      for (final a in stats.announcements) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RowTile(
            leading: IconBadge(Icons.campaign_rounded, color: a.priority == 'high' ? context.colors.danger : context.scheme.primary),
            title: a.title,
            subtitle: timeAgo(context, a.createdAt),
            trailing: a.priority == 'high' ? StatusChip('high', label: context.t('priority.high'), color: context.colors.danger) : null,
            onTap: () => context.push('/announcements'),
          ),
        ));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _BalanceCard extends StatelessWidget {
  final LeaveBalance b;
  const _BalanceCard({required this.b});

  @override
  Widget build(BuildContext context) {
    final color = hexColor(b.color);
    final remaining = b.remaining ?? 0;
    return SizedBox(
      width: 132,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProgressRing(
            value: b.total == 0 ? 0 : remaining / b.total,
            color: color,
            size: 56,
            stroke: 7,
            child: Text('$remaining', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color)),
          ),
          const Spacer(),
          Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(context.t('home.of_days', {'n': b.total}), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _MiniStat({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: context.colors.subtext, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}


// ============================================================ automatic status

/// What the server decided (never chosen by the employee): on time / late / half day ...
class _StatusPills extends StatelessWidget {
  final AttendanceRecord rec;
  const _StatusPills({required this.rec});

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[];
    switch (rec.status) {
      case 'late':
        pills.add(Pill(context.t('time.late_by', {'n': rec.lateMinutes}), color: Colors.white, icon: Icons.timer_outlined));
        break;
      case 'half_day':
        pills.add(Pill(context.t('status.half_day'), color: Colors.white, icon: Icons.contrast_rounded));
        break;
      case 'absent':
        pills.add(Pill(context.t('status.absent'), color: Colors.white, icon: Icons.person_off_rounded));
        break;
      default:
        pills.add(Pill(context.t('time.on_time'), color: Colors.white, icon: Icons.verified_rounded));
    }
    if (rec.earlyLeaveMinutes > 0 && rec.checkOut != null) pills.add(Pill(context.t('time.left_early', {'n': rec.earlyLeaveMinutes}), color: Colors.white, icon: Icons.logout_rounded));
    if (rec.overtimeMinutes > 0) pills.add(Pill(context.t('time.overtime', {'n': rec.overtimeMinutes}), color: Colors.white, icon: Icons.add_alarm_rounded));
    if (rec.outZoneMinutes > 0) pills.add(Pill(context.t('time.away_minutes', {'n': rec.outZoneMinutes}), color: Colors.white, icon: Icons.directions_walk_rounded));
    if (rec.missedCheckout) pills.add(Pill(context.t('time.missed_checkout'), color: Colors.white, icon: Icons.warning_amber_rounded));
    return Wrap(spacing: 8, runSpacing: 6, children: pills);
  }
}

/// Live "at the workplace / away" line under the clock while checked in.
class _ZoneBanner extends StatelessWidget {
  final TodayInfo info;
  final ZoneStatus? zone;
  final AttendanceRecord? rec;
  const _ZoneBanner({required this.info, required this.zone, required this.rec});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String text;
    Color bg;
    if (zone == null) {
      icon = Icons.my_location_rounded;
      text = context.t('zone.checking');
      bg = Colors.white.withValues(alpha: 0.14);
    } else if (zone!.error != null) {
      icon = Icons.location_off_rounded;
      text = context.t(zone!.error == 'permission' ? 'zone.need_permission' : zone!.error == 'gps' ? 'zone.need_gps' : 'zone.need_fix');
      bg = const Color(0xFFF59E0B).withValues(alpha: 0.4);
    } else if (zone!.inside) {
      icon = Icons.check_circle_rounded;
      text = context.t('zone.inside');
      bg = const Color(0xFF22C55E).withValues(alpha: 0.35);
    } else {
      icon = Icons.directions_walk_rounded;
      final away = zone!.outMinutes;
      final limit = info.outZoneHalfDayMinutes;
      text = limit > 0 ? context.t('zone.outside_limit', {'n': away, 'limit': limit}) : context.t('zone.outside', {'n': away});
      bg = const Color(0xFFEF4444).withValues(alpha: 0.42);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
    );
  }
}
