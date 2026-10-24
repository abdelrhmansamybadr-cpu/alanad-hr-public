import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/ui/widgets.dart';

class WellbeingPerson {
  final int employeeId;
  final String name;
  final String? avatar;
  final String detail;
  const WellbeingPerson({required this.employeeId, required this.name, this.avatar, this.detail = ''});
}

class WellbeingSignal {
  final String key;
  final List<WellbeingPerson> people;
  const WellbeingSignal(this.key, this.people);
}

/// Quiet signals that someone may need a conversation (HR only).
final wellbeingProvider = FutureProvider.autoDispose<List<WellbeingSignal>>((ref) async {
  final m = asMap(await ref.read(apiProvider).get('/stats/wellbeing'));
  return [
    for (final s in asMapList(m['signals']))
      WellbeingSignal(jStr(s, 'key'), [for (final e in asMapList(s['employees'])) WellbeingPerson(employeeId: jInt(e, 'employeeId'), name: jStr(e, 'name'), avatar: jStrN(e, 'avatar'), detail: jStr(e, 'detail'))]),
  ];
});

IconData _icon(String key) => switch (key) {
      'no_leave' => Icons.beach_access_rounded,
      'overtime' => Icons.nightlight_round,
      _ => Icons.sentiment_neutral_rounded,
    };

/// Dashboard card. Hidden when there is nothing to show.
class WellbeingCard extends ConsumerWidget {
  const WellbeingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signals = ref.watch(wellbeingProvider).valueOrNull ?? const <WellbeingSignal>[];
    final shown = signals.where((s) => s.people.isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(context.t('care.title')),
      AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('care.hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 6),
          for (final s in shown)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: IconBadge(_icon(s.key), color: context.colors.warning, size: 36),
              title: Text(context.t('care.${s.key}'), style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Pill('${s.people.length}', color: context.colors.warning),
              onTap: () => showAppSheet(
                context,
                title: context.t('care.${s.key}'),
                child: Column(children: [
                  for (final p in s.people)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(name: p.name, url: p.avatar, size: 38),
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(p.detail),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/h/employee/${p.employeeId}');
                      },
                    ),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}
