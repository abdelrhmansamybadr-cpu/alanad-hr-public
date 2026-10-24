import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

const _modules = ['employees', 'departments', 'leaves', 'attendance', 'shifts', 'payroll', 'recruitment', 'talent_pool', 'reviews', 'announcements', 'documents', 'requests'];

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(staffProvider);
    final me = ref.watch(sessionProvider).user!;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('staff.title'))),
      floatingActionButton: me.isAdmin ? FloatingActionButton.extended(onPressed: () => showAppSheet(context, title: context.t('staff.add'), child: const _StaffForm()), icon: const Icon(Icons.add_rounded), label: Text(context.t('staff.add'))) : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(staffProvider);
          await ref.read(staffProvider.future).catchError((_) => <StaffMember>[]);
        },
        child: AsyncBody<List<StaffMember>>(
          value: list,
          onRetry: () => ref.invalidate(staffProvider),
          builder: (items) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(context.t('staff.hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)));
              final s = items[i - 1];
              return RowTile(
                leading: Avatar(name: s.name, size: 46),
                title: s.name,
                subtitle: s.email,
                trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Pill(s.role == 'hr_admin' ? context.t('me.role_admin') : context.t('staff.manager'), color: s.role == 'hr_admin' ? context.scheme.primary : context.colors.info),
                  if (s.status != 'active') Padding(padding: const EdgeInsets.only(top: 6), child: StatusChip(s.status)),
                ]),
                onTap: me.isAdmin ? () => showAppSheet(context, title: s.name, child: _StaffForm(existing: s, isSelf: s.id == me.id)) : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StaffForm extends ConsumerStatefulWidget {
  final StaffMember? existing;
  final bool isSelf;
  const _StaffForm({this.existing, this.isSelf = false});

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _email = TextEditingController(text: widget.existing?.email);
  final _password = TextEditingController();
  late String _role = widget.existing?.role ?? 'hr_manager';
  late String _status = widget.existing?.status ?? 'active';
  late final Map<String, bool> _perms = {for (final m in _modules) m: widget.existing?.permissions[m] ?? true};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final permissions = [for (final e in _perms.entries) {'module': e.key, 'enabled': e.value}];
      final api = ref.read(apiProvider);
      if (widget.existing == null) {
        await api.post('/hr-staff', {'name': _name.text.trim(), 'email': _email.text.trim().toLowerCase(), 'password': _password.text, 'role': _role, 'permissions': permissions});
      } else {
        await api.put('/hr-staff/${widget.existing!.id}', {
          'name': _name.text.trim(),
          if (!widget.isSelf) 'role': _role,
          if (!widget.isSelf) 'status': _status,
          if (_password.text.isNotEmpty) 'password': _password.text,
          'permissions': permissions,
        });
      }
      ref.invalidate(staffProvider);
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
    final editing = widget.existing != null;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppField(controller: _name, label: context.t('common.name'), icon: Icons.person_outline_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
        const SizedBox(height: 14),
        AppField(controller: _email, label: context.t('common.email'), icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress, enabled: !editing, validator: (v) => emailValidator(context, v)),
        const SizedBox(height: 14),
        AppField(controller: _password, label: editing ? context.t('staff.new_password') : context.t('auth.password.label'), icon: Icons.lock_outline_rounded, obscure: true, validator: (v) => editing && (v ?? '').isEmpty ? null : passwordValidator(context, v)),
        if (!widget.isSelf) ...[
          const SizedBox(height: 16),
          SegmentBar(labels: [context.t('staff.manager'), context.t('me.role_admin')], index: _role == 'hr_admin' ? 1 : 0, onChanged: (i) => setState(() => _role = i == 1 ? 'hr_admin' : 'hr_manager')),
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_role == 'hr_admin' ? context.t('staff.admin_hint') : context.t('staff.manager_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
        ],
        if (_role == 'hr_manager') ...[
          const SizedBox(height: 14),
          Text(context.t('staff.access'), style: context.text.titleSmall),
          const SizedBox(height: 4),
          for (final m in _modules)
            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(context.t('module.$m')), value: _perms[m] ?? true, onChanged: (v) => setState(() => _perms[m] = v)),
        ],
        if (editing && !widget.isSelf) ...[
          const SizedBox(height: 6),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('staff.account_active')), value: _status == 'active', onChanged: (v) => setState(() => _status = v ? 'active' : 'disabled')),
        ],
        const SizedBox(height: 16),
        LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
        if (editing && !widget.isSelf)
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              if (!await confirmDialog(context, title: context.t('common.delete'), message: context.t('staff.delete_hint'), danger: true, confirmLabel: context.t('common.delete'))) return;
              try {
                await ref.read(apiProvider).delete('/hr-staff/${widget.existing!.id}');
                ref.invalidate(staffProvider);
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
