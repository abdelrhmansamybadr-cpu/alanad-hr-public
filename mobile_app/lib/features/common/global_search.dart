import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart' show rootNavigatorKey;
import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/responsive.dart';
import '../../core/ui/widgets.dart';
import '../group/group_screens.dart';
import '../premium/premium_common.dart';
import 'directory_screen.dart';

class _Page {
  final IconData icon;
  final String label;
  final String path;
  const _Page(this.icon, this.label, this.path);
}

class _Person {
  final int id;
  final String name;
  final String sub;
  final int? companyId;
  final String? companyName;
  final Employee? employee;
  const _Person(this.id, this.name, this.sub, {this.companyId, this.companyName, this.employee});
}

/// One search box for the whole app: finds pages (by name) and people. HR searches the company's employees, the owner searches
/// every company, an employee searches the company directory. Opened from the side menu (laptop) or the search icon (phone).
Future<void> showGlobalSearch(BuildContext context) {
  final body = const _SearchBody();
  if (!context.isDesktop) {
    return showDialog(context: context, useSafeArea: true, builder: (_) => Dialog.fullscreen(child: body));
  }
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 70, left: 24, right: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560), child: body),
    ),
  );
}

/// The small search icon used in the phone home headers.
class SearchIconButton extends StatelessWidget {
  const SearchIconButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(tooltip: context.t('common.search'), onPressed: () => showGlobalSearch(context), icon: const Icon(Icons.search_rounded));
}

/// The search box shown at the top of the laptop side menu.
class SidebarSearch extends StatelessWidget {
  const SidebarSearch({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showGlobalSearch(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.search_rounded, size: 19, color: c.subtext),
            const SizedBox(width: 10),
            Expanded(child: Text(context.t('search.hint'), style: TextStyle(color: c.subtext, fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}

class _SearchBody extends ConsumerStatefulWidget {
  const _SearchBody();

  @override
  ConsumerState<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends ConsumerState<_SearchBody> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  String _q = '';
  List<_Person> _people = const [];
  bool _loading = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  List<_Page> _pages(BuildContext context) {
    final user = ref.read(sessionProvider).user;
    final t = context.t;
    if (user == null) return const [];
    if (user.isHr) {
      return [
        _Page(Icons.dashboard_rounded, t('nav.home'), '/h/home'),
        _Page(Icons.people_alt_rounded, t('nav.people'), '/h/people'),
        _Page(Icons.access_time_filled_rounded, t('nav.board'), '/h/attendance'),
        _Page(Icons.fact_check_rounded, t('nav.approvals'), '/h/approvals'),
        _Page(Icons.notifications_rounded, t('nav.inbox'), '/inbox'),
        _Page(Icons.account_tree_rounded, t('module.departments'), '/h/departments'),
        _Page(Icons.schedule_rounded, t('module.shifts'), '/h/shifts'),
        _Page(Icons.payments_rounded, t('module.payroll'), '/h/payroll'),
        _Page(Icons.work_outline_rounded, t('module.recruitment'), '/h/recruitment'),
        _Page(Icons.description_rounded, t('ctr.title'), '/h/contracts'),
        _Page(Icons.workspace_premium_rounded, t('cert.title'), '/h/certificates'),
        _Page(Icons.campaign_rounded, t('home.announcements'), '/announcements'),
        _Page(Icons.videocam_rounded, t('meet.title'), '/meetings'),
        _Page(Icons.ios_share_rounded, t('more.reports'), '/h/reports'),
        _Page(Icons.people_outline_rounded, t('home.qa.directory'), '/directory'),
        _Page(Icons.settings_rounded, t('me.settings'), '/settings'),
      ];
    }
    return [
      _Page(Icons.home_rounded, t('nav.home'), '/e/home'),
      _Page(Icons.access_time_filled_rounded, t('nav.time'), '/e/time'),
      _Page(Icons.assignment_rounded, t('nav.requests'), '/e/requests'),
      _Page(Icons.notifications_rounded, t('nav.inbox'), '/e/inbox'),
      _Page(Icons.person_rounded, t('nav.me'), '/e/me'),
      _Page(Icons.receipt_long_rounded, t('home.qa.payslips'), '/payslips'),
      _Page(Icons.folder_copy_rounded, t('home.qa.documents'), '/documents'),
      _Page(Icons.people_alt_rounded, t('home.qa.directory'), '/directory'),
      _Page(Icons.campaign_rounded, t('home.announcements'), '/announcements'),
      _Page(Icons.videocam_rounded, t('meet.title'), '/meetings'),
      _Page(Icons.celebration_rounded, t('me.holidays'), '/holidays'),
      _Page(Icons.settings_rounded, t('me.settings'), '/settings'),
    ];
  }

  void _onChanged(String v) {
    setState(() => _q = v.trim());
    _debounce?.cancel();
    if (_q.length < 2) {
      _seq++;
      setState(() {
        _people = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _searchPeople);
  }

  Future<void> _searchPeople() async {
    final q = _q;
    final my = ++_seq;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final session = ref.read(sessionProvider);
      final owner = session.user?.isHr == true && ref.read(ownerMeProvider).valueOrNull?['isOwner'] == true;
      final List<_Person> found;
      if (owner) {
        // the owner searches every company of the group
        final rows = asMapList(await api.get('/group/search', query: {'q': q}));
        found = rows
            .map((m) => _Person(jInt(m, 'id'), '${jStr(m, 'firstName')} ${jStr(m, 'lastName')}'.trim(), [jStr(m, 'position'), jStr(m, 'departmentName')].where((s) => s.isNotEmpty).join(' · '),
                companyId: jInt(m, 'companyId'), companyName: jStr(m, 'companyName')))
            .toList();
      } else if (session.user?.isHr == true) {
        final rows = asMapList(await api.get('/employees', query: {'q': q}));
        found = rows.map(Employee.fromJson).map((e) => _Person(e.id, e.fullName, [e.position, e.departmentName ?? ''].where((s) => s.isNotEmpty).join(' · '), employee: e)).toList();
      } else {
        final rows = asMapList(await api.get('/directory', query: {'q': q}));
        found = rows.map(Employee.fromJson).map((e) => _Person(e.id, e.fullName, [e.position, e.departmentName ?? ''].where((s) => s.isNotEmpty).join(' · '), employee: e)).toList();
      }
      if (!mounted || my != _seq) return;
      setState(() {
        _people = found.take(30).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted && my == _seq) {
        setState(() {
          _people = const [];
          _loading = false;
        });
      }
    }
  }

  void _openPage(_Page p) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    (p.path.startsWith('/h/') || p.path.startsWith('/e/')) ? router.go(p.path) : router.push(p.path);
  }

  void _openPerson(_Person p) {
    final session = ref.read(sessionProvider);
    final router = GoRouter.of(context);
    final nav = Navigator.of(context);
    final outer = rootNavigatorKey.currentContext ?? context;
    if (session.user?.isHr == true) {
      if (p.companyId != null && p.companyId != session.company?.id) {
        // another company of the group: switch there first
        final target = session.group?.companies.where((c) => c.id == p.companyId).firstOrNull;
        nav.pop();
        if (target != null) startSwitch(outer, ref, target);
        return;
      }
      nav.pop();
      router.push('/h/employee/${p.id}');
    } else if (p.employee != null) {
      nav.pop();
      showContactSheet(outer, p.employee!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.toLowerCase();
    final pages = q.isEmpty ? <_Page>[] : _pages(context).where((p) => p.label.toLowerCase().contains(q)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.t('search.hint'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _ctl.clear(); _onChanged(''); }),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(tooltip: context.t('common.close'), onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
        ]),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: _q.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(context.t('search.type_more'), textAlign: TextAlign.center, style: TextStyle(color: c.subtext))))
            : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 16), children: [
                if (pages.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(6, 8, 6, 6), child: Text(context.t('search.pages'), style: TextStyle(color: c.subtext, fontWeight: FontWeight.w800, fontSize: 12))),
                  for (final p in pages) ListTile(dense: true, leading: Icon(p.icon, color: context.scheme.primary), title: Text(p.label), onTap: () => _openPage(p)),
                ],
                if (_q.length >= 2) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(6, 12, 6, 6), child: Text(context.t('search.people'), style: TextStyle(color: c.subtext, fontWeight: FontWeight.w800, fontSize: 12))),
                  if (_people.isEmpty && !_loading) Padding(padding: const EdgeInsets.all(16), child: Text(context.t('common.no_results'), style: TextStyle(color: c.subtext))),
                  for (final p in _people)
                    ListTile(
                      leading: Avatar(name: p.name, url: p.employee?.avatar, size: 40),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([p.sub, if (p.companyName != null && p.companyName!.isNotEmpty) p.companyName!].where((s) => s.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _openPerson(p),
                    ),
                ] else if (pages.isEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text(context.t('search.type_more'), style: TextStyle(color: c.subtext))),
              ]),
      ),
    ]);
  }
}
