import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import 'group_models.dart';

// ============================================================ switching companies

String _accessLabel(BuildContext context, GroupCompany c) {
  switch (c.level) {
    case 'home':
      return context.t('group.home_badge');
    case 'super':
      return context.t('group.super');
    case 'full':
      return c.readOnly ? context.t('group.access_ro') : context.t('group.access_full');
    default:
      return c.readOnly ? context.t('group.access_ro') : context.t('group.access_custom');
  }
}

/// Switch to [c]. Navigates to a neutral screen first so every screen of the old company is closed and its data dropped,
/// then asks the server (which checks the right to enter) and lands on the home of the new company.
void startSwitch(BuildContext context, WidgetRef ref, GroupCompany c, {bool popSheet = false}) {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(sessionProvider.notifier);
  final current = ref.read(sessionProvider).company?.id;
  if (popSheet) Navigator.of(context).pop();
  if (current == c.id) return;
  _runSwitch(router, messenger, notifier, c);
}

Future<void> _runSwitch(GoRouter router, ScaffoldMessengerState messenger, SessionNotifier notifier, GroupCompany c) async {
  router.go('/switching', extra: c.name);
  await Future.delayed(const Duration(milliseconds: 250));
  try {
    await notifier.switchCompany(c.id);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
  router.go('/');
}

/// The company switcher (bottom sheet).
void showCompanySwitcher(BuildContext context, WidgetRef ref) {
  if (ref.read(sessionProvider).group == null) return;
  showAppSheet(context, title: context.t('group.switch_company'), child: const _SwitcherList());
}

class _SwitcherList extends ConsumerWidget {
  const _SwitcherList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final group = session.group!;
    final activeId = session.company!.id;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.t('group.switch_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)),
      const SizedBox(height: 12),
      for (final c in group.companies) ...[
        RowTile(
          leading: IconBadge(Icons.business_rounded, color: c.id == activeId ? context.scheme.primary : context.colors.info, size: 40),
          title: c.name,
          subtitle: c.ceoName == null ? null : '${context.t('group.ceo')}: ${c.ceoName}',
          trailing: c.id == activeId ? Pill(context.t('group.current'), color: context.scheme.primary, icon: Icons.check_rounded) : Pill(_accessLabel(context, c), color: context.colors.subtext),
          onTap: c.active ? () => startSwitch(context, ref, c, popSheet: true) : null,
        ),
        const SizedBox(height: 10),
      ],
      if (group.isSuperAdmin || group.isOwner)
        TextButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            context.push('/h/group');
          },
          icon: const Icon(Icons.settings_suggest_rounded),
          label: Text(context.t('group.manage')),
        ),
    ]);
  }
}

/// Shown for a moment while the company changes.
class SwitchingScreen extends StatelessWidget {
  final String? name;
  const SwitchingScreen({super.key, this.name});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: brandGradient(context)),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white)),
              const SizedBox(height: 18),
              Text(context.t('group.switching', {'name': name ?? ''}), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

// ===================================================================== companies

class GroupCompaniesScreen extends ConsumerWidget {
  const GroupCompaniesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(groupCompaniesProvider);
    final activeId = ref.watch(sessionProvider).company?.id;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('group.companies'))),
      // Only the owner opens new companies
      floatingActionButton: data.valueOrNull?.isOwner == true
          ? FloatingActionButton.extended(
              onPressed: () => showAppSheet(context, title: context.t('group.add_company'), child: const _CompanyForm()),
              icon: const Icon(Icons.add_business_rounded),
              label: Text(context.t('group.add_company')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(groupCompaniesProvider);
          await ref.read(groupCompaniesProvider.future).catchError((_) => const GroupInfo(id: 0, name: '', isSuperAdmin: false, homeCompanyId: 0, activeCompanyId: 0, companies: []));
        },
        child: AsyncBody<GroupInfo>(
          value: data,
          onRetry: () => ref.invalidate(groupCompaniesProvider),
          builder: (g) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: g.companies.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(context.t('group.companies_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)));
              final c = g.companies[i - 1];
              return RowTile(
                leading: IconBadge(Icons.business_rounded, color: c.active ? context.scheme.primary : context.colors.danger, size: 42),
                title: c.name,
                subtitle: c.managerNames.isNotEmpty ? '${context.t('group.hr_managers')}: ${c.managerNames.join('، ')}' : (c.ceoName == null ? context.t('group.no_hr') : '${context.t('group.ceo')}: ${c.ceoName}'),
                trailing: c.id == activeId
                    ? Pill(context.t('group.current'), color: context.scheme.primary)
                    : (c.active ? (c.isHome ? Pill(context.t('group.home_badge'), color: context.colors.subtext) : null) : StatusChip(c.status)),
                bottom: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    Icon(Icons.groups_rounded, size: 16, color: context.colors.subtext),
                    const SizedBox(width: 4),
                    Text(context.t('group.employees_n', {'n': c.employeeCount}), style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
                    const SizedBox(width: 14),
                    Icon(Icons.account_tree_rounded, size: 16, color: context.colors.subtext),
                    const SizedBox(width: 4),
                    Text(context.t('group.departments_n', {'n': c.departmentCount}), style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
                    if (c.ownerManaged) ...[const SizedBox(width: 14), Pill(context.t('group.kept_by_owner'), color: const Color(0xFF8B5CF6), icon: Icons.lock_outline_rounded)],
                  ]),
                ),
                onTap: () => showAppSheet(context, title: c.name, child: _CompanyActions(company: c)),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompanyActions extends ConsumerWidget {
  final GroupCompany company;
  const _CompanyActions({required this.company});

  Future<void> _setStatus(BuildContext context, WidgetRef ref, String status) async {
    final nav = Navigator.of(context);
    if (status == 'suspended' && !await confirmDialog(context, title: context.t('group.suspend'), message: context.t('group.suspend_hint'), danger: true, confirmLabel: context.t('group.suspend'))) return;
    try {
      await ref.read(apiProvider).put('/group/companies/${company.id}', {'status': status});
      ref.invalidate(groupCompaniesProvider);
      await ref.read(sessionProvider.notifier).refresh();
      if (context.mounted) toast(context, context.t('common.saved'));
      nav.pop();
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _setOwnerManaged(BuildContext context, WidgetRef ref, bool value) async {
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).put('/group/companies/${company.id}', {'ownerManaged': value});
      ref.invalidate(groupCompaniesProvider);
      if (context.mounted) toast(context, context.t('common.saved'));
      nav.pop();
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(sessionProvider).company?.id == company.id;
    Widget tile(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color ?? context.scheme.primary),
          title: Text(label, style: TextStyle(color: color)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        );
    return Column(children: [
      if (company.active && !isCurrent) tile(Icons.login_rounded, context.t('group.enter'), () => startSwitch(context, ref, company, popSheet: true)),
      tile(Icons.edit_rounded, context.t('group.rename'), () {
        Navigator.of(context).pop();
        showAppSheet(context, title: context.t('group.rename'), child: _RenameForm(company: company));
      }),
      tile(Icons.badge_rounded, context.t('group.new_ceo'), () {
        Navigator.of(context).pop();
        showAppSheet(context, title: context.t('group.new_ceo'), child: _CeoForm(company: company));
      }),
      tile(Icons.key_rounded, context.t('group.who_manages'), () {
        Navigator.of(context).pop();
        context.push('/h/group-access');
      }),
      if (!company.isHome && ref.watch(groupCompaniesProvider).valueOrNull?.isOwner == true)
        tile(company.ownerManaged ? Icons.visibility_rounded : Icons.lock_outline_rounded, company.ownerManaged ? context.t('group.show_super') : context.t('group.keep_private'), () => _setOwnerManaged(context, ref, !company.ownerManaged)),
      if (!company.isHome)
        company.active
            ? tile(Icons.pause_circle_rounded, context.t('group.suspend'), () => _setStatus(context, ref, 'suspended'), color: context.colors.danger)
            : tile(Icons.play_circle_rounded, context.t('group.activate'), () => _setStatus(context, ref, 'active')),
    ]);
  }
}

class _CompanyForm extends ConsumerStatefulWidget {
  const _CompanyForm();

  @override
  ConsumerState<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends ConsumerState<_CompanyForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _ceoName = TextEditingController();
  final _ceoEmail = TextEditingController();
  final _ceoPassword = TextEditingController();
  final _ceoPhone = TextEditingController();
  final Set<int> _picked = {};
  bool _busy = false;

  bool get _wantsNew => _ceoName.text.trim().isNotEmpty || _ceoEmail.text.trim().isNotEmpty || _ceoPassword.text.isNotEmpty;

  @override
  void dispose() {
    for (final c in [_name, _ceoName, _ceoEmail, _ceoPassword, _ceoPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).post('/group/companies', {
        'name': _name.text.trim(),
        'hrUserIds': _picked.toList(),
        if (_wantsNew) ...{
          'ceoName': _ceoName.text.trim(),
          'ceoEmail': _ceoEmail.text.trim().toLowerCase(),
          'ceoPassword': _ceoPassword.text,
          if (_ceoPhone.text.trim().isNotEmpty) 'ceoPhone': _ceoPhone.text.trim(),
        },
      });
      ref.invalidate(groupCompaniesProvider);
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) toast(context, context.t('group.created'));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(controller: _name, label: context.t('group.company_name'), icon: Icons.business_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
          const SizedBox(height: 18),
          Text(context.t('group.who_runs'), style: context.text.titleSmall),
          Padding(padding: const EdgeInsets.only(top: 4, bottom: 6), child: Text(context.t('group.who_runs_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
          for (final p in ref.watch(groupPeopleProvider).valueOrNull ?? const <GroupPerson>[])
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _picked.contains(p.id),
              onChanged: (v) => setState(() => v == true ? _picked.add(p.id) : _picked.remove(p.id)),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${p.email} · ${p.companyName}${p.isSuperAdmin ? ' · ${context.t('group.super_admin')}' : ''}', style: const TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 14),
          Text(context.t('group.new_hr_optional'), style: context.text.titleSmall),
          const SizedBox(height: 10),
          AppField(controller: _ceoName, label: context.t('group.ceo_name'), icon: Icons.person_outline_rounded, capitalization: TextCapitalization.words, onChanged: (_) => setState(() {}), validator: (v) => _wantsNew ? requiredValidator(context, v) : null),
          const SizedBox(height: 14),
          AppField(controller: _ceoEmail, label: context.t('group.ceo_email'), icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress, onChanged: (_) => setState(() {}), validator: (v) => _wantsNew ? emailValidator(context, v) : null),
          const SizedBox(height: 14),
          AppField(controller: _ceoPassword, label: context.t('group.ceo_password'), icon: Icons.lock_outline_rounded, obscure: true, onChanged: (_) => setState(() {}), validator: (v) => _wantsNew ? passwordValidator(context, v) : null),
          const SizedBox(height: 14),
          AppField(controller: _ceoPhone, label: context.t('group.ceo_phone'), icon: Icons.phone_outlined, keyboard: TextInputType.phone),
          const SizedBox(height: 18),
          LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
        ]),
      );
}

class _RenameForm extends ConsumerStatefulWidget {
  final GroupCompany company;
  const _RenameForm({required this.company});

  @override
  ConsumerState<_RenameForm> createState() => _RenameFormState();
}

class _RenameFormState extends ConsumerState<_RenameForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.company.name);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).put('/group/companies/${widget.company.id}', {'name': _name.text.trim()});
      ref.invalidate(groupCompaniesProvider);
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) toast(context, context.t('common.saved'));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(controller: _name, label: context.t('group.company_name'), icon: Icons.business_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
          const SizedBox(height: 18),
          LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
        ]),
      );
}

class _CeoForm extends ConsumerStatefulWidget {
  final GroupCompany company;
  const _CeoForm({required this.company});

  @override
  ConsumerState<_CeoForm> createState() => _CeoFormState();
}

class _CeoFormState extends ConsumerState<_CeoForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).post('/group/companies/${widget.company.id}/ceo', {'name': _name.text.trim(), 'email': _email.text.trim().toLowerCase(), 'password': _password.text});
      ref.invalidate(groupCompaniesProvider);
      if (mounted) toast(context, context.t('common.saved'));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(context.t('group.ceo_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 14),
          AppField(controller: _name, label: context.t('group.ceo_name'), icon: Icons.person_outline_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
          const SizedBox(height: 14),
          AppField(controller: _email, label: context.t('group.ceo_email'), icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress, validator: (v) => emailValidator(context, v)),
          const SizedBox(height: 14),
          AppField(controller: _password, label: context.t('group.ceo_password'), icon: Icons.lock_outline_rounded, obscure: true, validator: (v) => passwordValidator(context, v)),
          const SizedBox(height: 18),
          LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
        ]),
      );
}

// ======================================================================== access

class GroupAccessScreen extends ConsumerWidget {
  const GroupAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grants = ref.watch(groupAccessProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('group.access'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAppSheet(context, title: context.t('group.give_access'), child: const _GrantForm()),
        icon: const Icon(Icons.key_rounded),
        label: Text(context.t('group.give_access')),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(groupAccessProvider);
          await ref.read(groupAccessProvider.future).catchError((_) => <AccessGrant>[]);
        },
        child: AsyncBody<List<AccessGrant>>(
          value: grants,
          onRetry: () => ref.invalidate(groupAccessProvider),
          builder: (items) {
            if (items.isEmpty) {
              return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                SizedBox(height: 360, child: EmptyState(icon: Icons.key_off_rounded, title: context.t('group.no_access'), subtitle: context.t('group.no_access_hint'))),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(context.t('group.access_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)));
                final g = items[i - 1];
                final label = g.readOnly ? context.t('group.access_ro') : (g.level == 'full' ? context.t('group.access_full') : context.t('group.access_custom'));
                return RowTile(
                  leading: Avatar(name: g.userName, size: 44),
                  title: g.userName,
                  subtitle: '${g.homeCompanyName}  →  ${g.companyName}',
                  trailing: Pill(label, color: g.level == 'full' && !g.readOnly ? context.scheme.primary : context.colors.info),
                  bottom: g.level == 'custom'
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Align(alignment: AlignmentDirectional.centerStart, child: Text(g.modules.map((m) => context.t('module.$m')).join(' · '), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.4))),
                        )
                      : null,
                  onTap: () async {
                    if (!await confirmDialog(context, title: context.t('group.revoke'), message: context.t('group.revoke_hint'), danger: true, confirmLabel: context.t('group.revoke'))) return;
                    try {
                      await ref.read(apiProvider).delete('/group/access/${g.id}');
                      ref.invalidate(groupAccessProvider);
                      if (context.mounted) toast(context, context.t('group.removed'));
                    } on ApiException catch (e) {
                      if (context.mounted) toast(context, e.message, error: true);
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _GrantForm extends ConsumerStatefulWidget {
  const _GrantForm();

  @override
  ConsumerState<_GrantForm> createState() => _GrantFormState();
}

class _GrantFormState extends ConsumerState<_GrantForm> {
  int? _personId;
  int? _companyId;
  bool _custom = false;
  bool _readOnly = false;
  final Map<String, bool> _modules = {for (final m in groupModules) m: m == 'dashboard'};
  bool _busy = false;

  Future<void> _save() async {
    if (_personId == null || _companyId == null) {
      toast(context, context.t('group.pick_person'), error: true);
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).post('/group/access', {
        'userId': _personId,
        'companyId': _companyId,
        'level': _custom ? 'custom' : 'full',
        if (_custom) 'modules': [for (final e in _modules.entries) if (e.value) e.key],
        'readOnly': _readOnly,
      });
      ref.invalidate(groupAccessProvider);
      if (mounted) toast(context, context.t('group.saved'));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(groupPeopleProvider);
    final companies = ref.watch(groupCompaniesProvider);
    if (people.isLoading || companies.isLoading) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    final persons = people.valueOrNull ?? const <GroupPerson>[];
    final all = companies.valueOrNull?.companies.where((c) => c.active).toList() ?? const <GroupCompany>[];
    final person = persons.where((p) => p.id == _personId).firstOrNull;
    final targets = all.where((c) => c.id != person?.companyId).toList();
    if (_companyId != null && !targets.any((c) => c.id == _companyId)) _companyId = null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<int>(
        initialValue: _personId,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.t('group.person'), prefixIcon: const Icon(Icons.person_outline_rounded)),
        items: [for (final p in persons) DropdownMenuItem(value: p.id, child: Text('${p.name} · ${p.companyName}', overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => _personId = v),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<int>(
        key: ValueKey("company-for-$_personId"),
        initialValue: _companyId,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.t('group.company'), prefixIcon: const Icon(Icons.business_rounded)),
        items: [for (final c in targets) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => _companyId = v),
      ),
      const SizedBox(height: 18),
      Text(context.t('group.level'), style: context.text.titleSmall),
      const SizedBox(height: 8),
      SegmentBar(labels: [context.t('group.level_full'), context.t('group.level_custom')], index: _custom ? 1 : 0, onChanged: (i) => setState(() => _custom = i == 1)),
      Padding(padding: const EdgeInsets.only(top: 8), child: Text(_custom ? context.t('group.level_custom_hint') : context.t('group.level_full_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
      if (_custom) ...[
        const SizedBox(height: 12),
        Text(context.t('group.modules_pick'), style: context.text.titleSmall),
        for (final m in groupModules) SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(context.t('module.$m')), value: _modules[m] ?? false, onChanged: (v) => setState(() => _modules[m] = v)),
      ],
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('group.read_only')), value: _readOnly, onChanged: (v) => setState(() => _readOnly = v)),
      const SizedBox(height: 12),
      LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
    ]);
  }
}
