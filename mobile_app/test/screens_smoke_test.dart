// Opens every employee and HR screen of the real app against a running backend, in English and Arabic on a
// phone-sized screen, and fails on: an error state, a "Forbidden" message, or any exception (including layout overflow).
//
//   flutter test test/screens_smoke_test.dart --dart-define=API_BASE=http://127.0.0.1:8099
//
// Uses the demo accounts of the local test rig (php-backend/tests); the whole file is skipped when the server is not running.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_mobile_app/app/router.dart';
import 'package:hr_mobile_app/core/config.dart';
import 'package:hr_mobile_app/core/ui/widgets.dart';
import 'package:hr_mobile_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _employee = ('mona.fresh@demo.test', 'Pass12345!');
const _hr = ('dana@demo.test', 'Demo12345!');

const _employeeScreens = [
  '/e/home', '/e/time', '/e/requests', '/e/inbox', '/e/me',
  '/payslips', '/documents', '/directory', '/announcements', '/holidays', '/profile/edit', '/settings', '/my-reviews',
  '/rewards', '/career', '/org', '/assistant', '/kudos', '/onboarding', '/onb-step/contract', '/onb-step/details', '/onb-step/policies',
];
const _hrScreens = [
  '/h/home', '/h/people', '/h/attendance', '/h/approvals', '/h/more',
  '/h/departments', '/h/shifts', '/h/leave-types', '/h/doc-types', '/h/payroll', '/h/loans', '/h/recruitment', '/h/talent',
  '/h/reviews', '/h/staff', '/h/company', '/h/attendance-rules', '/h/rewards', '/h/reports', '/h/audit', '/h/onboarding',
  '/payslips', '/directory', '/announcements', '/holidays', '/settings', '/org', '/assistant', '/kudos',
];

Future<String?> _login((String, String) who) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    final req = await c.postUrl(Uri.parse('${AppConfig.baseUrl}/api/auth/login'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'email': who.$1, 'password': who.$2}));
    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join());
    c.close();
    return body is Map ? body['token'] as String? : null;
  } catch (_) {
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real HTTP by default

  String? employeeToken;
  String? hrToken;
  setUpAll(() async {
    // The test environment draws text in a font whose letters are all as wide as they are tall, so rows of text would
    // "overflow" here that fit fine on a phone. Use a real font (Segoe UI also covers Arabic) under the names the app's
    // theme falls back to. On a machine without it the layout checks are looser/stricter, but everything else still runs.
    // google_fonts asks for names like "Inter_regular" and "Inter_700".
    final regular = File(r'C:\Windows\Fonts\segoeui.ttf');
    final bold = File(r'C:\Windows\Fonts\segoeuib.ttf');
    if (regular.existsSync() && bold.existsSync()) {
      final r = await regular.readAsBytes();
      final b = await bold.readAsBytes();
      for (final family in const ['Inter', 'Cairo']) {
        for (final variant in const ['regular', '100', '200', '300', '400', '500', '600', '700', '800', '900']) {
          final heavy = const ['600', '700', '800', '900'].contains(variant);
          final bytes = heavy ? b : r;
          await (FontLoader('${family}_$variant')..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
        }
      }
    }
    employeeToken = await _login(_employee);
    hrToken = await _login(_hr);
  });

  void suite(String role, (String, String) who, List<String> paths) {
    for (final lang in const ['en', 'ar']) {
      for (final path in paths) {
        testWidgets('$role · $lang · $path', (tester) async {
          final token = role == 'employee' ? employeeToken : hrToken;
          if (token == null) {
            // ignore: avoid_print
            print('SKIPPED: the test server is not reachable at ${AppConfig.baseUrl}');
            return;
          }
          FlutterSecureStorage.setMockInitialValues({'session_token_v2': token});
          SharedPreferences.setMockInitialValues({'lang': lang});
          tester.view.physicalSize = const Size(1080, 2340);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          final container = ProviderContainer();
          final reports = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (d) {
            reports.add(d.toDiagnosticsNode().toStringDeep(minLevel: DiagnosticLevel.debug));
            previous?.call(d);
          };
          addTearDown(() => FlutterError.onError = previous);
          await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AlAnadApp()));

          Future<void> settle([int rounds = 10]) async {
            for (var i = 0; i < rounds; i++) {
              await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
              await tester.pump(const Duration(milliseconds: 120));
            }
          }

          await settle(8); // sign in from the stored token and land on the role's home
          container.read(routerProvider).go(path);
          await settle(12);

          final problems = <String>[];
          Object? e;
          while ((e = tester.takeException()) != null) {
            problems.add(e.toString().split('\n').first);
          }
          if (reports.isNotEmpty) {
            // the first full report names the widget that broke (its "creator" chain)
            final r = reports.first.split('\n');
            final creator = r.indexWhere((l) => l.contains('creator:'));
            problems.add('layout report: ${creator >= 0 ? r.skip(creator).take(5).map((l) => l.trim()).join(' ') : r.take(6).join(' ')}');
          }
          final landed = container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
          if (landed != path) problems.add('the app ended up on $landed instead of $path');
          if (find.byType(Scaffold).evaluate().isEmpty) problems.add('nothing was drawn');
          if (find.byType(ErrorState).evaluate().isNotEmpty) problems.add('the screen shows an error state');
          if (find.textContaining(RegExp('Forbidden|Insufficient permissions|غير مصرح')).evaluate().isNotEmpty) problems.add('the screen shows "Forbidden"');
          expect(problems, isEmpty, reason: '$role/$lang $path -> ${problems.join(' | ')}');

          await tester.pumpWidget(const SizedBox()); // dispose the screens
          container.dispose(); // stops the polling streams
          await tester.pump(const Duration(minutes: 3)); // let any remaining timers run out
        });
      }
    }
  }

  suite('employee', _employee, _employeeScreens);
  suite('hr', _hr, _hrScreens);
}
