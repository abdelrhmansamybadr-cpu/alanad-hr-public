import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../premium/premium_common.dart';

/// The signed-in user's own employee record (null for HR accounts that are not employees).
final myProfileProvider = FutureProvider.autoDispose<Employee?>((ref) async {
  final m = asMap(await ref.read(apiProvider).get('/profile'));
  return m['employee'] is Map ? Employee.fromJson(m['employee']) : null;
});

Future<void> pickAndUploadAvatar(BuildContext context, WidgetRef ref) async {
  final ok = context.t('me.photo_updated');
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  final path = result?.files.single.path;
  if (path == null) return;
  try {
    await ref.read(apiProvider).upload('/profile/avatar', path);
    await ref.read(sessionProvider.notifier).refresh();
    ref.invalidate(myProfileProvider);
    if (context.mounted) toast(context, ok);
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
}

class ProfileCard extends ConsumerWidget {
  final AppUser user;
  final Company company;
  final Employee? employee;
  const ProfileCard({super.key, required this.user, required this.company, this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(ownerMeProvider).valueOrNull?['isOwner'] == true;
    final role = isOwner ? context.t('prem.role_owner') : user.isAdmin ? context.t('me.role_admin') : user.isHr ? context.t('me.role_hr') : (employee?.position.isNotEmpty ?? false) ? employee!.position : context.t('me.role_employee');
    return AppCard(
      padding: const EdgeInsets.all(20),
      shadow: true,
      child: Column(children: [
        Stack(children: [
          Avatar(name: user.name, url: user.avatar, size: 92, ring: true),
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => pickAndUploadAvatar(context, ref),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: context.scheme.primary, shape: BoxShape.circle, border: Border.all(color: context.scheme.surface, width: 3)),
                child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text(user.name, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(role, style: TextStyle(color: context.colors.subtext)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
          Pill(company.name, icon: Icons.business_rounded),
          if (employee?.departmentName != null) Pill(employee!.departmentName!, icon: Icons.account_tree_rounded, color: context.colors.info),
        ]),
        const SizedBox(height: 10),
        Text(user.email, style: TextStyle(color: context.colors.subtext, fontSize: 13)),
      ]),
    );
  }
}

class ProfileFacts extends StatelessWidget {
  final Employee employee;
  const ProfileFacts({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (employee.managerName != null) InfoRow(icon: Icons.supervisor_account_rounded, label: context.t('me.manager'), value: employee.managerName!),
      if (employee.shiftName != null) InfoRow(icon: Icons.schedule_rounded, label: context.t('me.shift'), value: employee.shiftName!),
      if (employee.startDate != null) InfoRow(icon: Icons.event_available_rounded, label: context.t('me.joined'), value: fmtDate(context, employee.startDate!)),
      if (employee.phone != null) InfoRow(icon: Icons.phone_rounded, label: context.t('common.phone'), value: employee.phone!),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Column(children: rows));
  }
}

class MenuGroup extends StatelessWidget {
  final List<Widget> children;
  const MenuGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(indent: 68, height: 1, color: context.colors.border),
            children[i],
          ],
        ]),
      );
}

class MenuItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? badge;
  final VoidCallback onTap;
  final Widget? trailing;
  const MenuItem({super.key, required this.icon, required this.color, required this.label, required this.onTap, this.badge, this.trailing});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            IconBadge(icon, color: color, size: 38),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
            if (badge != null) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: context.colors.danger, borderRadius: BorderRadius.circular(12)), child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
            if (trailing != null) trailing!,
            const SizedBox(width: 4),
            Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: context.colors.subtext),
          ]),
        ),
      );
}

class SignOutButton extends ConsumerWidget {
  const SignOutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
        onPressed: () async {
          final title = context.t('auth.sign_out');
          final msg = context.t('me.sign_out_confirm');
          if (await confirmDialog(context, title: title, message: msg, danger: true, confirmLabel: title)) {
            await ref.read(sessionProvider.notifier).signOut();
          }
        },
        icon: Icon(Icons.logout_rounded, color: context.colors.danger),
        label: Text(context.t('auth.sign_out'), style: TextStyle(color: context.colors.danger)),
        style: OutlinedButton.styleFrom(side: BorderSide(color: context.colors.danger.withValues(alpha: 0.4))),
      );
}
