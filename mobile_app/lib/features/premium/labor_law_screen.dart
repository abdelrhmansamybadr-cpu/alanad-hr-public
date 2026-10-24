import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import 'premium_common.dart';

final laborLawProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => asMap(await ref.read(apiProvider).get('/labor-law/summary')));

/// Local labour law: what the company's country law means for me (leave, probation, insurance, tax, end of service),
/// the Hijri date, and (company admin) which country's law pack the company follows.
class LaborLawScreen extends ConsumerWidget {
  const LaborLawScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(laborLawProvider);
    final isAdmin = ref.watch(sessionProvider).user?.isAdmin ?? false;
    final cur = ref.watch(sessionProvider).company?.currency ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('law.title')),
        actions: [if (isAdmin) IconButton(tooltip: context.t('law.settings'), icon: const Icon(Icons.tune_rounded), onPressed: () => _openSettings(context, ref, data.valueOrNull))],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(laborLawProvider);
          await ref.read(laborLawProvider.future).catchError((_) => <String, dynamic>{});
        },
        child: data.when(
          loading: () => const SkeletonList(),
          error: (e, _) => isFeatureOff(e) ? const FeatureOff() : ErrorState(e, onRetry: () => ref.invalidate(laborLawProvider)),
          data: (d) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), physics: const AlwaysScrollableScrollPhysics(), children: _body(context, ref, d, isAdmin, cur)),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, WidgetRef ref, Map<String, dynamic> d, bool isAdmin, String cur) {
    final hij = asMap(d['hijriToday']);
    final out = <Widget>[
      AppCard(
        gradient: brandGradient(context),
        child: Row(children: [
          const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.isAr ? jStr(hij, 'textAr') : jStr(hij, 'textEn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 2),
              Text(jStr(d, 'gregorianToday'), style: const TextStyle(color: Colors.white70)),
            ]),
          ),
          if (jStr(hij, 'source') == 'tabular') Tooltip(message: context.t('law.hijri_approx'), child: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 20)),
        ]),
      ),
    ];
    if (d['configured'] != true) {
      out.add(const SizedBox(height: 16));
      out.add(SizedBox(
        height: 320,
        child: EmptyState(
          icon: Icons.gavel_rounded,
          title: context.t('law.not_set'),
          subtitle: context.t(isAdmin ? 'law.not_set_admin' : 'law.not_set_user'),
          actionLabel: isAdmin ? context.t('law.choose_country') : null,
          onAction: isAdmin ? () => _openSettings(context, ref, d) : null,
        ),
      ));
      return out;
    }
    final pack = asMap(d['pack']);
    final rules = asMap(pack['rules']);
    final me = asMap(d['me']);
    out.add(SectionHeader('${context.t('law.country')}: ${pick(context, pack, 'name')}'));
    if (me.isNotEmpty) {
      out.add(AppCard(
        child: Column(children: [
          InfoRow(icon: Icons.beach_access_rounded, label: context.t('law.my_leave'), value: context.t('law.days_n', {'n': jInt(me, 'annualLeaveDays')})),
          InfoRow(icon: Icons.work_history_rounded, label: context.t('law.my_service'), value: context.t('law.years_n', {'n': jDouble(me, 'yearsOfService').toStringAsFixed(1)})),
          InfoRow(
              icon: Icons.fact_check_rounded,
              label: context.t('law.my_probation'),
              value: me['probationOver'] == true ? context.t('law.probation_done') : context.t('law.probation_until', {'d': jStr(me, 'probationEnds')})),
          const Divider(height: 20),
          InfoRow(icon: Icons.payments_rounded, label: context.t('law.salary'), value: money(jDouble(me, 'salary'), cur)),
          InfoRow(icon: Icons.shield_rounded, label: context.t('law.insurance'), value: '− ${money(jDouble(me, 'monthlyInsurance'), cur)}'),
          InfoRow(icon: Icons.account_balance_rounded, label: context.t('law.tax'), value: '− ${money(jDouble(me, 'monthlyTax'), cur)}'),
          InfoRow(icon: Icons.savings_rounded, label: context.t('law.net'), value: money(jDouble(me, 'netEstimate'), cur)),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.t('law.estimate_note'), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
        ]),
      ));
    }
    out.add(SectionHeader(context.t('law.rules')));
    out.add(AppCard(
      child: Column(children: [
        InfoRow(icon: Icons.schedule_rounded, label: context.t('law.hours'), value: context.t('law.hours_v', {'d': jInt(rules, 'dailyHours'), 'w': jInt(rules, 'weeklyHours')})),
        InfoRow(icon: Icons.more_time_rounded, label: context.t('law.overtime'), value: '× ${asMap(d['params'])['overtimeMultiplier']}'),
        InfoRow(icon: Icons.timelapse_rounded, label: context.t('law.probation_max'), value: context.t('law.months_n', {'n': jInt(rules, 'probationMonths')})),
        InfoRow(icon: Icons.logout_rounded, label: context.t('law.notice'), value: context.t('law.days_n', {'n': jInt(rules, 'noticeDays')})),
        InfoRow(icon: Icons.weekend_rounded, label: context.t('law.rest'), value: jStr(rules, 'weeklyRest')),
      ]),
    ));
    if (jStr(rules, 'eos') == 'sa' && me.isNotEmpty) out.addAll([SectionHeader(context.t('law.eos')), const _EosCard()]);
    out.add(const SizedBox(height: 10));
    out.add(Text(pick(context, pack, 'notes'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.5)));
    out.add(Text('${context.t('law.reviewed')}: ${jStr(pack, 'reviewed')}', style: TextStyle(color: context.colors.subtext, fontSize: 12)));
    return out;
  }

  void _openSettings(BuildContext context, WidgetRef ref, Map<String, dynamic>? d) {
    showAppSheet(context, title: context.t('law.settings'), child: _LawSettings(current: d ?? const {}));
  }
}

class _EosCard extends ConsumerStatefulWidget {
  const _EosCard();
  @override
  ConsumerState<_EosCard> createState() => _EosCardState();
}

class _EosCardState extends ConsumerState<_EosCard> {
  String _reason = 'termination';
  Map<String, dynamic>? _res;
  bool _busy = false;

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).get('/labor-law/eos', query: {'reason': _reason});
      if (mounted) setState(() => _res = asMap(r));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = ref.watch(sessionProvider).company?.currency ?? '';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.t('law.eos_hint'), style: TextStyle(color: context.colors.subtext, height: 1.45)),
        const SizedBox(height: 12),
        SegmentBar(labels: [context.t('law.eos_termination'), context.t('law.eos_resignation')], index: _reason == 'termination' ? 0 : 1, onChanged: (i) => setState(() { _reason = i == 0 ? 'termination' : 'resignation'; _res = null; })),
        const SizedBox(height: 12),
        LoadingButton(label: context.t('law.eos_calc'), loading: _busy, onPressed: _load, icon: Icons.calculate_rounded),
        if (_res != null && _res!['applicable'] == true) ...[
          const SizedBox(height: 14),
          Text(money(jDouble(_res!, 'amount'), cur), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: context.scheme.primary)),
          const SizedBox(height: 4),
          Text(context.t('law.eos_detail', {'y': jDouble(_res!, 'years').toStringAsFixed(1), 'full': money(jDouble(_res!, 'fullAward'), cur), 'share': (jDouble(_res!, 'share') * 100).round()}), style: TextStyle(color: context.colors.subtext, height: 1.4)),
          const SizedBox(height: 6),
          Text(pick(context, _res!, 'note'), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
        ],
      ]),
    );
  }
}

class _LawSettings extends ConsumerStatefulWidget {
  final Map<String, dynamic> current;
  const _LawSettings({required this.current});
  @override
  ConsumerState<_LawSettings> createState() => _LawSettingsState();
}

class _LawSettingsState extends ConsumerState<_LawSettings> {
  late String? _country = jStrN(widget.current, 'country');
  late final Map<String, dynamic> _p = asMap(widget.current['params']);
  late final _pct = TextEditingController(text: '${_p['insurancePct'] ?? ''}');
  late final _cap = TextEditingController(text: '${_p['insuranceCap'] ?? ''}');
  late final _ex = TextEditingController(text: '${_p['taxMonthlyExemption'] ?? ''}');
  late final _ot = TextEditingController(text: '${_p['overtimeMultiplier'] ?? ''}');
  late final _tax = TextEditingController(text: ((_p['taxBrackets'] as List?) ?? const []).join('\n'));
  bool _busy = false;
  List<Map<String, dynamic>> _packs = [];

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).get('/labor-law/packs').then((r) {
      if (mounted) setState(() => _packs = asMapList(r));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_pct, _cap, _ex, _ot, _tax]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fillFrom(String code) {
    final pack = _packs.where((p) => jStr(p, 'code') == code).firstOrNull;
    final params = asMap(pack?['params']);
    setState(() {
      _pct.text = '${params['insurancePct'] ?? ''}';
      _cap.text = '${params['insuranceCap'] ?? ''}';
      _ex.text = '${params['taxMonthlyExemption'] ?? ''}';
      _ot.text = '${params['overtimeMultiplier'] ?? ''}';
      _tax.text = ((params['taxBrackets'] as List?) ?? const []).join('\n');
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{'country': _country};
      if (_country != null) {
        body['params'] = {
          'insurance_pct': double.tryParse(_pct.text.trim()) ?? 0,
          'insurance_cap': double.tryParse(_cap.text.trim()) ?? 0,
          'tax_monthly_exemption': double.tryParse(_ex.text.trim()) ?? 0,
          'overtime_multiplier': double.tryParse(_ot.text.trim()) ?? 1,
          'tax_brackets': _tax.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        };
      }
      await ref.read(apiProvider).put('/labor-law/settings', body);
      ref.invalidate(laborLawProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, context.t('law.saved'));
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.t('law.settings_hint'), style: TextStyle(color: context.colors.subtext, height: 1.45)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ChoiceChip(label: Text(context.t('law.none')), selected: _country == null, onSelected: (_) => setState(() => _country = null)),
        for (final p in _packs)
          ChoiceChip(
            label: Text(pick(context, p, 'name')),
            selected: _country == jStr(p, 'code'),
            onSelected: (_) {
              setState(() => _country = jStr(p, 'code'));
              if (_country != jStrN(widget.current, 'country')) _fillFrom(jStr(p, 'code'));
            },
          ),
      ]),
      if (_country != null) ...[
        const SizedBox(height: 16),
        Text(context.t('law.figures'), style: context.text.titleSmall),
        const SizedBox(height: 4),
        Text(context.t('law.figures_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 10),
        AppField(controller: _pct, label: context.t('law.f_pct'), keyboard: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 10),
        AppField(controller: _cap, label: context.t('law.f_cap'), keyboard: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 10),
        AppField(controller: _ex, label: context.t('law.f_exempt'), keyboard: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 10),
        AppField(controller: _ot, label: context.t('law.f_ot'), keyboard: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 10),
        AppField(controller: _tax, label: context.t('law.f_brackets'), hint: '5000|10', maxLines: 5),
      ],
      const SizedBox(height: 18),
      LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
    ]);
  }
}
