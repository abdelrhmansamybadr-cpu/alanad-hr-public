import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/ui/widgets.dart';

class ExplainReason {
  final String code;
  final String text; // English text from the server, used if a translation is missing
  final Map<String, dynamic> params;
  final String tone; // info | good | warn | bad
  const ExplainReason({required this.code, required this.text, this.params = const {}, this.tone = 'info'});
}

class DayExplain {
  final String date;
  final String status;
  final List<ExplainReason> reasons;
  final bool canDispute;
  final bool disputePending;
  const DayExplain({required this.date, required this.status, this.reasons = const [], this.canDispute = false, this.disputePending = false});

  factory DayExplain.fromJson(dynamic raw) {
    final m = asMap(raw);
    return DayExplain(
      date: jStr(m, 'date'),
      status: jStr(m, 'status'),
      canDispute: jBool(m, 'canDispute'),
      disputePending: jBool(m, 'disputePending'),
      reasons: [for (final r in asMapList(m['reasons'])) ExplainReason(code: jStr(r, 'code'), text: jStr(r, 'text'), params: asMap(r['params']), tone: jStr(r, 'tone', 'info'))],
    );
  }
}

/// Why one day has the status it has. [employeeId] 0 = me; HR passes an employee id.
final dayExplainProvider = FutureProvider.autoDispose.family<DayExplain, ({String date, int employeeId})>((ref, q) async {
  final data = await ref.read(apiProvider).get('/attendance/explain', query: {'date': q.date, if (q.employeeId > 0) 'employeeId': q.employeeId});
  return DayExplain.fromJson(data);
});

/// The reasons behind a day's result, each one in plain words with the exact numbers from the company rules.
class DayExplainView extends ConsumerWidget {
  final String date; // yyyy-MM-dd
  final int employeeId;
  final Widget? disputeButton;
  const DayExplainView({super.key, required this.date, this.employeeId = 0, this.disputeButton});

  String _text(BuildContext context, ExplainReason r) {
    final p = <String, dynamic>{for (final e in r.params.entries) e.key: e.value};
    if (r.code == 'result') p['status'] = _statusLabel(context, '${p['status']}');
    if (r.code == 'missed_checkout') p['action'] = context.t('why.action.${p['action']}');
    final key = 'why.${r.code}';
    final t = context.t(key, p);
    return t == key ? r.text : t;
  }

  String _statusLabel(BuildContext context, String s) {
    final k = 'status.$s';
    final t = context.t(k);
    return t == k ? s : t;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ex = ref.watch(dayExplainProvider((date: date, employeeId: employeeId)));
    return ex.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: Text(errorText(context, e))),
      data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in d.reasons) _ReasonTile(text: _text(context, r), tone: r.tone, last: r.code == 'result'),
        const SizedBox(height: 6),
        Text(context.t('why.auto_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.4)),
        const SizedBox(height: 12),
        if (d.disputePending) Pill(context.t('why.dispute_pending'), color: context.colors.info, icon: Icons.hourglass_top_rounded),
        if (d.canDispute && disputeButton != null) disputeButton!,
      ]),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final String text;
  final String tone;
  final bool last;
  const _ReasonTile({required this.text, required this.tone, required this.last});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (tone) {
      'good' => (Icons.check_circle_rounded, context.colors.success),
      'warn' => (Icons.warning_amber_rounded, context.colors.warning),
      'bad' => (Icons.cancel_rounded, context.colors.danger),
      _ => (Icons.info_outline_rounded, context.colors.subtext),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(height: 1.4, fontWeight: last ? FontWeight.w800 : FontWeight.w400))),
      ]),
    );
  }
}
