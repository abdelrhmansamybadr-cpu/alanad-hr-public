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

/// HR: who is in, late, half day, absent or on leave for a chosen day. Statuses are computed by the
/// server from the shift, the times and the location — HR can correct the times (and only by exception
/// force a status).
class AttendanceBoardScreen extends ConsumerStatefulWidget {
  const AttendanceBoardScreen({super.key});

  @override
  ConsumerState<AttendanceBoardScreen> createState() => _AttendanceBoardScreenState();
}

class _AttendanceBoardScreenState extends ConsumerState<AttendanceBoardScreen> {
  DateTime _day = DateTime.now();
  String _filter = ''; // '' = all, else a board status, or 'outside'

  static const _filters = ['', 'present', 'late', 'half_day', 'absent', 'on_leave', 'not_in', 'outside'];

  @override
  Widget build(BuildContext context) {
    final key = ymd(_day);
    final board = ref.watch(boardProvider(key));
    final isToday = ymd(DateTime.now()) == key;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('board.title'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            IconButton.filledTonal(onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (d != null) setState(() => _day = d);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    Text(isToday ? context.t('common.today') : fmtWeekday(context, _day), style: context.text.titleMedium),
                    Text(fmtDate(context, _day), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                  ]),
                ),
              ),
            ),
            IconButton.filledTonal(onPressed: isToday ? null : () => setState(() => _day = _day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(boardProvider(key));
              await ref.read(boardProvider(key).future).catchError((_) => (counts: <String, int>{}, holiday: null, rows: <BoardRow>[]));
            },
            child: AsyncBody<({Map<String, int> counts, String? holiday, List<BoardRow> rows})>(
              value: board,
              onRetry: () => ref.invalidate(boardProvider(key)),
              builder: (b) {
                final rows = _filter.isEmpty ? b.rows : (_filter == 'outside' ? b.rows.where((r) => r.outsideNow).toList() : b.rows.where((r) => r.status == _filter).toList());
                final outside = b.rows.where((r) => r.outsideNow).length;
                return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), physics: const AlwaysScrollableScrollPhysics(), children: [
                  if (b.holiday != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppCard(color: context.colors.warning.withValues(alpha: 0.12), child: Row(children: [Icon(Icons.celebration_rounded, color: context.colors.warning), const SizedBox(width: 12), Expanded(child: Text(context.t('time.holiday', {'name': b.holiday}), style: const TextStyle(fontWeight: FontWeight.w700)))])),
                    ),
                  Row(children: [
                    _Count('${b.counts['present'] ?? 0}', context.t('status.present'), context.colors.success),
                    const SizedBox(width: 8),
                    _Count('${b.counts['late'] ?? 0}', context.t('status.late'), context.colors.warning),
                    const SizedBox(width: 8),
                    _Count('${b.counts['half_day'] ?? 0}', context.t('status.half_day'), statusColor(context, 'half_day')),
                    const SizedBox(width: 8),
                    _Count('${b.counts['absent'] ?? 0}', context.t('status.absent'), context.colors.danger),
                    const SizedBox(width: 8),
                    _Count('${b.counts['on_leave'] ?? 0}', context.t('status.on_leave'), context.colors.info),
                  ]),
                  if ((b.counts['not_in'] ?? 0) > 0 || outside > 0) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if ((b.counts['not_in'] ?? 0) > 0) Pill(context.t('board.not_in_n', {'n': b.counts['not_in']}), color: context.colors.subtext, icon: Icons.hourglass_empty_rounded),
                      if (outside > 0) Pill(context.t('board.outside_n', {'n': outside}), color: context.colors.danger, icon: Icons.directions_walk_rounded),
                    ]),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 40,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final f in _filters)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(f.isEmpty ? context.t('common.all') : (f == 'outside' ? context.t('board.outside') : context.t('status.$f'))),
                            selected: _filter == f,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _filter = f),
                            selectedColor: context.scheme.primary,
                            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _filter == f ? Colors.white : context.scheme.onSurface),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    Padding(padding: const EdgeInsets.only(top: 40), child: EmptyState(icon: Icons.event_busy_rounded, title: context.t('common.no_results')))
                  else
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RowTile(
                          leading: Avatar(name: r.name, url: r.avatar, size: 46),
                          title: r.name,
                          subtitle: _subtitle(context, r),
                          trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            StatusChip(r.status),
                            if (r.outsideNow) Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.directions_walk_rounded, size: 16, color: context.colors.danger)),
                            if (r.securityFlags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.gpp_maybe_rounded, size: 17, color: context.colors.warning)),
                          ]),
                          onTap: r.status == 'on_leave' || r.status == 'off' || r.status == 'holiday' ? null : () => _edit(r, key),
                        ),
                      ),
                ]);
              },
            ),
          ),
        ),
      ]),
    );
  }

  String _subtitle(BuildContext context, BoardRow r) {
    if (r.status == 'on_leave') return r.leaveType ?? context.t('status.on_leave');
    if (r.checkIn == null) return r.position;
    final parts = <String>['${fmtTime(context, r.checkIn)} → ${fmtTime(context, r.checkOut)}'];
    if (r.lateMinutes > 0) parts.add(context.t('time.late_by', {'n': r.lateMinutes}));
    if (r.earlyLeaveMinutes > 0 && r.checkOut != null) parts.add(context.t('time.left_early', {'n': r.earlyLeaveMinutes}));
    if (r.outZoneMinutes > 0) parts.add(context.t('time.away_minutes', {'n': r.outZoneMinutes}));
    if (r.flags.contains('missed_checkout')) parts.add(context.t('time.missed_checkout'));
    return parts.join(' · ');
  }

  Future<void> _edit(BoardRow r, String date) async {
    await showAppSheet(context, title: r.name, child: _RecordForm(row: r, date: date));
    ref.invalidate(boardProvider(date));
    ref.invalidate(hrStatsProvider);
  }
}

class _Count extends StatelessWidget {
  final String v;
  final String l;
  final Color c;
  const _Count(this.v, this.l, this.c);

  @override
  Widget build(BuildContext context) => Expanded(
        child: AppCard(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Column(children: [Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 20)), const SizedBox(height: 2), FittedBox(fit: BoxFit.scaleDown, child: Text(l, style: TextStyle(color: context.colors.subtext, fontSize: 11)))]),
        ),
      );
}

TimeOfDay? _parse(String? hhmm) {
  if (hhmm == null || hhmm.length < 4) return null;
  final p = hhmm.split(':');
  return TimeOfDay(hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
}

String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _RecordForm extends ConsumerStatefulWidget {
  final BoardRow row;
  final String date;
  const _RecordForm({required this.row, required this.date});

  @override
  ConsumerState<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends ConsumerState<_RecordForm> {
  late TimeOfDay? _in = _parse(widget.row.checkIn);
  late TimeOfDay? _out = _parse(widget.row.checkOut);
  String _override = ''; // '' = automatic
  bool _busy = false;

  Future<void> _pickTime(TimeOfDay? initial, ValueChanged<TimeOfDay> done) async {
    final t = await showTimePicker(context: context, initialTime: initial ?? TimeOfDay.now());
    if (t != null) setState(() => done(t));
  }

  Future<void> _save() async {
    if (_in == null && _override.isEmpty) {
      toast(context, context.t('board.need_in'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final body = {
        'employeeId': widget.row.employeeId,
        'date': widget.date,
        'checkIn': _in == null ? '' : _fmt(_in!),
        'checkOut': _out == null ? '' : _fmt(_out!),
        if (_override.isNotEmpty) 'status': _override,
      };
      final api = ref.read(apiProvider);
      if (widget.row.attendanceId == null) {
        await api.post('/attendance', body);
      } else {
        await api.put('/attendance/${widget.row.attendanceId}', body);
      }
      ref.invalidate(employeePointsProvider(widget.row.employeeId));
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
    final r = widget.row;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (r.attendanceId != null)
        AppCard(
          color: context.colors.surfaceAlt,
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 10, runSpacing: 8, children: [
            StatusChip(r.status),
            if (r.lateMinutes > 0) Pill(context.t('time.late_by', {'n': r.lateMinutes}), color: context.colors.warning),
            if (r.earlyLeaveMinutes > 0) Pill(context.t('time.left_early', {'n': r.earlyLeaveMinutes}), color: context.colors.warning),
            if (r.outZoneMinutes > 0) Pill(context.t('time.away_minutes', {'n': r.outZoneMinutes}), color: context.colors.danger),
            if (r.overtimeMinutes > 0) Pill(context.t('time.overtime', {'n': r.overtimeMinutes}), color: context.colors.info),
            if (r.flags.contains('missed_checkout')) Pill(context.t('time.missed_checkout'), color: context.colors.danger),
            for (final f in r.securityFlags) Pill(context.t('sec.$f'), color: context.colors.warning, icon: Icons.gpp_maybe_rounded),
          ]),
        ),
      if (r.attendanceId != null || r.status == 'absent')
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton.icon(
            onPressed: () => showAppSheet(context, title: context.t('why.title'), child: DayExplainView(date: widget.date, employeeId: r.employeeId)),
            icon: const Icon(Icons.help_outline_rounded, size: 18),
            label: Text(context.t('why.hr_button')),
          ),
        ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _TimeBox(label: context.t('board.check_in'), value: _in, onTap: () => _pickTime(_in, (t) => _in = t))),
        const SizedBox(width: 12),
        Expanded(child: _TimeBox(label: context.t('board.check_out'), value: _out, onTap: () => _pickTime(_out, (t) => _out = t))),
      ]),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: _override,
        decoration: InputDecoration(labelText: context.t('board.status_mode'), prefixIcon: const Icon(Icons.auto_awesome_rounded)),
        items: [
          DropdownMenuItem(value: '', child: Text(context.t('board.status_auto'))),
          for (final s in ['present', 'late', 'half_day', 'absent']) DropdownMenuItem(value: s, child: Text(context.t('board.status_force', {'s': context.t('status.$s')}))),
        ],
        onChanged: (v) => setState(() => _override = v ?? ''),
      ),
      Padding(padding: const EdgeInsets.only(top: 8), child: Text(_override.isEmpty ? context.t('board.status_auto_hint') : context.t('board.status_force_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.4))),
      const SizedBox(height: 20),
      LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
      if (r.attendanceId != null) ...[
        const SizedBox(height: 10),
        TextButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            if (!await confirmDialog(context, title: context.t('common.delete'), danger: true, confirmLabel: context.t('common.delete'))) return;
            try {
              await ref.read(apiProvider).delete('/attendance/${r.attendanceId}');
              nav.pop();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          },
          child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
        ),
      ],
    ]);
  }
}

class _TimeBox extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;
  const _TimeBox({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.access_time_rounded)),
          child: Text(value == null ? '—' : value!.format(context)),
        ),
      );
}
