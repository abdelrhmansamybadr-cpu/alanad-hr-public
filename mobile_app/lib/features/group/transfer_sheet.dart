import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';

/// Move an employee or a department to another company of the group. Returns true when it was moved.
Future<bool?> showTransferSheet(BuildContext context, {required String kind, required int id, required String name}) =>
    showAppSheet<bool>(context, title: name, child: _TransferBody(kind: kind, id: id, name: name));

/// The "Move to another company" card on an employee / department page of a company that belongs to a group.
class TransferCard extends ConsumerWidget {
  final String kind; // employee | department
  final int id;
  final String name;
  final VoidCallback onMoved; // the item is gone from this company: the page should close
  const TransferCard({super.key, required this.kind, required this.id, required this.name, required this.onMoved});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider).group == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          IconBadge(Icons.swap_horiz_rounded, color: context.colors.warning, size: 40),
          const SizedBox(width: 12),
          Expanded(child: Text(context.t('transfer.title'), style: const TextStyle(fontWeight: FontWeight.w800))),
          TextButton(
            onPressed: () async {
              final moved = await showTransferSheet(context, kind: kind, id: id, name: name);
              if (moved == true) onMoved();
            },
            child: Text(context.t('transfer.button')),
          ),
        ]),
      ),
    );
  }
}

class _TransferBody extends ConsumerStatefulWidget {
  final String kind;
  final int id;
  final String name;
  const _TransferBody({required this.kind, required this.id, required this.name});

  @override
  ConsumerState<_TransferBody> createState() => _TransferBodyState();
}

class _TransferBodyState extends ConsumerState<_TransferBody> {
  List<Map<String, dynamic>> _targets = const [];
  List<Map<String, dynamic>> _depts = const [];
  int? _target;
  int? _dept;
  bool _people = true;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = asMapList(await ref.read(apiProvider).get('/group/transfer-targets', query: {'kind': widget.kind}));
      if (mounted) setState(() { _targets = list; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _pickTarget(int id) async {
    setState(() { _target = id; _dept = null; _depts = const []; });
    if (widget.kind != 'employee') return;
    try {
      final list = asMapList(await ref.read(apiProvider).get('/group/transfer-departments', query: {'company_id': '$id'}));
      if (mounted && _target == id) setState(() => _depts = list);
    } catch (_) {}
  }

  Future<void> _move() async {
    final target = _targets.firstWhere((t) => jInt(t, 'id') == _target);
    final ok = await confirmDialog(context, title: context.t('transfer.title'), message: context.t('transfer.confirm', {'name': widget.name, 'company': jStr(target, 'name')}), confirmLabel: context.t('transfer.button'), danger: true);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).post('/group/transfer', {
        'kind': widget.kind,
        'id': widget.id,
        'targetCompanyId': _target,
        if (widget.kind == 'employee' && _dept != null) 'departmentId': _dept,
        if (widget.kind == 'department') 'moveMembers': _people,
      });
      if (mounted) toast(context, context.t('transfer.done', {'company': jStr(target, 'name')}));
      nav.pop(true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    if (_error != null) return Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: TextStyle(color: c.danger)));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.kind == 'employee' ? context.t('transfer.hint_employee') : context.t('transfer.hint_department'), style: TextStyle(color: c.subtext, height: 1.4)),
      const SizedBox(height: 12),
      if (_targets.isEmpty)
        Padding(padding: const EdgeInsets.all(12), child: Text(context.t('transfer.none'), style: TextStyle(color: c.subtext, height: 1.4)))
      else ...[
        Text(context.t('transfer.pick'), style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final t in _targets)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_target == jInt(t, 'id') ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _target == jInt(t, 'id') ? context.scheme.primary : c.subtext),
            title: Text(jStr(t, 'name'), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => _pickTarget(jInt(t, 'id')),
          ),
        if (widget.kind == 'employee' && _target != null && _depts.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            key: ValueKey(_target),
            initialValue: _dept,
            decoration: InputDecoration(labelText: context.t('transfer.dept')),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(context.t('transfer.no_dept'))),
              for (final d in _depts) DropdownMenuItem<int?>(value: jInt(d, 'id'), child: Text(jStr(d, 'name'))),
            ],
            onChanged: (v) => setState(() => _dept = v),
          ),
        ],
        if (widget.kind == 'department')
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('transfer.move_people')), subtitle: Text(context.t('transfer.move_people_hint'), style: const TextStyle(fontSize: 12)), value: _people, onChanged: (v) => setState(() => _people = v)),
        const SizedBox(height: 14),
        LoadingButton(label: context.t('transfer.button'), loading: _busy, onPressed: _target == null ? null : _move),
      ],
    ]);
  }
}
