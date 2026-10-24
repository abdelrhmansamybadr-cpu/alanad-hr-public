import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/strings.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import '../common/profile_widgets.dart';
import '../data/providers.dart';
import '../premium/arabic_tools.dart';
import '../premium/premium_common.dart';

/// "Me" tab: profile card, personal shortcuts and settings.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user!;
    final company = session.company!;
    final profile = ref.watch(myProfileProvider);
    final stats = ref.watch(myStatsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('me.title'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myProfileProvider);
          await ref.read(sessionProvider.notifier).refresh();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), physics: const AlwaysScrollableScrollPhysics(), children: [
          ProfileCard(user: user, company: company, employee: profile.valueOrNull),
          const SizedBox(height: 16),
          profile.maybeWhen(
            data: (e) => e == null ? const SizedBox.shrink() : ProfileFacts(employee: e),
            orElse: () => const Skeleton(height: 120, radius: 20),
          ),
          const SizedBox(height: 8),
          SectionHeader(context.t('me.my_stuff')),
          MenuGroup(children: [
            MenuItem(icon: Icons.person_outline_rounded, color: const Color(0xFF6366F1), label: context.t('me.personal'), onTap: () => context.push('/profile/edit')),
            MenuItem(icon: Icons.receipt_long_rounded, color: const Color(0xFF10B981), label: context.t('home.qa.payslips'), onTap: () => context.push('/payslips')),
            MenuItem(icon: Icons.folder_copy_rounded, color: const Color(0xFFF59E0B), label: context.t('home.qa.documents'), onTap: () => context.push('/documents')),
            if (company.pointsEnabled) MenuItem(icon: Icons.emoji_events_rounded, color: const Color(0xFFF59E0B), label: context.t('me.rewards'), onTap: () => context.push('/rewards')),
            MenuItem(icon: Icons.timeline_rounded, color: const Color(0xFF8B5CF6), label: context.t('me.career'), onTap: () => context.push('/career')),
            MenuItem(icon: Icons.star_rounded, color: const Color(0xFFEC4899), label: context.t('me.reviews'), onTap: () => context.push('/my-reviews')),
          ]),
          if (company.hasFeature(Feat.fairDecisions) || company.hasFeature(Feat.fieldProof) || company.hasFeature(Feat.careerPath) || company.hasFeature(Feat.localLaws) || company.hasFeature(Feat.arabicPack) || ((company.hasFeature(Feat.managerCoach) || company.hasFeature(Feat.complaints)) && (stats?.isTeamLead ?? user.isTeamLead))) ...[
            SectionHeader(context.t('prem.section')),
            MenuGroup(children: [
              if (company.hasFeature(Feat.careerPath)) MenuItem(icon: Icons.stairs_rounded, color: const Color(0xFF14B8A6), label: context.t('prem.m_career'), onTap: () => context.push('/career-path')),
              if (company.hasFeature(Feat.fairDecisions)) MenuItem(icon: Icons.balance_rounded, color: const Color(0xFF8B5CF6), label: context.t('prem.m_dec'), onTap: () => context.push('/decisions')),
              if (company.hasFeature(Feat.fieldProof)) MenuItem(icon: Icons.pin_drop_rounded, color: const Color(0xFF0EA5E9), label: context.t('prem.m_field'), onTap: () => context.push('/field')),
              if (company.hasFeature(Feat.managerCoach) && (stats?.isTeamLead ?? user.isTeamLead)) MenuItem(icon: Icons.tips_and_updates_rounded, color: const Color(0xFFF59E0B), label: context.t('prem.m_coach'), onTap: () => context.push('/coach')),
              if (company.hasFeature(Feat.complaints) && (stats?.isTeamLead ?? user.isTeamLead)) MenuItem(icon: Icons.report_gmailerrorred_rounded, color: const Color(0xFFEF4444), label: context.t('prem.m_cmp'), onTap: () => context.push('/complaints')),
              if (company.hasFeature(Feat.localLaws)) MenuItem(icon: Icons.gavel_rounded, color: const Color(0xFF64748B), label: context.t('prem.m_law'), onTap: () => context.push('/labor-law')),
              if (company.hasFeature(Feat.arabicPack)) MenuItem(icon: Icons.description_rounded, color: const Color(0xFF10B981), label: context.t('prem.m_letters'), onTap: () => showLettersSheet(context)),
              if (company.hasFeature(Feat.arabicPack)) MenuItem(icon: Icons.mic_rounded, color: const Color(0xFFEC4899), label: context.t('prem.m_voice'), onTap: () => showVoiceSheet(context)),
            ]),
          ],
          SectionHeader(context.t('me.company')),
          MenuGroup(children: [
            if (stats?.isTeamLead ?? user.isTeamLead)
              MenuItem(
                icon: Icons.fact_check_rounded,
                color: const Color(0xFF8B5CF6),
                label: context.t('me.team_approvals'),
                badge: (stats?.pendingApprovals ?? 0) > 0 ? '${stats!.pendingApprovals}' : null,
                onTap: () => context.push('/approvals'),
              ),
            if (stats?.isTeamLead ?? user.isTeamLead) MenuItem(icon: Icons.groups_rounded, color: const Color(0xFF14B8A6), label: context.t('me.my_team'), onTap: () => context.push('/team')),
            MenuItem(icon: Icons.people_alt_rounded, color: const Color(0xFF0EA5E9), label: context.t('home.qa.directory'), onTap: () => context.push('/directory')),
            MenuItem(icon: Icons.account_tree_rounded, color: const Color(0xFF14B8A6), label: context.t('me.org'), onTap: () => context.push('/org')),
            MenuItem(icon: Icons.campaign_rounded, color: const Color(0xFFEF4444), label: context.t('home.announcements'), onTap: () => context.push('/announcements')),
            MenuItem(icon: Icons.videocam_rounded, color: const Color(0xFF00617A), label: context.t('meet.title'), onTap: () => context.push('/meetings')),
            MenuItem(icon: Icons.auto_awesome_rounded, color: const Color(0xFF6366F1), label: context.t('assistant.title'), onTap: () => context.push('/assistant')),
            MenuItem(icon: Icons.favorite_rounded, color: const Color(0xFFEC4899), label: context.t('kudos.title'), onTap: () => context.push('/kudos')),
            MenuItem(icon: Icons.checklist_rounded, color: const Color(0xFF22C55E), label: context.t('ob.title'), onTap: () => context.push('/onboarding')),
            MenuItem(icon: Icons.celebration_rounded, color: const Color(0xFFF97316), label: context.t('me.holidays'), onTap: () => context.push('/holidays')),
          ]),
          SectionHeader(context.t('me.app')),
          MenuGroup(children: [
            MenuItem(icon: Icons.settings_rounded, color: const Color(0xFF64748B), label: context.t('me.settings'), onTap: () => context.push('/settings')),
          ]),
          const SizedBox(height: 22),
          const SignOutButton(),
        ]),
      ),
    );
  }
}
