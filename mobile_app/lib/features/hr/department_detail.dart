import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/ui/format.dart';
import '../../core/ui/suggest_field.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';
import '../group/share_sheet.dart';
import '../group/transfer_sheet.dart';

/// One department: its head, its members, and ways to add people.
class DepartmentDetailScreen extends ConsumerWidget {
  final int id;
  const DepartmentDetailScreen({super.key, required this.id});

  void _refresh(WidgetRef ref) {
    ref.invalidate(departmentProvider(id));
    ref.invalidate(departmentsProvider);
    ref.invalidate(employeesProvider);
    ref.invalidate(orgProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dept = ref.watch(departmentProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: Text(dept.valueOrNull?.name ?? context.t('org.departments')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: dept.valueOrNull == null || dept.valueOrNull!.shared
                ? null
                : () async {
                    await showDepartmentForm(context, existing: dept.valueOrNull);
                    _refresh(ref);
                  },
          ),
        ],
      ),
      body: AsyncBody<Department>(
        value: dept,
        onRetry: () => _refresh(ref),
        builder: (d) => RefreshIndicator(
          onRefresh: () async {
            _refresh(ref);
            await ref.read(departmentProvider(id).future).catchError((_) => d);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), physics: const AlwaysScrollableScrollPhysics(), children: [
            AppCard(
              shadow: true,
              child: Row(children: [
                IconBadge(Icons.account_tree_rounded, color: colorFor(d.name), size: 54),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    if ((d.description ?? '').isNotEmpty) Text(d.description!, style: TextStyle(color: context.colors.subtext, height: 1.35)),
                    const SizedBox(height: 6),
                    Pill(context.t('org.people_count', {'n': d.members.length})),
                  ]),
                ),
              ]),
            ),

            if (d.shared)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: context.colors.info.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Text(context.t('share.shared_banner', {'name': d.sharedFrom ?? ''}), style: TextStyle(color: context.colors.info, fontWeight: FontWeight.w600, height: 1.4)),
                ),
              )
            else
              Column(children: [
                ShareCard(kind: 'department', id: id, name: d.name, count: d.sharedCount, onChanged: () => _refresh(ref)),
                TransferCard(kind: 'department', id: id, name: d.name, onMoved: () {
                  _refresh(ref);
                  context.pop();
                }),
              ]),

            // ---- head
            SectionHeader(context.t('org.head')),
            AppCard(
              child: d.headId == null
                  ? Row(children: [
                      IconBadge(Icons.star_outline_rounded, color: context.colors.warning),
                      const SizedBox(width: 14),
                      Expanded(child: Text(context.t('org.no_head'), style: TextStyle(color: context.colors.subtext))),
                      if (!d.shared) TextButton(onPressed: () => _pickHead(context, ref, d), child: Text(context.t('org.set_head'))),
                    ])
                  : Row(children: [
                      Avatar(name: d.headName ?? '', url: d.headAvatar, size: 50, ring: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.headName ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          if ((d.headPosition ?? '').isNotEmpty) Text(d.headPosition!, style: TextStyle(color: context.colors.subtext, fontSize: 13)),
                        ]),
                      ),
                      if (!d.shared) TextButton(onPressed: () => _pickHead(context, ref, d), child: Text(context.t('org.change_head'))),
                    ]),
            ),
            if (!d.shared) Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text(context.t('org.head_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.4))),

            // ---- members
            SectionHeader(context.t('org.members')),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => _addExisting(context, ref, d), icon: const Icon(Icons.group_add_rounded), label: Text(context.t('org.add_existing')))),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await context.push('/h/employee/new?dept=$id');
                    _refresh(ref);
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(context.t('org.new_member')),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (d.members.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 20), child: EmptyState(icon: Icons.groups_outlined, title: context.t('org.no_members'), subtitle: context.t('org.no_members_hint')))
            else
              for (final m in d.members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RowTile(
                    leading: Avatar(name: m.fullName, url: m.avatar, size: 46, ring: m.id == d.headId),
                    title: m.fullName,
                    subtitle: m.shared ? [m.position, if (m.companyName != null) m.companyName!].where((s) => s.isNotEmpty).join(' · ') : m.position,
                    trailing: m.shared
                        ? Pill(context.t('share.from', {'name': m.companyName ?? ''}), color: context.colors.info, icon: Icons.share_rounded)
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            if (m.id == d.headId) Pill(context.t('org.head'), color: context.colors.warning, icon: Icons.star_rounded),
                            PopupMenuButton<String>(
                              onSelected: (v) => v == 'head' ? _setHead(context, ref, d, m.id) : _remove(context, ref, d, m),
                              itemBuilder: (_) => [
                                if (m.id != d.headId && !d.shared) PopupMenuItem(value: 'head', child: Text(context.t('org.make_head'))),
                                PopupMenuItem(value: 'remove', child: Text(context.t('org.remove_member'), style: TextStyle(color: context.colors.danger))),
                              ],
                            ),
                          ]),
                    onTap: m.shared ? null : () => context.push('/h/employee/${m.id}'),
                  ),
                ),
          ]),
        ),
      ),
    );
  }

  Future<void> _setHead(BuildContext context, WidgetRef ref, Department d, int? employeeId) async {
    try {
      await ref.read(apiProvider).put('/departments/${d.id}', {'headId': employeeId});
      _refresh(ref);
      if (context.mounted) toast(context, context.t('common.saved'));
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, Department d, Employee m) async {
    if (!await confirmDialog(context, title: context.t('org.remove_member'), message: context.t('org.remove_member_hint', {'name': m.fullName}), danger: true, confirmLabel: context.t('org.remove_member'))) return;
    try {
      await ref.read(apiProvider).delete('/departments/${d.id}/members/${m.id}');
      _refresh(ref);
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _pickHead(BuildContext context, WidgetRef ref, Department d) async {
    final picked = await showAppSheet<int>(context, title: context.t('org.choose_head'), child: _EmployeePicker(preferred: d.members.map((m) => m.id).toSet(), single: true));
    if (picked != null && context.mounted) await _setHead(context, ref, d, picked);
  }

  Future<void> _addExisting(BuildContext context, WidgetRef ref, Department d) async {
    final ids = await showAppSheet<List<int>>(context, title: context.t('org.add_existing'), child: _EmployeePicker(exclude: d.members.map((m) => m.id).toSet()));
    if (ids == null || ids.isEmpty) return;
    try {
      await ref.read(apiProvider).post('/departments/${d.id}/members', {'employeeIds': ids});
      _refresh(ref);
      if (context.mounted) toast(context, context.t('common.saved'));
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }
}

/// Search + pick one or several employees.
class _EmployeePicker extends ConsumerStatefulWidget {
  final Set<int> exclude;
  final Set<int> preferred;
  final bool single;
  const _EmployeePicker({this.exclude = const {}, this.preferred = const {}, this.single = false});

  @override
  ConsumerState<_EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends ConsumerState<_EmployeePicker> {
  final _selected = <int>{};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    // choosing a head: own people and people shared by other companies; adding members: own people only
    final all = widget.single ? ref.watch(peopleListProvider('')) : ref.watch(employeesProvider(''));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.62,
      child: Column(children: [
        TextField(onChanged: (v) => setState(() => _q = v.trim().toLowerCase()), decoration: InputDecoration(hintText: context.t('dir.search'), prefixIcon: const Icon(Icons.search_rounded))),
        const SizedBox(height: 10),
        Expanded(
          child: all.when(
            loading: () => const SkeletonList(count: 5),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(employeesProvider)),
            data: (list) {
              var items = list.where((e) => e.status != 'inactive' && !widget.exclude.contains(e.id)).toList();
              if (_q.isNotEmpty) items = items.where((e) => e.fullName.toLowerCase().contains(_q) || e.position.toLowerCase().contains(_q)).toList();
              items.sort((a, b) => (widget.preferred.contains(b.id) ? 1 : 0).compareTo(widget.preferred.contains(a.id) ? 1 : 0));
              if (items.isEmpty) return Center(child: Text(context.t('common.no_results'), style: TextStyle(color: context.colors.subtext)));
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final e = items[i];
                  final on = _selected.contains(e.id);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Avatar(name: e.fullName, url: e.avatar, size: 42),
                    title: Text(e.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([e.position, if (e.departmentName != null) e.departmentName!, if (e.sharedFrom != null) e.sharedFrom!].where((s) => s.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: widget.single ? null : Checkbox(value: on, onChanged: (_) => setState(() => on ? _selected.remove(e.id) : _selected.add(e.id))),
                    onTap: () {
                      if (widget.single) {
                        Navigator.pop(context, e.id);
                      } else {
                        setState(() => on ? _selected.remove(e.id) : _selected.add(e.id));
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
        if (!widget.single) ...[
          const SizedBox(height: 8),
          LoadingButton(label: context.t('org.add_n', {'n': _selected.length}), onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList())),
        ],
      ]),
    );
  }
}

// ================================================================ create / edit form

Future<void> showDepartmentForm(BuildContext context, {Department? existing}) =>
    showAppSheet(context, title: existing == null ? context.t('org.add_department') : context.t('common.edit'), child: _DepartmentForm(existing: existing));

class _DepartmentForm extends ConsumerStatefulWidget {
  final Department? existing;
  const _DepartmentForm({this.existing});

  @override
  ConsumerState<_DepartmentForm> createState() => _DepartmentFormState();
}

class _DepartmentFormState extends ConsumerState<_DepartmentForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late int? _head = widget.existing?.headId;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final body = {'name': _name.text.trim(), 'description': _desc.text.trim(), 'headId': _head};
      final api = ref.read(apiProvider);
      widget.existing == null ? await api.post('/departments', body) : await api.put('/departments/${widget.existing!.id}', body);
      ref.invalidate(departmentsProvider);
      ref.invalidate(employeesProvider);
      ref.invalidate(orgProvider);
      if (mounted) toast(context, context.t('common.saved'));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = (ref.watch(peopleListProvider('')).valueOrNull ?? const <Employee>[]).where((e) => e.status != 'inactive').toList();
    return Form(
      key: _form,
      child: Column(children: [
        departmentSuggestField(context, _name, label: context.t('common.name'), validator: (v) => requiredValidator(context, v)),
        const SizedBox(height: 14),
        AppField(controller: _desc, label: '${context.t('org.description')} (${context.t('common.optional')})', icon: Icons.notes_rounded, maxLines: 2),
        const SizedBox(height: 14),
        DropdownButtonFormField<int?>(
          initialValue: people.any((e) => e.id == _head) ? _head : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.t('org.head'), prefixIcon: const Icon(Icons.star_outline_rounded)),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(context.t('org.no_head'))),
            for (final e in people) DropdownMenuItem<int?>(value: e.id, child: Text(e.fullName, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _head = v),
        ),
        const SizedBox(height: 20),
        LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
        if (widget.existing != null)
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              if (!await confirmDialog(context, title: context.t('common.delete'), message: context.t('org.delete_department_hint'), danger: true, confirmLabel: context.t('common.delete'))) return;
              try {
                await ref.read(apiProvider).delete('/departments/${widget.existing!.id}');
                ref.invalidate(departmentsProvider);
                ref.invalidate(employeesProvider);
                nav.pop();
              } on ApiException catch (e) {
                if (context.mounted) toast(context, e.message, error: true);
              }
            },
            child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
          ),
      ]),
    );
  }
}
