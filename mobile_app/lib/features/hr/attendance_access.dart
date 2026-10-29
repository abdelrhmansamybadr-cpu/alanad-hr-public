import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

final _attendanceRulesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/attendance-rules')));
final _attemptsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, int>((ref, id) async => asMapList(await ref.read(apiProvider).get('/employees/$id/attendance-attempts')));

/// HR: how this person records attendance (company rule / another place / no place check), block them, see who tried away from the workplace.
class AttendanceAccessCard extends ConsumerStatefulWidget {
  final Employee employee;
  const AttendanceAccessCard({super.key, required this.employee});

  @override
  ConsumerState<AttendanceAccessCard> createState() => _AttendanceAccessCardState();
}

class _AttendanceAccessCardState extends ConsumerState<AttendanceAccessCard> {
  late String _mode = widget.employee.attendanceMode;
  late int? _rule = widget.employee.attendanceRuleId;
  late bool _blocked = widget.employee.attendanceBlocked;
  late final _reason = TextEditingController(text: widget.employee.attendanceBlockReason ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/employees/${widget.employee.id}/attendance-access', {
        'attendanceMode': _mode,
        'attendanceRuleId': _mode == 'rule' ? _rule : null,
        'attendanceBlocked': _blocked,
        'attendanceBlockReason': _blocked ? _reason.text.trim() : '',
      });
      ref.invalidate(employeesProvider);
      ref.invalidate(employeeProvider(widget.employee.id));
      if (mounted) toast(context, context.t('common.saved'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(_attendanceRulesProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final attempts = ref.watch(_attemptsProvider(widget.employee.id)).valueOrNull ?? const <Map<String, dynamic>>[];
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          initialValue: _mode,
          decoration: InputDecoration(labelText: context.t('attx.mode'), prefixIcon: const Icon(Icons.fingerprint_rounded)),
          items: [
            DropdownMenuItem(value: 'company', child: Text(context.t('attx.company'), overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'rule', child: Text(context.t('attx.rule'), overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'free', child: Text(context.t('attx.free'), overflow: TextOverflow.ellipsis)),
          ],
          isExpanded: true,
          onChanged: (v) => setState(() => _mode = v ?? 'company'),
        ),
        if (_mode == 'rule') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: rules.any((r) => jInt(r, 'id') == _rule) ? _rule : null,
            decoration: InputDecoration(labelText: context.t('attx.which_rule'), prefixIcon: const Icon(Icons.place_outlined)),
            items: [for (final r in rules) DropdownMenuItem<int?>(value: jInt(r, 'id'), child: Text(jStr(r, 'name')))],
            onChanged: (v) => setState(() => _rule = v),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _blocked,
          onChanged: (v) => setState(() => _blocked = v),
          title: Text(context.t('attx.block'), style: TextStyle(color: context.colors.danger, fontWeight: FontWeight.w700)),
        ),
        if (_blocked) AppField(controller: _reason, label: context.t('attx.reason'), icon: Icons.report_gmailerrorred_rounded),
        const SizedBox(height: 12),
        LoadingButton(label: context.t('attx.save'), loading: _busy, onPressed: (_mode == 'rule' && _rule == null) ? null : _save),
        if (attempts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(context.t('attx.attempts'), style: TextStyle(color: context.colors.warning, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final a in attempts.take(5)) Text('• ${jStr(a, 'createdAt').length >= 16 ? jStr(a, 'createdAt').substring(0, 16) : jStr(a, 'createdAt')} — ${jStr(a, 'message')}', style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
        ],
      ]),
    );
  }
}
