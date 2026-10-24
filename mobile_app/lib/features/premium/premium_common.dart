import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';

/// 'local_laws' -> 'localLaws' (the server sends switches with camelCase keys).
String camelKey(String k) {
  final parts = k.split('_');
  return parts.first + parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
}

/// Premium feature keys as the app reads them from company.features.
class Feat {
  static const localLaws = 'localLaws';
  static const arabicPack = 'arabicPack';
  static const fairDecisions = 'fairDecisions';
  static const groupDashboard = 'groupDashboard';
  static const managerCoach = 'managerCoach';
  static const fieldProof = 'fieldProof';
  static const careerPath = 'careerPath';
  static const approvalChain = 'approvalChain';
  static const complaints = 'complaints';
}

extension FeatureAccess on WidgetRef {
  /// Is the premium feature on for the company the person is working in right now?
  bool feature(String key) => watch(sessionProvider).company?.hasFeature(key) ?? false;
}

/// "Does this account control feature switches?" Only asked of HR accounts (others would just get 403).
final ownerMeProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionProvider);
  if (!s.isSignedIn || s.user?.role == 'employee') return {'canManage': false};
  try {
    return asMap(await ref.read(apiProvider).get('/owner/me'));
  } catch (_) {
    return {'canManage': false};
  }
});

/// Title / description of a record that carries titleEn / titleAr style fields, in the app language.
String pick(BuildContext context, Map m, String base) {
  final ar = jStrN(m, '${base}Ar');
  final en = jStrN(m, '${base}En');
  return context.isAr ? (ar ?? en ?? '') : (en ?? ar ?? '');
}

DateTime? parseUtc(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s.contains('T') ? s : '${s.replaceFirst(' ', 'T')}Z')?.toLocal();
}

String money(num v, [String cur = '']) {
  final s = v.abs() >= 1000 ? v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2) : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
  final withCommas = s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(\.|$))'), (m) => '${m[1]},');
  return cur.isEmpty ? withCommas : '$withCommas $cur';
}

/// A small, consistent "this feature is switched off" state (used when the server answers feature_disabled).
class FeatureOff extends StatelessWidget {
  const FeatureOff({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.toggle_off_rounded, size: 56, color: context.colors.subtext),
            const SizedBox(height: 12),
            Text(context.t('prem.off_title'), style: context.text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(context.t('prem.off_hint'), style: TextStyle(color: context.colors.subtext), textAlign: TextAlign.center),
          ]),
        ),
      );
}

bool isFeatureOff(Object e) => e is ApiException && (e.status == 403) && e.message.contains('turned off');
