import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

const contractTypes = ['permanent', 'fixed_term', 'probation', 'part_time', 'temporary', 'internship'];
const contractMonthChoices = [1, 3, 6, 12, 24, 36, 48, 60];

/// start + months − 1 day, month ends respected (31 Jan + 1 month = 28/29 Feb).
DateTime contractEndFor(DateTime start, int months) {
  final total = start.month - 1 + months;
  final y = start.year + total ~/ 12, m = total % 12 + 1;
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, start.day > last ? last : start.day).subtract(const Duration(days: 1));
}

int? contractDaysLeft(DateTime? end) {
  if (end == null) return null;
  final t = DateTime.now();
  return DateTime(end.year, end.month, end.day).difference(DateTime(t.year, t.month, t.day)).inDays;
}

/// The contract part of an employee, edited by the form.
class ContractData {
  String? type;
  DateTime? start;
  int? months;
  DateTime? end;
  ContractData({this.type, this.start, this.months, this.end});

  /// Sent with every save (null clears), so an edit can remove a contract.
  Map<String, dynamic> toBody() => {
        'contractType': type,
        'contractStart': start == null ? null : ymd(start!),
        'contractMonths': type == 'permanent' ? null : months,
        'contractEnd': (type == null || type == 'permanent' || end == null) ? null : ymd(end!),
      };
}

class ContractFields extends StatelessWidget {
  final ContractData data;
  final VoidCallback onChanged;
  const ContractFields({super.key, required this.data, required this.onChanged});

  Future<DateTime?> _pick(BuildContext c, DateTime? initial) => showDatePicker(context: c, initialDate: initial ?? DateTime.now(), firstDate: DateTime(1990), lastDate: DateTime(2100));

  @override
  Widget build(BuildContext context) {
    final open = data.type == 'permanent';
    Widget box(String label, IconData icon, DateTime? v, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: InputDecorator(decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)), child: Text(v == null ? '—' : fmtDate(context, v))),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String?>(
          initialValue: data.type,
          decoration: InputDecoration(labelText: context.t('ctr.type'), prefixIcon: const Icon(Icons.description_outlined)),
          items: [DropdownMenuItem<String?>(value: null, child: Text(context.t('ctr.not_set'))), for (final k in contractTypes) DropdownMenuItem<String?>(value: k, child: Text(context.t('ctr.t_$k'), overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            data.type = v;
            if (v == 'permanent') {
              data.end = null;
              data.months = null;
            } else if (v != null && data.start == null) {
              data.start = DateTime.now();
            }
            onChanged();
          },
        ),
        if (data.type != null) ...[
          const SizedBox(height: 12),
          box(context.t('ctr.starts'), Icons.event_available_rounded, data.start, () async {
            final d = await _pick(context, data.start);
            if (d == null) return;
            data.start = d;
            if (data.months != null && !open) data.end = contractEndFor(d, data.months!);
            onChanged();
          }),
        ],
        if (data.type != null && !open) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: contractMonthChoices.contains(data.months) ? data.months : null,
            decoration: InputDecoration(labelText: context.t('ctr.duration'), prefixIcon: const Icon(Icons.timelapse_rounded)),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(context.t('ctr.own_end'))),
              for (final m in contractMonthChoices) DropdownMenuItem<int?>(value: m, child: Text(m % 12 == 0 && m >= 12 ? context.t(m == 12 ? 'ctr.year' : 'ctr.years', {'n': '${m ~/ 12}'}) : context.t(m == 1 ? 'ctr.month' : 'ctr.months', {'n': '$m'}))),
            ],
            onChanged: (v) {
              data.months = v;
              if (v != null && data.start != null) data.end = contractEndFor(data.start!, v);
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          box(context.t('ctr.ends'), Icons.event_busy_rounded, data.end, () async {
            final d = await _pick(context, data.end ?? data.start);
            if (d == null) return;
            data.end = d;
            data.months = null;
            onChanged();
          }),
          if (data.end == null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.t('ctr.need_end'), style: TextStyle(fontSize: 12, color: context.colors.warning))),
        ],
      ]),
    );
  }
}

/// "Contract ends in 12 d" label, coloured by urgency.
class ContractChip extends StatelessWidget {
  final String? type;
  final DateTime? end;
  const ContractChip({super.key, this.type, this.end});

  @override
  Widget build(BuildContext context) {
    if (type == null) return const SizedBox.shrink();
    if (type == 'permanent' || end == null) return Text(type == 'permanent' ? context.t('ctr.permanent') : context.t('ctr.no_end'), style: TextStyle(fontSize: 11.5, color: context.colors.subtext));
    final d = contractDaysLeft(end)!;
    final color = d < 0 ? context.colors.danger : (d <= 30 ? context.colors.warning : context.colors.subtext);
    final text = d < 0 ? context.t('ctr.ended_ago', {'n': '${-d}'}) : (d == 0 ? context.t('ctr.ends_today') : context.t('ctr.ends_in', {'n': '$d'}));
    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

// =============================================================== contracts screen

final contractsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, days) async => asMap(await ref.read(apiProvider).get('/contracts/expiring', query: {'days': days})));
final contractSettingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => asMap(await ref.read(apiProvider).get('/contracts/settings')));

class ContractsScreen extends ConsumerStatefulWidget {
  const ContractsScreen({super.key});
  @override
  ConsumerState<ContractsScreen> createState() => _ContractsScreenState();
}

class _ContractsScreenState extends ConsumerState<ContractsScreen> {
  int _range = 90;
  Map<String, dynamic>? _s;
  bool _saving = false;

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).put('/contracts/settings', _s);
      ref.invalidate(contractsProvider);
      if (mounted) toast(context, context.t('ctr.settings_saved'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _renew(Map<String, dynamic> e) async {
    var months = 12;
    DateTime? end;
    var busy = false;
    final ok = await showAppSheet<bool>(
      context,
      title: context.t('ctr.renew_title', {'n': '${jStr(e, 'firstName')} ${jStr(e, 'lastName')}'}),
      child: StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${ctx.t('ctr.current_end')}: ${jStr(e, 'contractEnd').length >= 10 ? jStr(e, 'contractEnd').substring(0, 10) : '—'}', style: TextStyle(color: ctx.colors.subtext)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [for (final m in [3, 6, 12, 24, 36]) ChoiceChip(label: Text(ctx.t('ctr.months', {'n': '$m'})), selected: end == null && months == m, onSelected: (_) => set(() { months = m; end = null; }))]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_rounded),
            label: Text(end == null ? ctx.t('ctr.or_date') : fmtDate(ctx, end!)),
            onPressed: () async {
              final d = await showDatePicker(context: ctx, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime(2100));
              if (d != null) set(() => end = d);
            },
          ),
          const SizedBox(height: 18),
          LoadingButton(
            label: ctx.t('ctr.renew'),
            loading: busy,
            onPressed: () async {
              set(() => busy = true);
              try {
                await ref.read(apiProvider).post('/contracts/${jInt(e, 'id')}/renew', end != null ? {'endDate': ymd(end!)} : {'months': months});
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } on ApiException catch (x) {
                if (ctx.mounted) toast(ctx, x.message, error: true);
                set(() => busy = false);
              }
            },
          ),
        ]);
      }),
    );
    if (ok == true) {
      ref.invalidate(contractsProvider);
      ref.invalidate(employeesProvider);
      if (mounted) toast(context, context.t('ctr.renewed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(contractsProvider(_range));
    final settings = ref.watch(contractSettingsProvider);
    if (_s == null && settings.hasValue) _s = Map<String, dynamic>.from(settings.requireValue);
    final c = asMap(data.valueOrNull?['counts']);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('ctr.title'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(contractsProvider),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), physics: const AlwaysScrollableScrollPhysics(), children: [
          Row(children: [
            Expanded(child: _count(context.t('ctr.expired'), jInt(c, 'expired'), context.colors.danger)),
            const SizedBox(width: 10),
            Expanded(child: _count(context.t('ctr.soon'), jInt(c, 'soon'), context.colors.warning)),
            const SizedBox(width: 10),
            Expanded(child: _count(context.t('ctr.upcoming'), jInt(c, 'upcoming'), context.scheme.primary)),
          ]),
          SectionHeader(context.t('ctr.list_title'), action: '$_range ${context.t('cert.days')}', onAction: () => setState(() => _range = _range == 30 ? 90 : (_range == 90 ? 180 : (_range == 180 ? 365 : 30)))),
          AsyncBody<Map<String, dynamic>>(
            value: data,
            onRetry: () => ref.invalidate(contractsProvider),
            builder: (d) {
              final items = asMapList(d['items']);
              if (items.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text(context.t('ctr.none'), style: TextStyle(color: context.colors.subtext)));
              return Column(children: [
                for (final e in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${jStr(e, 'firstName')} ${jStr(e, 'lastName')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${jStr(e, 'position')}${jStrN(e, 'departmentName') == null ? '' : ' · ${jStr(e, 'departmentName')}'}', style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
                        ContractChip(type: jStrN(e, 'contractType'), end: DateTime.tryParse(jStr(e, 'contractEnd'))),
                        const SizedBox(height: 4),
                        Row(children: [
                          TextButton.icon(onPressed: () => _renew(e), icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(context.t('ctr.renew'))),
                          TextButton.icon(onPressed: () => context.push('/h/certificates?employee=${jInt(e, 'id')}'), icon: const Icon(Icons.workspace_premium_rounded, size: 18), label: Text(context.t('ctr.certificate'))),
                        ]),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
          SectionHeader(context.t('ctr.settings')),
          if (_s == null) const SkeletonList(count: 1) else _settingsCard(),
        ]),
      ),
    );
  }

  Widget _count(String label, int n, Color color) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$n', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)), Text(label, style: TextStyle(fontSize: 11.5, color: context.colors.subtext))]),
      );

  Widget _settingsCard() {
    final days = (_s!['remindDays'] as List? ?? const []).map((e) => (e as num).toInt()).toList();
    Widget sw(String key, String label) => SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, value: _s![key] == true, onChanged: (v) => setState(() => _s![key] = v), title: Text(label, style: const TextStyle(fontSize: 14)));
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.t('ctr.remind_days'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final d in [90, 60, 45, 30, 21, 14, 7, 3, 1, 0])
            FilterChip(
              label: Text(d == 0 ? context.t('ctr.on_day') : '$d'),
              selected: days.contains(d),
              onSelected: (on) => setState(() {
                final n = {...days};
                on ? n.add(d) : n.remove(d);
                _s!['remindDays'] = (n.toList()..sort((a, b) => b.compareTo(a)));
              }),
            ),
        ]),
        const SizedBox(height: 8),
        sw('notifyHr', context.t('ctr.n_hr')),
        sw('notifyManager', context.t('ctr.n_manager')),
        sw('notifyEmployee', context.t('ctr.n_employee')),
        sw('emailHr', context.t('ctr.n_email')),
        sw('remindExpired', context.t('ctr.n_expired')),
        const SizedBox(height: 8),
        LoadingButton(label: context.t('ctr.save_settings'), loading: _saving, onPressed: _saveSettings),
      ]),
    );
  }
}
