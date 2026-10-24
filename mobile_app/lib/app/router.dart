import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n/strings.dart';
import 'theme.dart';
import '../core/session/session.dart';
import '../core/ui/widgets.dart';
import '../features/auth/auth_screens.dart';
import '../features/group/group_screens.dart';
import 'routes_employee.dart';
import 'routes_hr.dart';
import 'routes_shared.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

Map<String, dynamic> _extra(GoRouterState s) => s.extra is Map ? Map<String, dynamic>.from(s.extra as Map) : <String, dynamic>{};

final routerProvider = Provider<GoRouter>((ref) {
  // One router for the whole app lifetime; it re-evaluates redirects when the session changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final s = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/welcome' || loc.startsWith('/auth');

      switch (s.status) {
        case SessionStatus.loading:
        case SessionStatus.offline:
          return loc == '/splash' ? null : '/splash';
        case SessionStatus.signedOut:
          return isAuthRoute ? null : '/welcome';
        case SessionStatus.signedIn:
          final home = s.user!.isHr ? '/h/home' : '/e/home';
          if (isAuthRoute || loc == '/splash' || loc == '/') return home;
          // Keep each role inside its own area
          if (loc.startsWith('/h/') && !s.user!.isHr) return '/e/home';
          if (loc.startsWith('/e/') && s.user!.isHr) return '/h/home';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => null, builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      // Neutral screen used while the company changes (closes the old company's screens and drops their data)
      GoRoute(path: '/switching', builder: (_, s) => SwitchingScreen(name: s.extra is String ? s.extra as String : null)),
      GoRoute(path: '/auth/email', builder: (_, __) => const EmailScreen()),
      GoRoute(
        path: '/auth/password',
        builder: (_, s) => PasswordScreen(email: _extra(s)['email'] ?? '', hr: _extra(s)['hr'] == true),
      ),
      GoRoute(path: '/auth/activate', builder: (_, s) => ActivateScreen(email: _extra(s)['email'] ?? '')),
      GoRoute(path: '/auth/reset', builder: (_, s) => ResetScreen(email: _extra(s)['email'] ?? '')),
      employeeShellRoute(),
      hrShellRoute(),
      ...sharedRoutes(),
      ...employeeRoutes(),
      ...hrRoutes(),
    ],
  );
});

/// Shown while the saved session is being checked, or when the server cannot be reached.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(sessionProvider).status == SessionStatus.offline;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: brandGradient(context)),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(size: 84, onDark: true),
            const SizedBox(height: 28),
            if (!offline)
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
            else ...[
              const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 30),
              const SizedBox(height: 10),
              Text(context.t('common.offline'), style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => ref.read(sessionProvider.notifier).restore(),
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: context.scheme.primary, minimumSize: const Size(160, 48)),
                child: Text(context.t('common.retry')),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
