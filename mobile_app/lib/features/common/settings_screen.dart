import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/config.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/push/push_service.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../../core/update/app_updater.dart';
import '../data/providers.dart';
import 'profile_widgets.dart';

/// Turns system notifications (check-in reminders, approvals, announcements) on or off.
class _PushSwitch extends StatefulWidget {
  const _PushSwitch();
  @override
  State<_PushSwitch> createState() => _PushSwitchState();
}

class _PushSwitchState extends State<_PushSwitch> {
  bool _on = true;
  bool _allowed = true;     // the phone's own permission

  @override
  void initState() {
    super.initState();
    PushService.isEnabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
    _refresh();
  }

  Future<void> _refresh() async {
    final ok = await PushService.permissionGranted();
    if (mounted) setState(() => _allowed = ok);
  }

  /// Ask the phone for permission; when it was refused for good, open the phone's settings page of this app.
  Future<void> _allow() async {
    final ok = await PushService.requestPermission();
    if (!ok) await openAppSettings();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SwitchListTile(
          value: _on,
          onChanged: (v) {
            setState(() => _on = v);
            PushService.setEnabled(v);
            if (v && !_allowed) _allow();
          },
          secondary: Icon(Icons.notifications_active_rounded, color: context.scheme.primary),
          title: Text(context.t('settings.push'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(context.t('settings.push_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
        ),
        if (!_allowed)
          ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: context.colors.warning),
            title: Text(context.t('settings.push_blocked'), style: TextStyle(color: context.colors.warning, fontWeight: FontWeight.w700, fontSize: 13.5)),
            subtitle: Text(context.t('settings.push_blocked_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
            trailing: FilledButton(onPressed: _allow, child: Text(context.t('settings.push_allow'))),
          ),
      ]);
}

// =============================================================== settings page

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final mode = ref.watch(themeModeProvider);
    final user = ref.watch(sessionProvider).user!;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('me.settings'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        SectionHeader(context.t('settings.appearance'), padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('common.language'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentBar(labels: const ['English', 'العربية'], index: locale.languageCode == 'ar' ? 1 : 0, onChanged: (i) => ref.read(localeProvider.notifier).set(i == 1 ? 'ar' : 'en')),
            const SizedBox(height: 18),
            Text(context.t('settings.theme'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentBar(
              labels: [context.t('settings.theme_system'), context.t('settings.theme_light'), context.t('settings.theme_dark')],
              index: {ThemeMode.system: 0, ThemeMode.light: 1, ThemeMode.dark: 2}[mode]!,
              onChanged: (i) => ref.read(themeModeProvider.notifier).set([ThemeMode.system, ThemeMode.light, ThemeMode.dark][i]),
            ),
          ]),
        ),
        SectionHeader(context.t('settings.notifications')),
        const AppCard(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: _PushSwitch()),
        SectionHeader(context.t('settings.security')),
        MenuGroup(children: [
          MenuItem(icon: Icons.lock_reset_rounded, color: const Color(0xFF6366F1), label: context.t('settings.change_password'), onTap: () => showAppSheet(context, title: context.t('settings.change_password'), child: const _ChangePasswordForm())),
        ]),
        SectionHeader(context.t('settings.about')),
        MenuGroup(children: [
          MenuItem(
            icon: Icons.privacy_tip_outlined,
            color: const Color(0xFF0EA5E9),
            label: context.t('settings.privacy'),
            onTap: () => launchUrl(Uri.parse('${AppConfig.baseUrl}/app/alanad/privacy.html'), mode: LaunchMode.externalApplication),
          ),
          MenuItem(
            icon: Icons.support_agent_rounded,
            color: const Color(0xFF22C55E),
            label: context.t('settings.support'),
            onTap: () => launchUrl(Uri(scheme: 'mailto', path: 'info@anadcorp.com', queryParameters: {'subject': 'Al Anad HR support'})),
          ),
        ]),
        const SizedBox(height: 10),
        AppCard(
          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (_, snap) => Column(children: [
              InfoRow(icon: Icons.info_outline_rounded, label: context.t('settings.version'), value: snap.hasData ? '${snap.data!.version} (${snap.data!.buildNumber})' : '…'),
              InfoRow(icon: Icons.person_outline_rounded, label: context.t('settings.signed_in_as'), value: user.email),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final none = context.t('settings.up_to_date');
                  final u = await checkForUpdate();
                  if (context.mounted && u == null) toast(context, none);
                },
                icon: const Icon(Icons.system_update_alt_rounded),
                label: Text(context.t('settings.check_updates')),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 22),
        const SignOutButton(),
      ]),
    );
  }
}

class _ChangePasswordForm extends ConsumerStatefulWidget {
  const _ChangePasswordForm();

  @override
  ConsumerState<_ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<_ChangePasswordForm> {
  final _form = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).put('/auth/password', {'oldPassword': _old.text, 'newPassword': _new.text});
      if (mounted) {
        Navigator.pop(context);
        toast(context, context.t('settings.password_changed'));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(children: [
          AppField(controller: _old, label: context.t('settings.current_password'), icon: Icons.lock_outline_rounded, obscure: true, validator: (v) => requiredValidator(context, v)),
          const SizedBox(height: 14),
          AppField(controller: _new, label: context.t('auth.reset.new_password'), icon: Icons.lock_reset_rounded, obscure: true, validator: (v) => passwordValidator(context, v)),
          const SizedBox(height: 14),
          AppField(controller: _confirm, label: context.t('auth.activate.confirm'), icon: Icons.verified_user_outlined, obscure: true, validator: (v) => v != _new.text ? context.t('auth.password_mismatch') : null),
          if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: TextStyle(color: context.colors.danger, fontWeight: FontWeight.w600))],
          const SizedBox(height: 20),
          LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
        ]),
      );
}

// ============================================================== my information

/// Employees see their data here but cannot change what HR entered: they send a change request.
/// HR / admin accounts (which have no employee record) edit their own name, phone and title directly.
class ProfileEditScreen extends ConsumerWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user!;
    if (user.employeeId == null) return _HrProfileEdit(user: user);
    final profile = ref.watch(myProfileProvider);
    final mine = ref.watch(requestsProvider((scope: 'mine', status: 'pending'))).valueOrNull ?? const <RequestItem>[];
    final pending = mine.where((r) => r.type == 'profile_change').toList();

    return Scaffold(
      appBar: AppBar(title: Text(context.t('me.personal'))),
      body: profile.when(
        loading: () => const SkeletonList(count: 4),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myProfileProvider)),
        data: (emp) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          Center(child: GestureDetector(onTap: () => pickAndUploadAvatar(context, ref), child: Stack(children: [Avatar(name: user.name, url: user.avatar, size: 96, ring: true), PositionedDirectional(end: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: context.scheme.primary, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white)))]))),
          const SizedBox(height: 14),
          AppCard(
            color: context.colors.brandSoft,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline_rounded, color: context.scheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(context.t('info.locked'), style: TextStyle(color: context.scheme.primary, fontWeight: FontWeight.w600, height: 1.4))),
            ]),
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              color: context.colors.warning.withValues(alpha: 0.12),
              child: Row(children: [
                Icon(Icons.hourglass_top_rounded, color: context.colors.warning),
                const SizedBox(width: 10),
                Expanded(child: Text(context.t('info.pending', {'n': pending.length}), style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              InfoRow(icon: Icons.badge_outlined, label: context.t('common.name'), value: user.name),
              InfoRow(icon: Icons.alternate_email_rounded, label: context.t('common.email'), value: user.email),
              if (emp != null) ...[
                InfoRow(icon: Icons.work_outline_rounded, label: context.t('emp.position'), value: emp.position.isEmpty ? '—' : emp.position),
                InfoRow(icon: Icons.account_tree_outlined, label: context.t('people.department'), value: emp.departmentName ?? '—'),
                InfoRow(icon: Icons.supervisor_account_rounded, label: context.t('me.manager'), value: emp.managerName ?? '—'),
                InfoRow(icon: Icons.schedule_rounded, label: context.t('me.shift'), value: emp.shiftName ?? context.t('info.default_shift')),
                if (emp.startDate != null) InfoRow(icon: Icons.event_available_rounded, label: context.t('me.joined'), value: fmtDate(context, emp.startDate!)),
              ],
            ]),
          ),
          if (emp != null) ...[
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: [
                InfoRow(icon: Icons.phone_outlined, label: context.t('common.phone'), value: (emp.phone ?? '').isEmpty ? '—' : emp.phone!),
                InfoRow(icon: Icons.home_outlined, label: context.t('emp.address'), value: (emp.address ?? '').isEmpty ? '—' : emp.address!),
                InfoRow(icon: Icons.cake_outlined, label: context.t('emp.birth_date'), value: emp.birthDate == null ? '—' : fmtDate(context, emp.birthDate!)),
                InfoRow(icon: Icons.wc_rounded, label: context.t('emp.gender'), value: emp.gender == null ? '—' : context.t(emp.gender == 'male' ? 'emp.male' : 'emp.female')),
                InfoRow(icon: Icons.contact_emergency_outlined, label: context.t('emp.emergency'), value: [emp.emergencyName, emp.emergencyPhone].where((e) => e != null && e.isNotEmpty).join(' · ').isEmpty ? '—' : [emp.emergencyName, emp.emergencyPhone].where((e) => e != null && e.isNotEmpty).join(' · ')),
              ]),
            ),
            const SizedBox(height: 20),
            LoadingButton(
              label: context.t('info.request_change'),
              icon: Icons.edit_note_rounded,
              onPressed: () => showAppSheet(context, title: context.t('info.request_change'), child: _ChangeRequestForm(emp: emp)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ChangeRequestForm extends ConsumerStatefulWidget {
  final Employee emp;
  const _ChangeRequestForm({required this.emp});

  @override
  ConsumerState<_ChangeRequestForm> createState() => _ChangeRequestFormState();
}

class _ChangeRequestFormState extends ConsumerState<_ChangeRequestForm> {
  late final _first = TextEditingController(text: widget.emp.firstName);
  late final _last = TextEditingController(text: widget.emp.lastName);
  late final _phone = TextEditingController(text: widget.emp.phone ?? '');
  late final _address = TextEditingController(text: widget.emp.address ?? '');
  late final _emName = TextEditingController(text: widget.emp.emergencyName ?? '');
  late final _emPhone = TextEditingController(text: widget.emp.emergencyPhone ?? '');
  late DateTime? _birth = widget.emp.birthDate;
  late String? _gender = widget.emp.gender;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _address, _emName, _emPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final e = widget.emp;
    final changes = <String, String>{};
    void diff(String key, String now, String? old) {
      if (now.trim() != (old ?? '')) changes[key] = now.trim();
    }

    diff('first_name', _first.text, e.firstName);
    diff('last_name', _last.text, e.lastName);
    diff('phone', _phone.text, e.phone);
    diff('address', _address.text, e.address);
    diff('emergency_name', _emName.text, e.emergencyName);
    diff('emergency_phone', _emPhone.text, e.emergencyPhone);
    diff('gender', _gender ?? '', e.gender);
    final oldBirth = e.birthDate == null ? '' : ymd(e.birthDate!);
    final newBirth = _birth == null ? '' : ymd(_birth!);
    if (oldBirth != newBirth) changes['birth_date'] = newBirth;
    if (changes.isEmpty) return toast(context, context.t('info.nothing_changed'), error: true);

    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).post('/requests', {'type': 'profile_change', 'payload': {'changes': changes}});
      ref.invalidate(requestsProvider);
      if (mounted) toast(context, context.t('info.sent'));
      nav.pop();
    } on ApiException catch (err) {
      if (mounted) toast(context, err.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('info.request_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: AppField(controller: _first, label: context.t('people.first_name'), capitalization: TextCapitalization.words)),
          const SizedBox(width: 12),
          Expanded(child: AppField(controller: _last, label: context.t('people.last_name'), capitalization: TextCapitalization.words)),
        ]),
        const SizedBox(height: 14),
        AppField(controller: _phone, label: context.t('common.phone'), icon: Icons.phone_outlined, keyboard: TextInputType.phone),
        const SizedBox(height: 14),
        AppField(controller: _address, label: context.t('emp.address'), icon: Icons.home_outlined, maxLines: 2),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _birth ?? DateTime(1995), firstDate: DateTime(1940), lastDate: DateTime.now());
            if (d != null) setState(() => _birth = d);
          },
          child: InputDecorator(decoration: InputDecoration(labelText: context.t('emp.birth_date'), prefixIcon: const Icon(Icons.cake_outlined)), child: Text(_birth == null ? '—' : fmtDate(context, _birth!))),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _gender,
          decoration: InputDecoration(labelText: context.t('emp.gender'), prefixIcon: const Icon(Icons.wc_rounded)),
          items: [DropdownMenuItem(value: 'male', child: Text(context.t('emp.male'))), DropdownMenuItem(value: 'female', child: Text(context.t('emp.female')))],
          onChanged: (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: 14),
        AppField(controller: _emName, label: context.t('emp.emergency_name'), icon: Icons.contact_emergency_outlined),
        const SizedBox(height: 14),
        AppField(controller: _emPhone, label: context.t('emp.emergency_phone'), icon: Icons.phone_in_talk_outlined, keyboard: TextInputType.phone, formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]'))]),
        const SizedBox(height: 22),
        LoadingButton(label: context.t('info.send_request'), loading: _busy, onPressed: _send),
      ]);
}

/// Admin / HR accounts that are not employees manage their own contact details directly.
class _HrProfileEdit extends ConsumerStatefulWidget {
  final AppUser user;
  const _HrProfileEdit({required this.user});

  @override
  ConsumerState<_HrProfileEdit> createState() => _HrProfileEditState();
}

class _HrProfileEditState extends ConsumerState<_HrProfileEdit> {
  late final _name = TextEditingController(text: widget.user.name);
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late final _title = TextEditingController(text: widget.user.title ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast(context, context.t('common.required'), error: true);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/profile', {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'title': _title.text.trim()});
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) {
        toast(context, context.t('common.saved'));
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user!;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('me.personal'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: GestureDetector(onTap: () => pickAndUploadAvatar(context, ref), child: Stack(children: [Avatar(name: user.name, url: user.avatar, size: 96, ring: true), PositionedDirectional(end: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: context.scheme.primary, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white)))]))),
        const SizedBox(height: 22),
        AppField(controller: _name, label: context.t('common.name'), icon: Icons.badge_outlined, capitalization: TextCapitalization.words),
        const SizedBox(height: 14),
        AppField(controller: _title, label: context.t('me.job_title'), icon: Icons.work_outline_rounded),
        const SizedBox(height: 14),
        AppField(controller: _phone, label: context.t('common.phone'), icon: Icons.phone_outlined, keyboard: TextInputType.phone),
        const SizedBox(height: 14),
        InfoRow(icon: Icons.alternate_email_rounded, label: context.t('common.email'), value: user.email),
        const SizedBox(height: 24),
        LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
      ]),
    );
  }
}
