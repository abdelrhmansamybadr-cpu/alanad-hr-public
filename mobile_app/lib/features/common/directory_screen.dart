import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/ui/widgets.dart';
import '../../core/session/session.dart';
import '../data/providers.dart';
import '../premium/complaints_screens.dart';
import '../premium/premium_common.dart';

Future<void> _launch(BuildContext context, Uri uri) async {
  final failed = context.t('dir.cannot_open');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) toast(context, failed, error: true);
}

/// Contact card for a colleague with call / message / email shortcuts.
Future<void> showContactSheet(BuildContext context, Employee e) {
  Widget action(IconData icon, String label, Color color, VoidCallback? onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: Column(children: [
              Container(width: 58, height: 58, decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)), child: Icon(icon, color: color)),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
          ),
        ),
      );
  return showAppSheet(
    context,
    title: e.fullName,
    child: Column(children: [
      Avatar(name: e.fullName, url: e.avatar, size: 88, ring: true),
      const SizedBox(height: 12),
      Text(e.position, style: TextStyle(color: context.colors.subtext)),
      if (e.departmentName != null) Padding(padding: const EdgeInsets.only(top: 8), child: Pill(e.departmentName!, icon: Icons.account_tree_rounded)),
      const SizedBox(height: 22),
      Row(children: [
        action(Icons.call_rounded, context.t('dir.call'), context.colors.success, e.phone == null ? null : () => _launch(context, Uri(scheme: 'tel', path: e.phone))),
        action(Icons.chat_rounded, context.t('dir.whatsapp'), const Color(0xFF25D366), e.phone == null ? null : () => _launch(context, Uri.parse('https://wa.me/${e.phone!.replaceAll(RegExp(r'[^0-9]'), '')}'))),
        action(Icons.email_rounded, context.t('dir.email'), context.scheme.primary, e.email.isEmpty ? null : () => _launch(context, Uri(scheme: 'mailto', path: e.email))),
      ]),
      const SizedBox(height: 18),
      if (e.email.isNotEmpty) InfoRow(icon: Icons.alternate_email_rounded, label: context.t('common.email'), value: e.email),
      if (e.phone != null) InfoRow(icon: Icons.phone_outlined, label: context.t('common.phone'), value: e.phone!),
    ]),
  );
}

class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key});

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(directoryProvider(_q));
    return Scaffold(
      appBar: AppBar(title: Text(context.t('home.qa.directory'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _q = v.trim()));
            },
            decoration: InputDecoration(hintText: context.t('dir.search'), prefixIcon: const Icon(Icons.search_rounded)),
          ),
        ),
        Expanded(
          child: AsyncBody<List<Employee>>(
            value: list,
            onRetry: () => ref.invalidate(directoryProvider(_q)),
            builder: (items) => items.isEmpty
                ? EmptyState(icon: Icons.person_search_rounded, title: context.t('common.no_results'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final e = items[i];
                      return RowTile(leading: Avatar(name: e.fullName, url: e.avatar, size: 48), title: e.fullName, subtitle: [e.position, if (e.departmentName != null) e.departmentName!].where((s) => s.isNotEmpty).join(' · '), onTap: () => showContactSheet(context, e));
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

/// Team lead: direct reports with today's status.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('me.my_team'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(teamProvider);
          await ref.read(teamProvider.future).catchError((_) => <BoardRow>[]);
        },
        child: AsyncBody<List<BoardRow>>(
          value: team,
          onRetry: () => ref.invalidate(teamProvider),
          builder: (rows) => rows.isEmpty
              ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.groups_rounded, title: context.t('team.empty')))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return RowTile(
                      leading: Avatar(name: r.name, url: r.avatar, size: 48),
                      title: r.name,
                      subtitle: r.status == 'absent' ? r.position : (r.checkIn != null ? '${r.position} · ${r.checkIn!.substring(0, 5)}' : r.position),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        StatusChip(r.status == 'not_yet' ? 'pending' : r.status),
                        if (ref.watch(sessionProvider).company?.hasFeature(Feat.complaints) ?? false)
                          IconButton(tooltip: context.t('cmp.complain'), icon: Icon(Icons.report_gmailerrorred_rounded, color: context.colors.danger), onPressed: () => showComplaintForm(context, ref, targetId: r.employeeId)),
                      ]),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
