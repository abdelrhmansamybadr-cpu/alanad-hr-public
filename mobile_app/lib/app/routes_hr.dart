import '../core/ui/responsive.dart';
import '../features/hr/loans.dart';
import '../features/onboarding/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n/strings.dart';
import 'floating_nav.dart';
import '../features/common/approvals_screen.dart';
import '../features/common/documents_screen.dart';
import '../features/data/providers.dart';
import '../features/hr/attendance_board.dart';
import '../features/hr/career_actions.dart';
import '../features/hr/company_settings.dart';
import '../features/hr/admin_tools.dart';
import '../features/hr/department_detail.dart';
import '../features/hr/policies.dart';
import '../features/hr/hr_home.dart';
import '../features/hr/more_screen.dart';
import '../features/hr/org.dart';
import '../features/hr/payroll.dart';
import '../features/hr/people.dart';
import '../features/hr/recruitment.dart';
import '../features/hr/reviews_manage.dart';
import '../features/hr/staff.dart';
import '../features/group/group_screens.dart';
import '../features/certificates/cert_designer.dart';
import '../features/certificates/cert_model.dart';
import '../features/certificates/cert_screens.dart';
import '../features/certificates/contract_widgets.dart';

/// The 5-tab HR app: Home · People · Attendance · Approvals · More.
RouteBase hrShellRoute() => StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HrShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/h/home', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: HrHome()))]),
        StatefulShellBranch(routes: [GoRoute(path: '/h/people', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: PeopleScreen()))]),
        StatefulShellBranch(routes: [GoRoute(path: '/h/attendance', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: AttendanceBoardScreen()))]),
        StatefulShellBranch(routes: [GoRoute(path: '/h/approvals', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: ApprovalsScreen(asTab: true)))]),
        StatefulShellBranch(routes: [GoRoute(path: '/h/more', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: HrMoreScreen()))]),
      ],
    );

int _id(GoRouterState s) => int.tryParse(s.pathParameters['id'] ?? '') ?? 0;

List<RouteBase> hrRoutes() => [
      GoRoute(path: '/h/employee/new', builder: (_, s) => EmployeeFormScreen(initialDepartment: int.tryParse(s.uri.queryParameters['dept'] ?? ''))),
      GoRoute(path: '/h/employee/:id', builder: (_, s) => EmployeeDetailScreen(id: _id(s))),
      GoRoute(path: '/h/employee/:id/edit', builder: (_, s) => EmployeeFormScreen(id: _id(s))),
      GoRoute(path: '/h/employee/:id/documents', builder: (_, s) => DocumentsScreen(employeeId: _id(s), title: s.uri.queryParameters['name'])),
      GoRoute(path: '/h/employee/:id/points', builder: (_, s) => EmployeePointsScreen(employeeId: _id(s), name: s.extra is String ? s.extra as String : '')),
      GoRoute(path: '/h/department/:id', builder: (_, s) => DepartmentDetailScreen(id: _id(s))),
      GoRoute(path: '/h/policies', builder: (_, s) => PoliciesScreen(initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0)),
      GoRoute(path: '/h/onboarding', builder: (_, __) => const OnboardingOverviewScreen()),
      GoRoute(path: '/h/rewards', builder: (_, __) => const HrRewardsScreen()),
      GoRoute(path: '/h/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(path: '/h/audit', builder: (_, __) => const AuditScreen()),
      GoRoute(path: '/h/departments', builder: (_, __) => const DepartmentsScreen()),
      GoRoute(path: '/h/shifts', builder: (_, __) => const ShiftsScreen()),
      GoRoute(path: '/h/leave-types', builder: (_, __) => const LeaveTypesScreen()),
      GoRoute(path: '/h/doc-types', builder: (_, __) => const DocTypesScreen()),
      GoRoute(path: '/h/payroll', builder: (_, __) => const PayrollScreen()),
      GoRoute(path: '/h/loans', builder: (_, __) => const LoansScreen()),
      GoRoute(path: '/h/recruitment', builder: (_, __) => const RecruitmentScreen()),
      GoRoute(path: '/h/talent', builder: (_, __) => const TalentPoolScreen()),
      GoRoute(path: '/h/reviews', builder: (_, __) => const ReviewsManageScreen()),
      GoRoute(path: '/h/staff', builder: (_, __) => const StaffScreen()),
      GoRoute(path: '/h/group', builder: (_, __) => const GroupCompaniesScreen()),
      GoRoute(path: '/h/group-access', builder: (_, __) => const GroupAccessScreen()),
      GoRoute(path: '/h/hr-accounts', builder: (_, __) => const HrAccountsScreen()),
      GoRoute(path: '/h/certificates', builder: (_, s) => CertificatesScreen(employeeId: int.tryParse(s.uri.queryParameters['employee'] ?? ''))),
      GoRoute(path: '/h/certificates/design', builder: (_, s) => CertDesignerScreen(initial: s.extra is CertTemplate ? s.extra as CertTemplate : CertTemplate())),
      GoRoute(path: '/h/contracts', builder: (_, __) => const ContractsScreen()),
      GoRoute(path: '/h/company', builder: (_, __) => const CompanySettingsScreen()),
      GoRoute(path: '/h/attendance-rules', builder: (_, __) => const AttendanceRulesScreen()),
    ];

class HrShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const HrShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(hrStatsProvider).valueOrNull?.pendingApprovals ?? 0;
    return Scaffold(
      body: shell,
      bottomNavigationBar: context.isDesktop ? null : FloatingNavBar(
        index: shell.currentIndex,
        onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        items: [
          FloatingNavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, label: context.t('nav.home')),
          FloatingNavItem(icon: Icons.people_outline_rounded, selectedIcon: Icons.people_alt_rounded, label: context.t('nav.people')),
          FloatingNavItem(icon: Icons.access_time_outlined, selectedIcon: Icons.access_time_filled_rounded, label: context.t('nav.board')),
          FloatingNavItem(icon: Icons.fact_check_outlined, selectedIcon: Icons.fact_check_rounded, label: context.t('nav.approvals'), badge: pending),
          FloatingNavItem(icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view_rounded, label: context.t('nav.more')),
        ],
      ),
    );
  }
}
