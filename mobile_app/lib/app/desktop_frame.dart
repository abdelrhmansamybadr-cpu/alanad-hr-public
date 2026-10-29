import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config.dart';
import '../core/i18n/strings.dart';
import '../core/session/session.dart';
import '../core/ui/responsive.dart';
import '../core/ui/widgets.dart';
import '../features/auth/auth_screens.dart';
import '../features/common/global_search.dart';
import '../features/data/providers.dart';
import '../features/group/group_screens.dart';
import '../features/premium/premium_common.dart';
import 'router.dart';
import 'theme.dart';

/// On a laptop-sized window every signed-in page sits next to a permanent side menu (like the website),
/// instead of the phone's floating bottom bar. On a phone, or on the sign-in pages, nothing changes.
class DesktopFrame extends ConsumerStatefulWidget {
  final GoRouter router;
  final Widget child;
  const DesktopFrame({super.key, required this.router, required this.child});

  @override
  ConsumerState<DesktopFrame> createState() => _DesktopFrameState();
}

class _DesktopFrameState extends ConsumerState<DesktopFrame> {
  final _childKey = GlobalKey();

  static bool _noMenu(String loc) => loc == '/splash' || loc == '/' || loc == '/switching' || loc == '/welcome' || loc.startsWith('/auth') || loc.startsWith('/meeting/');

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final body = KeyedSubtree(key: _childKey, child: widget.child);
    if (!context.isDesktop) return body;
    return ListenableBuilder(
      listenable: widget.router.routerDelegate,
      builder: (context, _) {
        final cfg = widget.router.routerDelegate.currentConfiguration;
        // the top-most page, including ones opened with push()
        final loc = cfg.lastOrNull?.matchedLocation ?? cfg.uri.path;
        // Signed out: brand panel on the left, the sign-in form on the right
        if (s.status == SessionStatus.signedOut && (loc == '/welcome' || loc.startsWith('/auth'))) {
          return _AuthSplit(router: widget.router, welcome: loc == '/welcome', child: body);
        }
        if (s.status != SessionStatus.signedIn || s.user == null || s.company == null || _noMenu(loc)) return body;
        return Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Row(children: [
            _Sidebar(router: widget.router, location: loc),
            Expanded(child: ClipRect(child: body)),
          ]),
        );
      },
    );
  }
}

/// Laptop sign-in: a brand panel with the product story on the left, the actual form on the right.
class _AuthSplit extends StatelessWidget {
  final GoRouter router;
  final bool welcome;
  final Widget child;
  const _AuthSplit({required this.router, required this.welcome, required this.child});

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(gradient: brandGradient(context)),
              child: const SafeArea(child: Center(child: Padding(padding: EdgeInsets.all(48), child: WelcomeHero(wide: true)))),
            ),
          ),
          Expanded(
            flex: 4,
            child: Stack(children: [
              if (welcome) const PositionedDirectional(top: 14, end: 18, child: LanguageToggle()),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Stack(alignment: Alignment.center, children: [
                    Offstage(offstage: welcome, child: child),
                    if (welcome)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(context.t('auth.sign_in'), style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(context.t('auth.email.subtitle'), style: TextStyle(color: context.colors.subtext, height: 1.5)),
                          const SizedBox(height: 28),
                          EmailCheckForm(autofocus: true, router: router),
                        ]),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      );
}

class _Nav {
  final IconData icon;
  final String label;
  final String path;
  final int badge;
  const _Nav(this.icon, this.label, this.path, {this.badge = 0});
}

class _Sec {
  final String? title;
  final List<_Nav> items;
  const _Sec(this.title, this.items);
}

class _Sidebar extends ConsumerWidget {
  final GoRouter router;
  final String location;
  const _Sidebar({required this.router, required this.location});

  /// Detail pages keep their list highlighted in the menu (an employee's page lights up "People", ...).
  static const _belongsTo = {'/h/employee': '/h/people', '/h/department': '/h/departments', '/complaint': '/complaints', '/field': '/field', '/onboarding': '/h/onboarding'};

  bool _active(String path) {
    if (location == path) return true;
    for (final e in _belongsTo.entries) {
      if ((location == e.key || location.startsWith('${e.key}/')) && e.value == path) return true;
    }
    return path != '/h/home' && path != '/e/home' && location.startsWith('$path/');
  }

  List<_Sec> _hr(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user!;
    final company = session.company!;
    bool can(String m) => user.canUse(m) && company.hasModule(m);
    bool feat(String k) => company.hasFeature(k);
    final isOwner = ref.watch(ownerMeProvider).valueOrNull?['canManage'] == true;
    final pending = ref.watch(hrStatsProvider).valueOrNull?.pendingApprovals ?? 0;
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final g = session.group;
    final t = context.t;
    return [
      _Sec(null, [
        _Nav(Icons.dashboard_rounded, t('nav.home'), '/h/home'),
        _Nav(Icons.people_alt_rounded, t('nav.people'), '/h/people'),
        _Nav(Icons.access_time_filled_rounded, t('nav.board'), '/h/attendance'),
        _Nav(Icons.fact_check_rounded, t('nav.approvals'), '/h/approvals', badge: pending),
        _Nav(Icons.notifications_rounded, t('nav.inbox'), '/inbox', badge: unread),
      ]),
      _Sec(t('more.organization'), [
        _Nav(Icons.hub_rounded, t('more.org'), '/org'),
        if (can('employees')) _Nav(Icons.description_rounded, t('ctr.title'), '/h/contracts'),
        if (can('documents')) _Nav(Icons.workspace_premium_rounded, t('cert.title'), '/h/certificates'),
        if (can('departments')) _Nav(Icons.account_tree_rounded, t('module.departments'), '/h/departments'),
        if (can('shifts')) _Nav(Icons.schedule_rounded, t('module.shifts'), '/h/shifts'),
        if (can('leaves')) _Nav(Icons.beach_access_rounded, t('more.leave_types'), '/h/leave-types'),
        if (can('documents')) _Nav(Icons.folder_special_rounded, t('more.doc_types'), '/h/doc-types'),
        _Nav(Icons.people_outline_rounded, t('home.qa.directory'), '/directory'),
      ]),
      _Sec(t('more.work'), [
        if (can('payroll')) _Nav(Icons.payments_rounded, t('module.payroll'), '/h/payroll'),
        if (can('recruitment')) _Nav(Icons.work_outline_rounded, t('module.recruitment'), '/h/recruitment'),
        if (can('talent_pool')) _Nav(Icons.groups_3_rounded, t('module.talent_pool'), '/h/talent'),
        if (can('reviews')) _Nav(Icons.star_rounded, t('me.reviews'), '/h/reviews'),
        if (can('announcements')) _Nav(Icons.campaign_rounded, t('home.announcements'), '/announcements'),
        _Nav(Icons.videocam_rounded, t('meet.title'), '/meetings'),
        _Nav(Icons.auto_awesome_rounded, t('assistant.title'), '/assistant'),
        _Nav(Icons.favorite_rounded, t('kudos.title'), '/kudos'),
        _Nav(Icons.checklist_rounded, t('ob.hr_title'), '/h/onboarding'),
        _Nav(Icons.celebration_rounded, t('me.holidays'), '/holidays'),
        if (company.pointsEnabled) _Nav(Icons.emoji_events_rounded, t('more.rewards'), '/h/rewards'),
        _Nav(Icons.ios_share_rounded, t('more.reports'), '/h/reports'),
      ]),
      if (isOwner || feat(Feat.complaints) || feat(Feat.managerCoach) || feat(Feat.fairDecisions) || feat(Feat.fieldProof) || feat(Feat.careerPath) || feat(Feat.localLaws))
        _Sec(t('prem.section'), [
          if (isOwner) _Nav(Icons.admin_panel_settings_rounded, t('prem.m_owner'), '/owner'),
          if (isOwner && feat(Feat.groupDashboard)) _Nav(Icons.insights_rounded, t('prem.m_pf'), '/portfolio'),
          if (isOwner) _Nav(Icons.report_rounded, t('prem.m_cmp_owner'), '/complaints/owner'),
          if (feat(Feat.complaints)) _Nav(Icons.report_gmailerrorred_rounded, t('prem.m_cmp'), '/complaints'),
          if (feat(Feat.managerCoach)) _Nav(Icons.tips_and_updates_rounded, t('prem.m_coach'), '/coach'),
          if (feat(Feat.fairDecisions)) _Nav(Icons.balance_rounded, t('prem.m_dec'), '/decisions'),
          if (feat(Feat.fieldProof)) _Nav(Icons.pin_drop_rounded, t('prem.m_field'), '/field'),
          if (feat(Feat.careerPath)) _Nav(Icons.stairs_rounded, t('prem.m_career'), '/career-path'),
          if (feat(Feat.localLaws)) _Nav(Icons.gavel_rounded, t('prem.m_law'), '/labor-law'),
        ]),
      if (g != null && (g.isSuperAdmin || g.isOwner))
        _Sec(g.name, [
          _Nav(Icons.business_rounded, t('group.companies'), '/h/group'),
          _Nav(Icons.key_rounded, t('group.access'), '/h/group-access'),
          if (g.isOwner) _Nav(Icons.manage_accounts_rounded, t('hra.title'), '/h/hr-accounts'),
        ]),
      if (user.isAdmin)
        _Sec(t('more.admin'), [
          _Nav(Icons.business_rounded, t('company.title'), '/h/company'),
          _Nav(Icons.auto_awesome_rounded, t('more.policies'), '/h/policies'),
          _Nav(Icons.pin_drop_rounded, t('rules.title'), '/h/attendance-rules'),
          _Nav(Icons.admin_panel_settings_rounded, t('staff.title'), '/h/staff'),
          _Nav(Icons.history_rounded, t('more.audit'), '/h/audit'),
        ]),
      _Sec(null, [_Nav(Icons.settings_rounded, t('me.settings'), '/settings')]),
    ];
  }

  List<_Sec> _employee(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user!;
    final company = session.company!;
    final stats = ref.watch(myStatsProvider).valueOrNull;
    final lead = stats?.isTeamLead ?? user.isTeamLead;
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final t = context.t;
    bool feat(String k) => company.hasFeature(k);
    return [
      _Sec(null, [
        _Nav(Icons.home_rounded, t('nav.home'), '/e/home'),
        _Nav(Icons.access_time_filled_rounded, t('nav.time'), '/e/time'),
        _Nav(Icons.assignment_rounded, t('nav.requests'), '/e/requests'),
        _Nav(Icons.notifications_rounded, t('nav.inbox'), '/e/inbox', badge: unread),
        _Nav(Icons.person_rounded, t('nav.me'), '/e/me'),
      ]),
      _Sec(t('me.my_stuff'), [
        _Nav(Icons.person_outline_rounded, t('me.personal'), '/profile/edit'),
        _Nav(Icons.receipt_long_rounded, t('home.qa.payslips'), '/payslips'),
        _Nav(Icons.folder_copy_rounded, t('home.qa.documents'), '/documents'),
        if (company.pointsEnabled) _Nav(Icons.emoji_events_rounded, t('me.rewards'), '/rewards'),
        _Nav(Icons.timeline_rounded, t('me.career'), '/career'),
        _Nav(Icons.star_rounded, t('me.reviews'), '/my-reviews'),
      ]),
      if (feat(Feat.careerPath) || feat(Feat.fairDecisions) || feat(Feat.fieldProof) || feat(Feat.localLaws) || (lead && (feat(Feat.managerCoach) || feat(Feat.complaints))))
        _Sec(t('prem.section'), [
          if (feat(Feat.careerPath)) _Nav(Icons.stairs_rounded, t('prem.m_career'), '/career-path'),
          if (feat(Feat.fairDecisions)) _Nav(Icons.balance_rounded, t('prem.m_dec'), '/decisions'),
          if (feat(Feat.fieldProof)) _Nav(Icons.pin_drop_rounded, t('prem.m_field'), '/field'),
          if (lead && feat(Feat.managerCoach)) _Nav(Icons.tips_and_updates_rounded, t('prem.m_coach'), '/coach'),
          if (lead && feat(Feat.complaints)) _Nav(Icons.report_gmailerrorred_rounded, t('prem.m_cmp'), '/complaints'),
          if (feat(Feat.localLaws)) _Nav(Icons.gavel_rounded, t('prem.m_law'), '/labor-law'),
        ]),
      _Sec(t('me.company'), [
        if (lead) _Nav(Icons.fact_check_rounded, t('me.team_approvals'), '/approvals', badge: stats?.pendingApprovals ?? 0),
        if (lead) _Nav(Icons.groups_rounded, t('me.my_team'), '/team'),
        _Nav(Icons.people_alt_rounded, t('home.qa.directory'), '/directory'),
        _Nav(Icons.account_tree_rounded, t('me.org'), '/org'),
        _Nav(Icons.campaign_rounded, t('home.announcements'), '/announcements'),
        _Nav(Icons.videocam_rounded, t('meet.title'), '/meetings'),
        _Nav(Icons.auto_awesome_rounded, t('assistant.title'), '/assistant'),
        _Nav(Icons.favorite_rounded, t('kudos.title'), '/kudos'),
        _Nav(Icons.checklist_rounded, t('ob.title'), '/onboarding'),
        _Nav(Icons.celebration_rounded, t('me.holidays'), '/holidays'),
      ]),
      _Sec(null, [_Nav(Icons.settings_rounded, t('me.settings'), '/settings')]),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user!;
    final company = session.company!;
    final sections = user.isHr ? _hr(context, ref) : _employee(context, ref);
    final c = context.colors;
    final canSwitch = session.group?.canSwitch ?? false;

    return Container(
      width: 272,
      decoration: BoxDecoration(color: context.scheme.surface, border: BorderDirectional(end: BorderSide(color: c.border))),
      child: SafeArea(
        child: Column(children: [
          // brand + company
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(children: [
              const BrandMark(size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppConfig.productName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  InkWell(
                    onTap: canSwitch ? () => showCompanySwitcher(rootNavigatorKey.currentContext ?? context, ref) : null,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(child: Text(company.name, style: TextStyle(color: c.subtext, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (canSwitch) Icon(Icons.unfold_more_rounded, size: 15, color: c.subtext),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          const SidebarSearch(),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), children: [
              for (final sec in sections) ...[
                if (sec.items.isNotEmpty) ...[
                  if (sec.title != null) Padding(padding: const EdgeInsets.fromLTRB(10, 16, 10, 6), child: Text(sec.title!.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: c.subtext))),
                  for (final n in sec.items) _Item(nav: n, selected: _active(n.path), onTap: () => router.go(n.path)),
                ],
              ],
            ]),
          ),
          // person + language + sign out
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(children: [
              Avatar(name: user.name, url: user.avatar, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(user.email, style: TextStyle(color: c.subtext, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              IconButton(
                onPressed: () => ref.read(localeProvider.notifier).set(context.isAr ? 'en' : 'ar'),
                icon: const Icon(Icons.language_rounded, size: 20),
              ),
              IconButton(
                onPressed: () async {
                  final ctx = rootNavigatorKey.currentContext ?? context;
                  final title = ctx.t('auth.sign_out');
                  if (await confirmDialog(ctx, title: title, message: ctx.t('me.sign_out_confirm'), danger: true, confirmLabel: title)) {
                    await ref.read(sessionProvider.notifier).signOut();
                  }
                },
                icon: Icon(Icons.logout_rounded, size: 20, color: c.danger),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final _Nav nav;
  final bool selected;
  final VoidCallback onTap;
  const _Item({required this.nav, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = context.scheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: selected ? primary.withValues(alpha: 0.11) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: primary.withValues(alpha: 0.06),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(nav.icon, size: 20, color: selected ? primary : context.colors.subtext),
              const SizedBox(width: 12),
              Expanded(child: Text(nav.label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? primary : context.scheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (nav.badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: context.colors.danger, borderRadius: BorderRadius.circular(20)),
                  child: Text('${nav.badge > 99 ? '99+' : nav.badge}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
