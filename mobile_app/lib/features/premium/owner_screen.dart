import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import 'premium_common.dart';

final ownerOverviewProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => asMap(await ref.read(apiProvider).get('/owner/features')));
final ownerAuditProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final r = await ref.read(apiProvider).get('/owner/audit', query: {'limit': 60});
  return asMapList(r);
});

const _featureIcons = <String, IconData>{
  'local_laws': Icons.gavel_rounded,
  'arabic_pack': Icons.translate_rounded,
  'fair_decisions': Icons.balance_rounded,
  'group_dashboard': Icons.insights_rounded,
  'manager_coach': Icons.tips_and_updates_rounded,
  'field_proof': Icons.pin_drop_rounded,
  'career_path': Icons.stairs_rounded,
};

/// The owner's control panel: which company may use which premium feature. Every switch is enforced by the server.
class OwnerScreen extends ConsumerStatefulWidget {
  const OwnerScreen({super.key});
  @override
  ConsumerState<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends ConsumerState<OwnerScreen> {
  int _tab = 0;
  final _busy = <String>{}; // "companyId:key" while a switch is being saved

  Future<void> _set(Map company, String key, bool on) async {
    final id = jInt(company, 'id');
    final tag = '$id:$key';
    setState(() => _busy.add(tag));
    try {
      await ref.read(apiProvider).put('/owner/companies/$id/features', {'flags': {key: on}});
      ref.invalidate(ownerOverviewProvider);
      ref.invalidate(ownerAuditProvider);
      await ref.read(ownerOverviewProvider.future);
      if (ref.read(sessionProvider).company?.id == id) await ref.read(sessionProvider.notifier).refresh();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(tag));
    }
  }

  Future<void> _applyAll(Map feature, bool on, int companies) async {
    final title = pick(context, feature, 'title');
    final ok = await confirmDialog(context,
        title: context.t(on ? 'own.all_on_q' : 'own.all_off_q', {'f': title}),
        message: context.t(on ? 'own.all_on_msg' : 'own.all_off_msg', {'n': companies}),
        confirmLabel: context.t(on ? 'own.turn_on' : 'own.turn_off'),
        danger: !on);
    if (!ok) return;
    try {
      await ref.read(apiProvider).post('/owner/features/apply', {'key': jStr(feature, 'key'), 'enabled': on});
      ref.invalidate(ownerOverviewProvider);
      ref.invalidate(ownerAuditProvider);
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) toast(context, context.t('own.saved'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(ownerOverviewProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('own.title'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentBar(labels: [context.t('own.tab_companies'), context.t('own.tab_features'), context.t('own.tab_log')], index: _tab, onChanged: (i) => setState(() => _tab = i)),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(ownerOverviewProvider);
              ref.invalidate(ownerAuditProvider);
              await ref.read(ownerOverviewProvider.future).catchError((_) => <String, dynamic>{});
            },
            child: AsyncBody<Map<String, dynamic>>(
              value: data,
              onRetry: () => ref.invalidate(ownerOverviewProvider),
              builder: (d) {
                final features = asMapList(d['features']);
                final companies = asMapList(d['companies']);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    AppCard(
                      color: context.colors.brandSoft,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.admin_panel_settings_rounded, color: context.scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(child: Text(context.t(jStr(d, 'mode') == 'owner' ? 'own.hint_owner' : 'own.hint_super'), style: const TextStyle(height: 1.45))),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    if (_tab == 0) ..._companiesTab(features, companies),
                    if (_tab == 1) ..._featuresTab(features, companies),
                    if (_tab == 2) _LogTab(),
                  ],
                );
              },
            ),
          ),
        ),
      ]),
    );
  }

  List<Widget> _companiesTab(List<Map<String, dynamic>> features, List<Map<String, dynamic>> companies) {
    if (companies.isEmpty) return [SizedBox(height: 300, child: EmptyState(icon: Icons.business_rounded, title: context.t('own.no_companies')))];
    return [
      for (final c in companies)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _CompanyCard(
            company: c,
            features: features,
            busy: _busy,
            onChanged: (key, on) => _set(c, key, on),
          ),
        ),
    ];
  }

  List<Widget> _featuresTab(List<Map<String, dynamic>> features, List<Map<String, dynamic>> companies) {
    return [
      for (final f in features)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Builder(builder: (context) {
            final key = jStr(f, 'key');
            final on = companies.where((c) => asMap(c['flags'])[camelKey(key)] == true).length;
            return AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconBadge(_featureIcons[key] ?? Icons.extension_rounded, color: context.scheme.primary, size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: Text(pick(context, f, 'title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
                  Pill(context.t('own.on_n', {'on': on, 'n': companies.length}), color: on == 0 ? context.colors.subtext : context.colors.success),
                ]),
                const SizedBox(height: 8),
                Text(pick(context, f, 'desc'), style: TextStyle(color: context.colors.subtext, height: 1.45)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: on == companies.length ? null : () => _applyAll(f, true, companies.length), child: Text(context.t('own.all_on')))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton(onPressed: on == 0 ? null : () => _applyAll(f, false, companies.length), child: Text(context.t('own.all_off')))),
                ]),
              ]),
            );
          }),
        ),
    ];
  }
}

class _CompanyCard extends StatelessWidget {
  final Map<String, dynamic> company;
  final List<Map<String, dynamic>> features;
  final Set<String> busy;
  final void Function(String key, bool on) onChanged;
  const _CompanyCard({required this.company, required this.features, required this.busy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final flags = asMap(company['flags']);
    final onCount = features.where((f) => flags[camelKey(jStr(f, 'key'))] == true).length;
    final id = jInt(company, 'id');
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          leading: IconBadge(Icons.business_rounded, color: context.scheme.primary, size: 40),
          title: Text(jStr(company, 'name'), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(context.t('own.company_sub', {'on': onCount, 'n': features.length, 'people': jInt(company, 'employeeCount')}), style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
          children: [
            for (final f in features)
              Builder(builder: (context) {
                final key = jStr(f, 'key');
                final saving = busy.contains('$id:$key');
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  secondary: Icon(_featureIcons[key] ?? Icons.extension_rounded, color: context.colors.subtext),
                  title: Text(pick(context, f, 'title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  subtitle: Text(pick(context, f, 'desc'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.35)),
                  value: flags[camelKey(key)] == true,
                  onChanged: saving ? null : (v) => onChanged(key, v),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _LogTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(ownerAuditProvider);
    return log.when(
      loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(ownerAuditProvider)),
      data: (rows) {
        if (rows.isEmpty) return SizedBox(height: 300, child: EmptyState(icon: Icons.history_rounded, title: context.t('own.log_empty')));
        return Column(children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RowTile(
                leading: IconBadge(r['enabled'] == true || r['enabled'] == 1 ? Icons.toggle_on_rounded : Icons.toggle_off_rounded, color: (r['enabled'] == true || r['enabled'] == 1) ? context.colors.success : context.colors.danger, size: 38),
                title: '${context.t('own.f.${jStr(r, 'featureKey')}')} · ${jStr(r, 'companyName')}',
                subtitle: '${context.t((r['enabled'] == true || r['enabled'] == 1) ? 'own.log_on' : 'own.log_off')} · ${jStr(r, 'actorName')} · ${jStr(r, 'createdAt').replaceFirst('T', ' ').split('.').first}',
              ),
            ),
        ]);
      },
    );
  }
}
