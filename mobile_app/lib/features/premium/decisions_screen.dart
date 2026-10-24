import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import 'premium_common.dart';

final decisionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/decisions')));

IconData _kindIcon(String k) => switch (k) {
      'leave' => Icons.beach_access_rounded,
      'request' => Icons.assignment_rounded,
      'point' => Icons.flag_rounded,
      _ => Icons.receipt_long_rounded,
    };

/// Fair decisions: every adverse decision (rejected leave or request, lost point, payslip deduction) with its reason.
/// The affected person can dispute it; their manager or HR answers on the record.
class DecisionsScreen extends ConsumerStatefulWidget {
  const DecisionsScreen({super.key});
  @override
  ConsumerState<DecisionsScreen> createState() => _DecisionsScreenState();
}

class _DecisionsScreenState extends ConsumerState<DecisionsScreen> {
  int _filter = 0; // 0 all, 1 open disputes, 2 answered, 3 no reason

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(decisionsProvider);
    final me = ref.watch(sessionProvider).user;
    final isHr = me != null && me.role != 'employee';
    return Scaffold(
      appBar: AppBar(title: Text(context.t('dec.title'))),
      body: Column(children: [
        const SizedBox(height: 4),
        FilterChips(labels: [context.t('dec.f_all'), context.t('dec.f_open'), context.t('dec.f_answered'), if (isHr) context.t('dec.f_noreason')], index: _filter, onChanged: (i) => setState(() => _filter = i)),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(decisionsProvider);
              await ref.read(decisionsProvider.future).catchError((_) => <Map<String, dynamic>>[]);
            },
            child: data.when(
              loading: () => const SkeletonList(),
              error: (e, _) => isFeatureOff(e) ? const FeatureOff() : ErrorState(e, onRetry: () => ref.invalidate(decisionsProvider)),
              data: (all) {
                final items = all.where((d) {
                  final disp = asMap(d['dispute']);
                  switch (_filter) {
                    case 1:
                      return disp['status'] == 'open';
                    case 2:
                      return disp.isNotEmpty && disp['status'] != 'open';
                    case 3:
                      return d['hasReason'] != true;
                    default:
                      return true;
                  }
                }).toList();
                if (items.isEmpty) {
                  return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: 380, child: EmptyState(icon: Icons.balance_rounded, title: context.t('dec.empty'), subtitle: context.t('dec.empty_hint')))]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _DecisionTile(items[i]),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _DecisionTile extends ConsumerWidget {
  final Map<String, dynamic> d;
  const _DecisionTile(this.d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disp = asMap(d['dispute']);
    final mine = d['employeeId'] == ref.watch(sessionProvider).user?.employeeId;
    final reason = _reasonText(context, d);
    final status = jStr(disp, 'status');
    final color = status == 'open' ? context.colors.warning : (status == 'reversed' ? context.colors.success : (status == 'upheld' ? context.colors.subtext : context.colors.danger));
    return RowTile(
      leading: IconBadge(_kindIcon(jStr(d, 'kind')), color: color, size: 42),
      title: jStr(d, 'title'),
      subtitle: [if (!mine) jStr(d, 'employeeName'), reason ?? context.t('dec.no_reason')].where((e) => e.isNotEmpty).join(' · '),
      trailing: disp.isEmpty ? (d['hasReason'] == true ? null : Pill(context.t('dec.no_reason_short'), color: context.colors.danger)) : Pill(context.t('dec.s_$status'), color: color),
      onTap: () => showAppSheet(context, title: context.t('dec.details'), child: _DecisionSheet(d: d, mine: mine)),
    );
  }
}

/// Reason line: a written note, or the stable reason code translated (why.late ...).
String? _reasonText(BuildContext context, Map<String, dynamic> d) {
  final note = jStrN(d, 'reasonText');
  final code = jStrN(d, 'reasonCode');
  final coded = code == null ? null : context.t(code);
  final codedText = (coded == null || coded == code) ? null : coded;
  if (codedText != null && note != null) return '$codedText — $note';
  return codedText ?? note;
}

class _DecisionSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> d;
  final bool mine;
  const _DecisionSheet({required this.d, required this.mine});
  @override
  ConsumerState<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends ConsumerState<_DecisionSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String _answer = 'upheld';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String path, Map<String, dynamic> body, {bool put = false}) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      final r = put ? await api.put(path, body) : await api.post(path, body);
      ref.invalidate(decisionsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      final effect = jStrN(asMap(r), 'effect');
      toast(context, effect ?? context.t('dec.sent'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final disp = asMap(d['dispute']);
    final kind = jStr(d, 'kind');
    final base = '/decisions/$kind/${jInt(d, 'refId')}';
    final me = ref.watch(sessionProvider).user;
    final canAnswer = !widget.mine && me != null;
    final reason = _reasonText(context, d);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(jStr(d, 'title'), style: context.text.titleMedium),
      if (jStr(d, 'employeeName').isNotEmpty && !widget.mine) Padding(padding: const EdgeInsets.only(top: 2), child: Text(jStr(d, 'employeeName'), style: TextStyle(color: context.colors.subtext))),
      const SizedBox(height: 14),
      AppCard(
        color: reason == null ? context.colors.danger.withValues(alpha: 0.08) : context.colors.surfaceAlt,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('dec.reason'), style: TextStyle(color: context.colors.subtext, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(reason ?? context.t('dec.no_reason'), style: TextStyle(height: 1.45, color: reason == null ? context.colors.danger : null)),
          const SizedBox(height: 8),
          Text(
            [
              if (d['auto'] == true) context.t('dec.auto') else if (jStrN(d, 'decidedBy') != null) '${context.t('dec.by')} ${jStr(d, 'decidedBy')}',
              jStr(d, 'decidedAt').split(' ').first,
            ].join(' · '),
            style: TextStyle(color: context.colors.subtext, fontSize: 12),
          ),
        ]),
      ),
      if (disp.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(context.t('dec.dispute'), style: context.text.titleSmall),
        const SizedBox(height: 6),
        AppCard(child: Text(jStr(disp, 'message'), style: const TextStyle(height: 1.45))),
        if (disp['status'] != 'open') ...[
          const SizedBox(height: 10),
          AppCard(
            color: (disp['status'] == 'reversed' ? context.colors.success : context.colors.subtext).withValues(alpha: 0.10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Pill(context.t('dec.s_${jStr(disp, 'status')}'), color: disp['status'] == 'reversed' ? context.colors.success : context.colors.subtext),
              const SizedBox(height: 8),
              Text(jStr(disp, 'response'), style: const TextStyle(height: 1.45)),
            ]),
          ),
        ],
      ],
      if (disp.isEmpty && widget.mine) ...[
        const SizedBox(height: 16),
        AppField(controller: _text, label: context.t('dec.why_disagree'), maxLines: 4, maxLength: 2000),
        const SizedBox(height: 12),
        LoadingButton(label: context.t('dec.send_dispute'), loading: _busy, icon: Icons.record_voice_over_rounded, onPressed: () => _send('$base/dispute', {'message': _text.text.trim()})),
      ],
      if (disp['status'] == 'open' && canAnswer) ...[
        const SizedBox(height: 16),
        SegmentBar(labels: [context.t('dec.uphold'), context.t('dec.reverse')], index: _answer == 'upheld' ? 0 : 1, onChanged: (i) => setState(() => _answer = i == 0 ? 'upheld' : 'reversed')),
        const SizedBox(height: 6),
        Text(context.t(_answer == 'upheld' ? 'dec.uphold_hint' : 'dec.reverse_hint_$kind'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 10),
        AppField(controller: _text, label: context.t('dec.your_answer'), maxLines: 3, maxLength: 2000),
        const SizedBox(height: 12),
        LoadingButton(label: context.t('dec.send_answer'), loading: _busy, onPressed: () => _send('$base/respond', {'status': _answer, 'response': _text.text.trim()}, put: true)),
      ],
    ]);
  }
}
