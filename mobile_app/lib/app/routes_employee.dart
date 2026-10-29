import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n/strings.dart';
import '../core/ui/responsive.dart';
import 'floating_nav.dart';
import '../features/data/providers.dart';
import '../features/employee/home_screen.dart';
import '../features/employee/inbox_screen.dart';
import '../features/employee/location_tracker.dart';
import '../features/employee/me_screen.dart';
import '../features/employee/requests_screen.dart';
import '../features/employee/time_screen.dart';

/// The 5-tab employee app: Home · Time · Requests · Inbox · Me.
RouteBase employeeShellRoute() => StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => EmployeeShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/e/home', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: EmployeeHome()))]),
        StatefulShellBranch(routes: [GoRoute(path: '/e/time', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: TimeScreen()))]),
        StatefulShellBranch(routes: [GoRoute(path: '/e/requests', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: RequestsScreen()))]),
        StatefulShellBranch(routes: [GoRoute(path: '/e/inbox', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: InboxScreen()))]),
        StatefulShellBranch(routes: [GoRoute(path: '/e/me', builder: (_, __) => const DesktopPage(maxWidth: 1180, child: MeScreen()))]),
      ],
    );

/// Extra pushed pages only employees use (none yet — shared pages live in routes_shared).
List<RouteBase> employeeRoutes() => const [];

class EmployeeShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const EmployeeShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    return Scaffold(
      body: LocationTracker(child: shell),
      bottomNavigationBar: context.isDesktop ? null : FloatingNavBar(
        index: shell.currentIndex,
        onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        items: [
          FloatingNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: context.t('nav.home')),
          FloatingNavItem(icon: Icons.access_time_outlined, selectedIcon: Icons.access_time_filled_rounded, label: context.t('nav.time')),
          FloatingNavItem(icon: Icons.assignment_outlined, selectedIcon: Icons.assignment_rounded, label: context.t('nav.requests')),
          FloatingNavItem(icon: Icons.notifications_none_rounded, selectedIcon: Icons.notifications_rounded, label: context.t('nav.inbox'), badge: unread),
          FloatingNavItem(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: context.t('nav.me')),
        ],
      ),
    );
  }
}
