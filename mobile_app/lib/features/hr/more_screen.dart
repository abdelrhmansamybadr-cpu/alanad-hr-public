import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/strings.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import '../common/profile_widgets.dart';
import '../group/group_screens.dart';
import '../premium/arabic_tools.dart';
import '../premium/premium_common.dart';

/// HR "More" tab: every management area, filtered by the user's module permissions.
class HrMoreScreen extends ConsumerWidget {
  const HrMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user!;
    final company = session.company!;

    bool can(String m) => user.canUse(m) && company.hasModule(m);

    MenuItem item(String module, IconData icon, Color color, String label, String path) => MenuItem(icon: icon, color: color, label: label, onTap: () => context.push(path));
    final isOwner = ref.watch(ownerMeProvider).valueOrNull?['canManage'] == true;
    bool feat(String k) => company.hasFeature(k);
    // Premium features: shown only while the owner has switched them on (the server enforces it as well)
    final smart = <Widget>[
      if (isOwner) item('owner', Icons.admin_panel_settings_rounded, const Color(0xFFEF4444), context.t('prem.m_owner'), '/owner'),
      if (isOwner && feat(Feat.groupDashboard)) item('portfolio', Icons.insights_rounded, const Color(0xFF00617A), context.t('prem.m_pf'), '/portfolio'),
      if (isOwner) item('complaints-owner', Icons.report_rounded, const Color(0xFF8B5CF6), context.t('prem.m_cmp_owner'), '/complaints/owner'),
      if (feat(Feat.complaints)) item('complaints', Icons.report_gmailerrorred_rounded, const Color(0xFFEF4444), context.t('prem.m_cmp'), '/complaints'),
      if (feat(Feat.managerCoach)) item('coach', Icons.tips_and_updates_rounded, const Color(0xFFF59E0B), context.t('prem.m_coach'), '/coach'),
      if (feat(Feat.fairDecisions)) item('decisions', Icons.balance_rounded, const Color(0xFF8B5CF6), context.t('prem.m_dec'), '/decisions'),
      if (feat(Feat.fieldProof)) item('field', Icons.pin_drop_rounded, const Color(0xFF0EA5E9), context.t('prem.m_field'), '/field'),
      if (feat(Feat.careerPath)) item('career-path', Icons.stairs_rounded, const Color(0xFF14B8A6), context.t('prem.m_career'), '/career-path'),
      if (feat(Feat.localLaws)) item('law', Icons.gavel_rounded, const Color(0xFF64748B), context.t('prem.m_law'), '/labor-law'),
      if (feat(Feat.arabicPack)) MenuItem(icon: Icons.description_rounded, color: const Color(0xFF10B981), label: context.t('prem.m_letters'), onTap: () => showLettersSheet(context)),
      if (feat(Feat.arabicPack)) MenuItem(icon: Icons.mic_rounded, color: const Color(0xFFEC4899), label: context.t('prem.m_voice'), onTap: () => showVoiceSheet(context)),
    ];

    final people = <Widget>[
      item('org', Icons.hub_rounded, const Color(0xFF14B8A6), context.t('more.org'), '/org'),
      if (can('departments')) item('departments', Icons.account_tree_rounded, const Color(0xFF6366F1), context.t('module.departments'), '/h/departments'),
      if (can('shifts')) item('shifts', Icons.schedule_rounded, const Color(0xFF0EA5E9), context.t('module.shifts'), '/h/shifts'),
      if (can('leaves')) item('leaves', Icons.beach_access_rounded, const Color(0xFF10B981), context.t('more.leave_types'), '/h/leave-types'),
      if (can('documents')) item('documents', Icons.folder_special_rounded, const Color(0xFFF59E0B), context.t('more.doc_types'), '/h/doc-types'),
    ];
    final work = <Widget>[
      if (can('payroll')) item('payroll', Icons.payments_rounded, const Color(0xFF10B981), context.t('module.payroll'), '/h/payroll'),
      if (can('recruitment')) item('recruitment', Icons.work_outline_rounded, const Color(0xFF8B5CF6), context.t('module.recruitment'), '/h/recruitment'),
      if (can('talent_pool')) item('talent_pool', Icons.groups_3_rounded, const Color(0xFF14B8A6), context.t('module.talent_pool'), '/h/talent'),
      if (can('reviews')) item('reviews', Icons.star_rounded, const Color(0xFFEC4899), context.t('me.reviews'), '/h/reviews'),
      if (can('announcements')) item('announcements', Icons.campaign_rounded, const Color(0xFFEF4444), context.t('home.announcements'), '/announcements'),
      item('meetings', Icons.videocam_rounded, const Color(0xFF00617A), context.t('meet.title'), '/meetings'),
      item('assistant', Icons.auto_awesome_rounded, const Color(0xFF6366F1), context.t('assistant.title'), '/assistant'),
      item('kudos', Icons.favorite_rounded, const Color(0xFFEC4899), context.t('kudos.title'), '/kudos'),
      item('onboarding', Icons.checklist_rounded, const Color(0xFF22C55E), context.t('ob.hr_title'), '/h/onboarding'),
      item('holidays', Icons.celebration_rounded, const Color(0xFFF97316), context.t('me.holidays'), '/holidays'),
      if (company.pointsEnabled) item('rewards', Icons.emoji_events_rounded, const Color(0xFFF59E0B), context.t('more.rewards'), '/h/rewards'),
      item('reports', Icons.ios_share_rounded, const Color(0xFF0EA5E9), context.t('more.reports'), '/h/reports'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.t('nav.more'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        ProfileCard(user: user, company: company),
        const SizedBox(height: 8),
        // Company group: switch company, and (super admin) manage the companies and who may enter them
        if (session.group != null && (session.group!.canSwitch || session.group!.isSuperAdmin || session.group!.isOwner)) ...[
          SectionHeader(session.group!.name),
          MenuGroup(children: [
            if (session.group!.canSwitch) MenuItem(icon: Icons.swap_horiz_rounded, color: const Color(0xFF00617A), label: context.t('group.switch_company'), onTap: () => showCompanySwitcher(context, ref)),
            if (session.group!.isSuperAdmin || session.group!.isOwner) item('group', Icons.business_rounded, const Color(0xFF00617A), context.t('group.companies'), '/h/group'),
            if (session.group!.isSuperAdmin || session.group!.isOwner) item('group-access', Icons.key_rounded, const Color(0xFFC88453), context.t('group.access'), '/h/group-access'),
          ]),
        ],
        if (smart.isNotEmpty) ...[SectionHeader(context.t('prem.section')), MenuGroup(children: smart)],
        if (work.isNotEmpty) ...[SectionHeader(context.t('more.work')), MenuGroup(children: work)],
        if (people.isNotEmpty) ...[SectionHeader(context.t('more.organization')), MenuGroup(children: people)],
        if (user.isAdmin) ...[
          SectionHeader(context.t('more.admin')),
          MenuGroup(children: [
            item('company', Icons.business_rounded, const Color(0xFF6366F1), context.t('company.title'), '/h/company'),
            item('policies', Icons.auto_awesome_rounded, const Color(0xFF8B5CF6), context.t('more.policies'), '/h/policies'),
            item('rules', Icons.pin_drop_rounded, const Color(0xFF0EA5E9), context.t('rules.title'), '/h/attendance-rules'),
            item('staff', Icons.admin_panel_settings_rounded, const Color(0xFFEF4444), context.t('staff.title'), '/h/staff'),
            item('audit', Icons.history_rounded, const Color(0xFF64748B), context.t('more.audit'), '/h/audit'),
          ]),
        ],
        SectionHeader(context.t('me.app')),
        MenuGroup(children: [
          item('directory', Icons.people_alt_rounded, const Color(0xFF0EA5E9), context.t('home.qa.directory'), '/directory'),
          item('inbox', Icons.notifications_rounded, const Color(0xFFF59E0B), context.t('nav.inbox'), '/inbox'),
          item('settings', Icons.settings_rounded, const Color(0xFF64748B), context.t('me.settings'), '/settings'),
        ]),
        const SizedBox(height: 22),
        const SignOutButton(),
      ]),
    );
  }
}
