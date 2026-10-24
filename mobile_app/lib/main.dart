import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/i18n/strings.dart';
import 'core/push/push_service.dart';
import 'core/session/session.dart';
import 'core/update/app_updater.dart';
import 'features/meetings/meeting_ring.dart';
import 'features/onboarding/onboarding_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await PushService.init();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(const ProviderScope(child: AlAnadApp()));
}

class AlAnadApp extends ConsumerWidget {
  const AlAnadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    final brand = ref.watch(brandProvider);
    final mode = ref.watch(themeModeProvider);
    final ar = locale.languageCode == 'ar';

    return MaterialApp.router(
      title: 'Al Anad HR',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      theme: buildTheme(brand, Brightness.light, arabic: ar),
      darkTheme: buildTheme(brand, Brightness.dark, arabic: ar),
      themeMode: mode,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Theme.of(context).colorScheme.surface),
          child: AppEventsHost(child: ObFlowWatcher(child: UpdateGate(child: child ?? const SizedBox()))),
        );
      },
    );
  }
}
