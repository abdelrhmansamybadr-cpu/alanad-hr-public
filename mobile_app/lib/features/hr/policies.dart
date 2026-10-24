import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

/// Admin: every automatic rule of the company in one place — attendance, reward points, payroll.
class PoliciesScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const PoliciesScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends ConsumerState<PoliciesScreen> {
  late int _tab = widget.initialTab;
  late final Map<String, dynamic> _att = Map.of(ref.read(sessionProvider).company!.attendancePolicy);
  late final Map<String, dynamic> _pts = Map.of(ref.read(sessionProvider).company!.pointsConfig);
  late final Map<String, dynamic> _pay = Map.of(ref.read(sessionProvider).company!.payrollPolicy);
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final key = ['attendancePolicy', 'pointsConfig', 'payrollPolicy'][_tab];
      final body = [_att, _pts, _pay][_tab];
      await ref.read(apiProvider).put('/company', {key: body});
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) toast(context, context.t('policy.saved'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recalc() async {
    if (!await confirmDialog(context, title: context.t('policy.pts.recalc'), message: context.t('policy.pts.recalc_hint'), confirmLabel: context.t('common.confirm'))) return;
    try {
      await ref.read(apiProvider).post('/points/recalculate', {});
      ref.invalidate(leaderboardProvider);
      if (mounted) toast(context, context.t('policy.pts.recalc_done'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('policy.title'))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SegmentBar(labels: [context.t('policy.tab_att'), context.t('policy.tab_pts'), context.t('policy.tab_pay')], index: _tab, onChanged: (i) => setState(() => _tab = i))),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            if (_tab == 0) ..._attendance(context),
            if (_tab == 1) ..._points(context),
            if (_tab == 2) ..._payroll(context),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save)),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ helpers
  int _i(Map<String, dynamic> m, String k, int d) => m[k] is num ? (m[k] as num).toInt() : d;
  double _d(Map<String, dynamic> m, String k, double d) => m[k] is num ? (m[k] as num).toDouble() : d;
  bool _b(Map<String, dynamic> m, String k, bool d) => m[k] is bool ? m[k] as bool : d;
  String _s(Map<String, dynamic> m, String k, String d) => m[k] is String ? m[k] as String : d;

  Widget _group(String title, String? hint, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.4))),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );

  Widget _step(Map<String, dynamic> m, String key, String label, {String? hint, int min = 0, int max = 1000, int step = 5, int def = 0, String unit = ''}) {
    final v = _i(m, key, def);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (hint != null) Text(hint, style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.3)),
          ]),
        ),
        IconButton.filledTonal(visualDensity: VisualDensity.compact, onPressed: v <= min ? null : () => setState(() => m[key] = (v - step).clamp(min, max)), icon: const Icon(Icons.remove_rounded)),
        SizedBox(width: 62, child: Center(child: Text(v == 0 && unit.isNotEmpty ? context.t('policy.off') : '$v$unit', style: const TextStyle(fontWeight: FontWeight.w800)))),
        IconButton.filledTonal(visualDensity: VisualDensity.compact, onPressed: v >= max ? null : () => setState(() => m[key] = (v + step).clamp(min, max)), icon: const Icon(Icons.add_rounded)),
      ]),
    );
  }

  Widget _stepD(Map<String, dynamic> m, String key, String label, {String? hint, double min = 0, double max = 10, double step = 0.25, double def = 0, String suffix = ''}) {
    final v = _d(m, key, def);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (hint != null) Text(hint, style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.3)),
          ]),
        ),
        IconButton.filledTonal(visualDensity: VisualDensity.compact, onPressed: v <= min ? null : () => setState(() => m[key] = double.parse((v - step).clamp(min, max).toStringAsFixed(2))), icon: const Icon(Icons.remove_rounded)),
        SizedBox(width: 62, child: Center(child: Text('${v == v.roundToDouble() ? v.toInt() : v}$suffix', style: const TextStyle(fontWeight: FontWeight.w800)))),
        IconButton.filledTonal(visualDensity: VisualDensity.compact, onPressed: v >= max ? null : () => setState(() => m[key] = double.parse((v + step).clamp(min, max).toStringAsFixed(2))), icon: const Icon(Icons.add_rounded)),
      ]),
    );
  }

  Widget _switch(Map<String, dynamic> m, String key, String label, {String? hint, bool def = false}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: hint == null ? null : Text(hint, style: TextStyle(fontSize: 12, color: context.colors.subtext, height: 1.3)),
        value: _b(m, key, def),
        onChanged: (v) => setState(() => m[key] = v),
      );

  /// A number box for amounts that are too big for the +/- steppers (insurance cap, tax-free amount...).
  Widget _money(Map<String, dynamic> m, String key, String label, {String? hint}) {
    final v = _d(m, key, 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        key: ValueKey('$key-${v.toStringAsFixed(2)}'),
        initialValue: v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString()),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (t) => m[key] = double.tryParse(t.trim().replaceAll(',', '.')) ?? 0.0,
        decoration: InputDecoration(labelText: label, helperText: hint, helperMaxLines: 3, prefixIcon: const Icon(Icons.payments_outlined)),
      ),
    );
  }

  /// Tax steps, one per line: "5000 0", "10000 10", "- 20"  (up to this monthly amount, the rate in %; "-" = everything above).
  Widget _brackets(Map<String, dynamic> m) {
    final list = (m['taxBrackets'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final text = list.map((e) {
      final p = e.split('|');
      return '${p[0].isEmpty ? '-' : p[0]} ${p.length > 1 ? p[1] : '0'}';
    }).join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        key: ValueKey('brackets-$text'),
        initialValue: text,
        minLines: 3,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        onChanged: (t) {
          m['taxBrackets'] = [
            for (final line in t.split('\n'))
              if (RegExp(r'^\s*(-|\*|\d+(\.\d+)?)\s*[ :|]\s*\d+(\.\d+)?\s*$').hasMatch(line))
                () {
                  final parts = line.trim().split(RegExp(r'\s*[ :|]\s*'));
                  final upTo = (parts[0] == '-' || parts[0] == '*') ? '' : parts[0];
                  return '$upTo|${parts[1]}';
                }(),
          ];
        },
        decoration: InputDecoration(labelText: context.t('policy.tax.brackets'), helperText: context.t('policy.tax.brackets_hint'), helperMaxLines: 5, prefixIcon: const Icon(Icons.stacked_bar_chart_rounded)),
      ),
    );
  }

  Widget _seg(Map<String, dynamic> m, String key, String label, List<String> values, String prefix, {String def = ''}) {
    final cur = values.indexOf(_s(m, key, def));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentBar(labels: [for (final v in values) context.t('$prefix.$v')], index: cur < 0 ? 0 : cur, onChanged: (i) => setState(() => m[key] = values[i])),
      ]),
    );
  }

  Widget _time(Map<String, dynamic> m, String key, String label, String def) {
    final v = _s(m, key, def);
    final p = v.split(':');
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 9, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0));
          if (t != null) setState(() => m[key] = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
        },
        child: InputDecorator(decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.access_time_rounded)), child: Text(v)),
      ),
    );
  }

  // ---------------------------------------------------------------- attendance
  List<Widget> _attendance(BuildContext context) => [
        _group(context.t('policy.att.hours'), context.t('policy.att.hours_hint'), [
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Row(children: [_time(_att, 'defaultStart', context.t('org.starts'), '09:00'), const SizedBox(width: 12), _time(_att, 'defaultEnd', context.t('org.ends'), '17:00')])),
        ]),
        _group(context.t('policy.att.late'), context.t('policy.att.late_hint'), [
          _step(_att, 'halfDayLateMinutes', context.t('policy.att.half_late'), hint: context.t('policy.att.half_late_hint'), max: 480, step: 15, def: 120, unit: ' m'),
          _step(_att, 'absentLateMinutes', context.t('policy.att.absent_late'), hint: context.t('policy.att.absent_late_hint'), max: 600, step: 15, unit: ' m'),
        ]),
        _group(context.t('policy.att.leave'), null, [
          _step(_att, 'earlyLeaveGraceMinutes', context.t('policy.att.early_grace'), hint: context.t('policy.att.early_grace_hint'), max: 120, def: 10, unit: ' m'),
          _step(_att, 'halfDayEarlyMinutes', context.t('policy.att.half_early'), hint: context.t('policy.att.half_early_hint'), max: 480, step: 15, def: 120, unit: ' m'),
          _step(_att, 'halfDayMinHoursPct', context.t('policy.att.half_hours'), hint: context.t('policy.att.half_hours_hint'), max: 100, def: 50, unit: '%'),
          _step(_att, 'absentMinHoursPct', context.t('policy.att.absent_hours'), hint: context.t('policy.att.absent_hours_hint'), max: 100, unit: '%'),
          _step(_att, 'overtimeAfterMinutes', context.t('policy.att.overtime'), hint: context.t('policy.att.overtime_hint'), max: 240, def: 30, unit: ' m'),
        ]),
        _group(context.t('policy.att.zone'), context.t('policy.att.zone_hint'), [
          _switch(_att, 'trackLocation', context.t('policy.att.track'), hint: context.t('policy.att.track_hint'), def: true),
          _step(_att, 'pingIntervalMinutes', context.t('policy.att.ping'), min: 1, max: 30, step: 1, def: 5, unit: ' m'),
          _step(_att, 'outZoneHalfDayMinutes', context.t('policy.att.out_half'), hint: context.t('policy.att.out_half_hint'), max: 480, step: 15, def: 120, unit: ' m'),
          _switch(_att, 'allowCheckoutOutside', context.t('policy.att.out_checkout'), hint: context.t('policy.att.out_checkout_hint'), def: true),
        ]),
        _group(context.t('policy.trust.title'), context.t('policy.trust.hint'), [
          _switch(_att, 'blockMockLocation', context.t('policy.trust.mock'), hint: context.t('policy.trust.mock_hint'), def: true),
          _switch(_att, 'blockSharedDevice', context.t('policy.trust.shared'), hint: context.t('policy.trust.shared_hint')),
          _step(_att, 'offlineMaxHours', context.t('policy.trust.offline'), hint: context.t('policy.trust.offline_hint'), max: 72, step: 1, def: 12, unit: ' h'),
          _switch(_att, 'reminders', context.t('policy.trust.reminders'), hint: context.t('policy.trust.reminders_hint'), def: true),
        ]),
        _group(context.t('policy.preset.title'), context.t('policy.preset.hint'), [
          _seg(_att, 'leavePreset', context.t('policy.preset.label'), const ['none', 'egypt'], 'policy.preset', def: 'none'),
        ]),
        _group(context.t('policy.att.missed'), null, [
          _seg(_att, 'missedCheckout', context.t('policy.att.missed_label'), const ['flag', 'half_day', 'absent'], 'policy.missed', def: 'flag'),
          _step(_att, 'autoCloseAfterHours', context.t('policy.att.auto_close'), hint: context.t('policy.att.auto_close_hint'), min: 1, max: 24, step: 1, def: 4, unit: ' h'),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(onPressed: () => context.push('/h/attendance-rules'), icon: const Icon(Icons.pin_drop_rounded), label: Text(context.t('policy.att.open_rules'))),
        ),
      ];

  // -------------------------------------------------------------------- points
  List<Widget> _points(BuildContext context) => [
        _group(context.t('policy.pts.general'), context.t('policy.pts.general_hint'), [
          _switch(_pts, 'enabled', context.t('policy.pts.enabled'), def: true),
          _switch(_pts, 'showLeaderboard', context.t('policy.pts.board'), hint: context.t('policy.pts.board_hint'), def: true),
        ]),
        _group(context.t('policy.pts.colours'), context.t('policy.pts.colours_hint'), [
          _seg(_pts, 'lateColor', context.t('policy.pts.late'), const ['none', 'red'], 'policy.colour', def: 'none'),
          _seg(_pts, 'halfDayColor', context.t('policy.pts.half'), const ['none', 'red'], 'policy.colour', def: 'red'),
          _seg(_pts, 'absentColor', context.t('policy.pts.absent'), const ['none', 'red', 'black'], 'policy.colour', def: 'black'),
          _seg(_pts, 'missedCheckoutColor', context.t('policy.pts.missed'), const ['none', 'red'], 'policy.colour', def: 'none'),
        ]),
        _group(context.t('policy.pts.kudos'), context.t('policy.pts.kudos_hint'), [
          _step(_pts, 'kudosGreenEvery', context.t('policy.pts.kudos_every'), max: 50, step: 1, def: 5),
        ]),
        _group(context.t('policy.pts.exchange'), context.t('policy.pts.exchange_hint'), [
          _step(_pts, 'redCost', context.t('policy.pts.red_cost'), min: 1, max: 30, step: 1, def: 2),
          _step(_pts, 'blackCost', context.t('policy.pts.black_cost'), min: 1, max: 60, step: 1, def: 5),
          _seg(_pts, 'cancelOrder', context.t('policy.pts.order'), const ['black_first', 'red_first'], 'policy.order', def: 'black_first'),
        ]),
        _group(context.t('policy.pts.levels'), context.t('policy.pts.levels_hint'), [
          _step(_pts, 'streakDays', context.t('policy.pts.streak'), min: 3, max: 365, step: 1, def: 30),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: TextFormField(
              key: ValueKey('levels-${(_pts['levels'] as List?)?.join(',')}'),
              initialValue: ((_pts['levels'] as List?)?.map((e) => e.toString()).toList() ?? const ['Rookie', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Legend']).join(', '),
              onChanged: (v) => _pts['levels'] = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
              decoration: InputDecoration(labelText: context.t('policy.pts.level_names'), helperText: context.t('policy.pts.level_names_hint'), helperMaxLines: 2, prefixIcon: const Icon(Icons.workspace_premium_rounded)),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _recalc, icon: const Icon(Icons.refresh_rounded), label: Text(context.t('policy.pts.recalc')))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/h/rewards'), icon: const Icon(Icons.leaderboard_rounded), label: Text(context.t('policy.pts.open_board')))),
          ]),
        ),
      ];

  // ------------------------------------------------------------------- payroll
  List<Widget> _payroll(BuildContext context) => [
        _group(context.t('policy.pay.general'), context.t('policy.pay.general_hint'), [
          _switch(_pay, 'useAttendance', context.t('policy.pay.use_att'), def: true),
          _seg(_pay, 'dayDivisor', context.t('policy.pay.divisor'), const ['working_days', '30'], 'policy.divisor', def: 'working_days'),
          _stepD(_pay, 'shiftHours', context.t('policy.pay.shift_hours'), min: 1, max: 16, step: 0.5, def: 8, suffix: ' h'),
        ]),
        _group(context.t('policy.pay.deductions'), null, [
          _switch(_pay, 'deductAbsent', context.t('policy.pay.absent'), def: true),
          _switch(_pay, 'deductUnpaidLeave', context.t('policy.pay.unpaid'), def: true),
          _stepD(_pay, 'halfDayFraction', context.t('policy.pay.half'), hint: context.t('policy.pay.half_hint'), min: 0, max: 1, step: 0.25, def: 0.5),
          _seg(_pay, 'lateDeduction', context.t('policy.pay.late'), const ['none', 'hourly'], 'policy.latepay', def: 'none'),
        ]),
        _group(context.t('policy.tax.insurance'), context.t('policy.tax.insurance_hint'), [
          _stepD(_pay, 'insurancePct', context.t('policy.tax.insurance_pct'), min: 0, max: 30, step: 0.5, def: 0, suffix: '%'),
          _money(_pay, 'insuranceCap', context.t('policy.tax.insurance_cap'), hint: context.t('policy.tax.insurance_cap_hint')),
        ]),
        _group(context.t('policy.tax.title'), context.t('policy.tax.hint'), [
          _seg(_pay, 'taxMode', context.t('policy.tax.mode'), const ['none', 'flat', 'brackets'], 'policy.taxmode', def: 'none'),
          if (_s(_pay, 'taxMode', 'none') != 'none') _money(_pay, 'taxMonthlyExemption', context.t('policy.tax.exemption'), hint: context.t('policy.tax.exemption_hint')),
          if (_s(_pay, 'taxMode', 'none') == 'flat') _stepD(_pay, 'taxFlatPct', context.t('policy.tax.flat'), min: 0, max: 50, step: 0.5, def: 0, suffix: '%'),
          if (_s(_pay, 'taxMode', 'none') == 'brackets') _brackets(_pay),
        ]),
        _group(context.t('policy.pay.additions'), null, [
          _switch(_pay, 'overtimeEnabled', context.t('policy.pay.overtime'), def: true),
          _stepD(_pay, 'overtimeMultiplier', context.t('policy.pay.multiplier'), min: 1, max: 4, step: 0.25, def: 1.5, suffix: '×'),
          _stepD(_pay, 'perfectAttendanceBonus', context.t('policy.pay.perfect'), hint: context.t('policy.pay.perfect_hint'), min: 0, max: 100000, step: 50, def: 0),
        ]),
      ];
}
