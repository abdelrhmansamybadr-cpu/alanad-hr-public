import '../common/day_explain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';
import 'home_screen.dart';

class TimeScreen extends ConsumerStatefulWidget {
  const TimeScreen({super.key});

  @override
  ConsumerState<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends ConsumerState<TimeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final summary = ref.watch(attendanceSummaryProvider(_month));

    Future<void> refresh() async {
      ref.invalidate(todayProvider);
      ref.invalidate(attendanceSummaryProvider(_month));
      await ref.read(attendanceSummaryProvider(_month).future).catchError((_) => AttendanceSummary(month: _month.month, year: _month.year));
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.t('time.title'))),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            today.when(
              data: (t) => AttendanceHero(info: t),
              loading: () => const Skeleton(height: 210, radius: 24),
              error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(todayProvider)),
            ),
            const SizedBox(height: 20),
            _MonthBar(
              month: _month,
              onPrev: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              onNext: _month.year == DateTime.now().year && _month.month == DateTime.now().month ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
            const SizedBox(height: 12),
            AsyncBody<AttendanceSummary>(
              value: summary,
              onRetry: () => ref.invalidate(attendanceSummaryProvider(_month)),
              loading: const Padding(padding: EdgeInsets.only(top: 8), child: Skeleton(height: 320, radius: 20)),
              builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _SummaryRow(s: s),
                const SizedBox(height: 14),
                _CalendarCard(month: _month, summary: s),
                SectionHeader(context.t('time.log')),
                if (s.records.isEmpty)
                  AppCard(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Center(child: Text(context.t('time.no_records'), style: TextStyle(color: context.colors.subtext)))))
                else
                  ...s.records.reversed.map((r) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _RecordTile(r: r))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const _MonthBar({required this.month, required this.onPrev, this.onNext});

  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton.filledTonal(onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(child: Center(child: Text(fmtMonthYear(context, month), style: context.text.titleMedium))),
        IconButton.filledTonal(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded)),
      ]);
}

class _SummaryRow extends StatelessWidget {
  final AttendanceSummary s;
  const _SummaryRow({required this.s});

  @override
  Widget build(BuildContext context) {
    Widget cell(String v, String l, Color c) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(children: [
              Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 20)),
              const SizedBox(height: 2),
              Text(l, style: TextStyle(color: context.colors.subtext, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
    final extras = <Widget>[
      if (s.half > 0) Pill(context.t('time.s.half', {'n': s.half}), color: statusColor(context, 'half_day'), icon: Icons.contrast_rounded),
      if (s.earlyLeaveDays > 0) Pill(context.t('time.s.early', {'n': s.earlyLeaveDays}), color: context.colors.warning, icon: Icons.logout_rounded),
      if (s.overtimeMinutes > 0) Pill(context.t('time.s.overtime', {'h': (s.overtimeMinutes / 60).toStringAsFixed(1)}), color: context.colors.info, icon: Icons.add_alarm_rounded),
      if (s.outZoneMinutes > 0) Pill(context.t('time.s.away', {'n': s.outZoneMinutes}), color: context.colors.danger, icon: Icons.directions_walk_rounded),
    ];
    return Column(children: [
      Row(children: [
        cell('${s.present + s.late + s.half}', context.t('time.s.present'), context.colors.success),
        const SizedBox(width: 8),
        cell('${s.late}', context.t('time.s.late'), context.colors.warning),
        const SizedBox(width: 8),
        cell('${s.absent}', context.t('time.s.absent'), context.colors.danger),
        const SizedBox(width: 8),
        cell('${s.leave}', context.t('time.s.leave'), context.colors.info),
        const SizedBox(width: 8),
        cell(s.hours.toStringAsFixed(0), context.t('time.s.hours'), context.scheme.primary),
      ]),
      if (extras.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: extras)],
    ]);
  }
}

/// Month grid coloured by what the SERVER decided for each day. Tap a day to see details or ask HR to correct it.
class _CalendarCard extends ConsumerWidget {
  final DateTime month;
  final AttendanceSummary summary;
  const _CalendarCard({required this.month, required this.summary});

  static const _dow = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  Color? _dot(BuildContext context, String? st) {
    switch (st) {
      case 'present':
        return context.colors.success;
      case 'late':
        return context.colors.warning;
      case 'half_day':
        return statusColor(context, 'half_day');
      case 'absent':
        return context.colors.danger;
      case 'on_leave':
        return context.colors.info;
      case 'holiday':
        return const Color(0xFF8B5CF6);
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final byDay = {for (final r in summary.records) ymd(r.date): r};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final lead = first.weekday - 1;
    final cells = <Widget>[for (var i = 0; i < lead; i++) const SizedBox()];
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final key = ymd(date);
      final isFuture = date.isAfter(today);
      final isToday = date == today;
      final st = summary.days[key];
      final dot = _dot(context, st);
      final tappable = !isFuture && (byDay[key] != null || st == 'absent' || st == 'half_day' || st == 'late');
      cells.add(GestureDetector(
        onTap: tappable ? () => showAppSheet(context, title: fmtLongDate(context, date), child: _DaySheet(date: date, record: byDay[key], status: st ?? 'present')) : null,
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isToday ? context.colors.brandSoft : null,
            borderRadius: BorderRadius.circular(12),
            border: isToday ? Border.all(color: context.scheme.primary, width: 1.4) : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$d', style: TextStyle(fontWeight: isToday ? FontWeight.w800 : FontWeight.w600, color: st == 'off' || isFuture ? context.colors.subtext : null)),
            const SizedBox(height: 3),
            Container(width: 7, height: 7, decoration: BoxDecoration(color: dot ?? Colors.transparent, shape: BoxShape.circle)),
          ]),
        ),
      ));
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      child: Column(children: [
        Row(children: [
          for (final d in _dow) Expanded(child: Center(child: Text(context.t('weekday.$d').substring(0, context.isAr ? 3 : 1), style: TextStyle(color: context.colors.subtext, fontWeight: FontWeight.w700, fontSize: 12)))),
        ]),
        const SizedBox(height: 6),
        GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.05, children: cells),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 6, children: [
          _Legend(context.colors.success, context.t('status.present')),
          _Legend(context.colors.warning, context.t('status.late')),
          _Legend(statusColor(context, 'half_day'), context.t('status.half_day')),
          _Legend(context.colors.danger, context.t('status.absent')),
          _Legend(context.colors.info, context.t('status.on_leave')),
          _Legend(const Color(0xFF8B5CF6), context.t('time.legend.holiday')),
        ]),
        const SizedBox(height: 8),
        Text(context.t('time.tap_day'), style: TextStyle(color: context.colors.subtext, fontSize: 11)),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: context.colors.subtext, fontSize: 11)),
      ]);
}

/// Why a day has the status it has, and a way to dispute it.
class _DaySheet extends ConsumerWidget {
  final DateTime date;
  final AttendanceRecord? record;
  final String status;
  const _DaySheet({required this.date, required this.record, required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = record;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [StatusChip(status), const Spacer(), if (r != null && r.hoursWorked > 0) Text(context.t('time.worked', {'h': r.hoursWorked.toStringAsFixed(1)}), style: TextStyle(color: context.colors.subtext))]),
      const SizedBox(height: 12),
      if (r != null) InfoRow(icon: Icons.schedule_rounded, label: context.t('req.corr_times'), value: '${fmtTime(context, r.checkIn)}  →  ${fmtTime(context, r.checkOut)}'),
      const SizedBox(height: 8),
      DayExplainView(
        date: ymd(date),
        disputeButton: OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            showCorrectionForm(context, date: date, record: r);
          },
          icon: const Icon(Icons.edit_calendar_rounded),
          label: Text(context.t('why.dispute')),
        ),
      ),
    ]);
  }
}

class _RecordTile extends StatelessWidget {
  final AttendanceRecord r;
  const _RecordTile({required this.r});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => showAppSheet(context, title: fmtLongDate(context, r.date), child: _DaySheet(date: r.date, record: r, status: r.status)),
        child: Row(children: [
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: context.colors.brandSoft, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text('${r.date.day}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: context.scheme.primary)),
              Text(fmtWeekdayShort(context, r.date), style: TextStyle(fontSize: 10, color: context.scheme.primary)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${fmtTime(context, r.checkIn)}  →  ${fmtTime(context, r.checkOut)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(r.hoursWorked > 0 ? context.t('time.worked', {'h': r.hoursWorked.toStringAsFixed(1)}) : (r.missedCheckout ? context.t('time.missed_checkout') : context.t('time.in_progress')), style: TextStyle(color: context.colors.subtext, fontSize: 13)),
            ]),
          ),
          StatusChip(r.status),
        ]),
      );
}

/// Ask HR to fix a day (forgot to check in/out, phone died, wrong status).
Future<void> showCorrectionForm(BuildContext context, {DateTime? date, AttendanceRecord? record}) {
  return showAppSheet(context, title: context.t('req.type.attendance_correction'), child: _CorrectionForm(date: date ?? DateTime.now().subtract(const Duration(days: 1)), record: record));
}

class _CorrectionForm extends ConsumerStatefulWidget {
  final DateTime date;
  final AttendanceRecord? record;
  const _CorrectionForm({required this.date, this.record});

  @override
  ConsumerState<_CorrectionForm> createState() => _CorrectionFormState();
}

class _CorrectionFormState extends ConsumerState<_CorrectionForm> {
  late DateTime _date = widget.date;
  late TimeOfDay? _in = _parse(widget.record?.checkIn);
  late TimeOfDay? _out = _parse(widget.record?.checkOut);
  final _reason = TextEditingController();
  bool _busy = false;

  TimeOfDay? _parse(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return null;
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 9, minute: int.tryParse(p[1]) ?? 0);
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_in == null) return toast(context, context.t('req.corr_need_in'), error: true);
    if (_reason.text.trim().isEmpty) return toast(context, context.t('common.required'), error: true);
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).post('/requests', {
        'type': 'attendance_correction',
        'title': '${context.t('req.type.attendance_correction')} · ${ymd(_date)}',
        'payload': {'date': ymd(_date), 'check_in': _hhmm(_in!), if (_out != null) 'check_out': _hhmm(_out!), 'reason': _reason.text.trim()},
      });
      ref.invalidate(requestsProvider);
      if (mounted) toast(context, context.t('req.request_sent'));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('req.corr_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 45)), lastDate: DateTime.now());
            if (d != null) setState(() => _date = d);
          },
          child: InputDecorator(decoration: InputDecoration(labelText: context.t('req.corr_date'), prefixIcon: const Icon(Icons.event_rounded)), child: Text(fmtDate(context, _date))),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _in ?? const TimeOfDay(hour: 9, minute: 0));
                if (t != null) setState(() => _in = t);
              },
              child: InputDecorator(decoration: InputDecoration(labelText: context.t('req.corr_in'), prefixIcon: const Icon(Icons.login_rounded)), child: Text(_in == null ? '—' : _in!.format(context))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _out ?? const TimeOfDay(hour: 17, minute: 0));
                if (t != null) setState(() => _out = t);
              },
              child: InputDecorator(decoration: InputDecoration(labelText: context.t('req.corr_out'), prefixIcon: const Icon(Icons.logout_rounded)), child: Text(_out == null ? '—' : _out!.format(context))),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        AppField(controller: _reason, label: context.t('req.corr_reason'), icon: Icons.notes_rounded, maxLines: 3),
        const SizedBox(height: 20),
        LoadingButton(label: context.t('info.send_request'), loading: _busy, onPressed: _send),
      ]);
}
