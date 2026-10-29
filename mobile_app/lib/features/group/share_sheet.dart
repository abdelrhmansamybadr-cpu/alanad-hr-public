import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';

/// "Share with other companies" for one employee or department. HR of the owning company ticks the companies of the group
/// that may also see it (employee: basic details, read-only; department: its HR can put their own people in it).
Future<bool?> showShareSheet(BuildContext context, {required String kind, required int id, required String name}) =>
    showAppSheet<bool>(context, title: name, child: _ShareBody(kind: kind, id: id));

/// The small card shown on an employee / department page of a company that belongs to a group.
class ShareCard extends ConsumerWidget {
  final String kind; // employee | department
  final int id;
  final String name;
  final int count;
  final VoidCallback onChanged;
  const ShareCard({super.key, required this.kind, required this.id, required this.name, required this.count, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider).group == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          IconBadge(Icons.share_rounded, color: context.scheme.primary, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('share.title'), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(count > 0 ? context.t('share.count', {'n': count}) : context.t('share.not_shared'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
            ]),
          ),
          TextButton(
            onPressed: () async {
              final changed = await showShareSheet(context, kind: kind, id: id, name: name);
              if (changed == true) onChanged();
            },
            child: Text(context.t('share.manage')),
          ),
        ]),
      ),
    );
  }
}

class _ShareBody extends ConsumerStatefulWidget {
  final String kind;
  final int id;
  const _ShareBody({required this.kind, required this.id});

  @override
  ConsumerState<_ShareBody> createState() => _ShareBodyState();
}

class _ShareBodyState extends ConsumerState<_ShareBody> {
  List<Map<String, dynamic>> _companies = const [];
  final Set<int> _on = {};
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
      final data = asMap(await ref.read(apiProvider).get('/group/shares', query: {'kind': widget.kind, 'id': '${widget.id}'}));
      final list = asMapList(data['companies']);
      if (!mounted) return;
      setState(() {
        _companies = list;
        _on
          ..clear()
          ..addAll(list.where((c) => c['shared'] == true).map((c) => jInt(c, 'id')));
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).put('/group/shares', {'kind': widget.kind, 'id': widget.id, 'companyIds': _on.toList()});
      if (mounted) toast(context, context.t('common.saved'));
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
      Text(widget.kind == 'employee' ? context.t('share.hint_employee') : context.t('share.hint_department'), style: TextStyle(color: c.subtext, height: 1.4)),
      const SizedBox(height: 10),
      if (_companies.isEmpty)
        Padding(padding: const EdgeInsets.all(16), child: Text(context.t('share.none'), style: TextStyle(color: c.subtext)))
      else
        for (final co in _companies)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _on.contains(jInt(co, 'id')),
            title: Text(jStr(co, 'name'), style: const TextStyle(fontWeight: FontWeight.w700)),
            secondary: const Icon(Icons.business_rounded),
            onChanged: (v) => setState(() => v == true ? _on.add(jInt(co, 'id')) : _on.remove(jInt(co, 'id'))),
          ),
      const SizedBox(height: 14),
      if (_companies.isNotEmpty) LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
    ]);
  }
}
