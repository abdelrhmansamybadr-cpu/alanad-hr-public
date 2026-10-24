import '../features/assistant/assistant.dart';
import '../features/kudos/kudos.dart';
import '../features/onboarding/onboarding.dart';
import '../features/onboarding/onboarding_flow.dart';
import 'package:go_router/go_router.dart';

import '../features/common/announcements_screen.dart';
import '../features/common/career_org.dart';
import '../features/rewards/rewards_screen.dart';
import '../features/common/approvals_screen.dart';
import '../features/common/directory_screen.dart';
import '../features/common/documents_screen.dart';
import '../features/common/payslips_screen.dart';
import '../features/common/reviews_screen.dart';
import '../features/common/settings_screen.dart';
import '../features/employee/inbox_screen.dart';
import '../features/meetings/meeting_room_screen.dart';
import '../features/meetings/meetings_list_screen.dart';
import '../features/premium/career_screens.dart';
import '../features/premium/complaints_screens.dart';
import '../features/premium/coach_screen.dart';
import '../features/premium/decisions_screen.dart';
import '../features/premium/field_screens.dart';
import '../features/premium/labor_law_screen.dart';
import '../features/premium/owner_screen.dart';
import '../features/premium/portfolio_screen.dart';

/// Pages reachable by both employees and HR.
List<RouteBase> sharedRoutes() => [
      GoRoute(path: '/payslips', builder: (_, __) => const PayslipsScreen()),
      GoRoute(path: '/documents', builder: (_, __) => const DocumentsScreen()),
      GoRoute(path: '/directory', builder: (_, __) => const DirectoryScreen()),
      GoRoute(path: '/announcements', builder: (_, __) => const AnnouncementsScreen()),
      GoRoute(path: '/holidays', builder: (_, __) => const HolidaysScreen()),
      GoRoute(path: '/profile/edit', builder: (_, __) => const ProfileEditScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/approvals', builder: (_, __) => const ApprovalsScreen()),
      GoRoute(path: '/team', builder: (_, __) => const TeamScreen()),
      GoRoute(path: '/my-reviews', builder: (_, __) => const MyReviewsScreen()),
      GoRoute(path: '/rewards', builder: (_, __) => const RewardsScreen()),
      GoRoute(path: '/career', builder: (_, __) => const CareerScreen()),
      GoRoute(path: '/org', builder: (_, __) => const OrgScreen()),
      GoRoute(path: '/assistant', builder: (_, __) => const AssistantScreen()),
      GoRoute(path: '/kudos', builder: (_, __) => const KudosScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/onb-step/:key', builder: (_, s) => ObStepScreen(stepKey: s.pathParameters['key'] ?? 'contract')),
      GoRoute(path: '/onboarding/:id', builder: (_, s) => OnboardingScreen(employeeId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0, name: s.extra is String ? s.extra as String : null)),
      GoRoute(path: '/inbox', builder: (_, __) => const InboxScreen(showBack: true)),
      GoRoute(path: '/owner', builder: (_, __) => const OwnerScreen()),
      GoRoute(path: '/labor-law', builder: (_, __) => const LaborLawScreen()),
      GoRoute(path: '/decisions', builder: (_, __) => const DecisionsScreen()),
      GoRoute(path: '/complaints', builder: (_, __) => const ComplaintsScreen()),
      GoRoute(path: '/complaints/owner', builder: (_, __) => const ComplaintsScreen(ownerView: true)),
      GoRoute(path: '/complaint/:id', builder: (_, st) => ComplaintDetailScreen(id: int.tryParse(st.pathParameters['id'] ?? '') ?? 0)),
      GoRoute(path: '/coach', builder: (_, __) => const CoachScreen()),
      GoRoute(path: '/portfolio', builder: (_, __) => const PortfolioScreen()),
      GoRoute(path: '/field', builder: (_, __) => const FieldVisitsScreen()),
      GoRoute(path: '/field/active/:id', builder: (_, s) => FieldActiveScreen(id: int.tryParse(s.pathParameters['id'] ?? '') ?? 0)),
      GoRoute(path: '/field/visit/:id', builder: (_, s) => FieldVisitScreen(id: int.tryParse(s.pathParameters['id'] ?? '') ?? 0)),
      GoRoute(path: '/career-path', builder: (_, __) => const CareerPathScreen()),
      GoRoute(path: '/career-ladder', builder: (_, __) => const CareerLadderScreen()),
      GoRoute(path: '/meetings', builder: (_, __) => const MeetingsScreen()),
      GoRoute(path: '/meeting/:id', builder: (_, s) => MeetingRoomScreen(id: int.tryParse(s.pathParameters['id'] ?? '') ?? 0)),
    ];
