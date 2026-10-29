import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../../core/ui/responsive.dart';
import '../data/providers.dart';
import '../rewards/rewards_screen.dart';

// ============================================================ rewards leaderboard (HR)

class HrRewardsScreen extends ConsumerWidget {
  const HrRewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text(context.t('rewards.tab_board')), actions: [
          IconButton(icon: const Icon(Icons.tune_rounded), tooltip: context.t('policy.title'), onPressed: () => context.push('/h/policies?tab=1')),
        ]),
        body: const LeaderboardList(),
      );
}

// ================================================================ reports / exports

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _busy;

  Future<void> _export(String id, String query, String name) async {
    setState(() => _busy = id);
    final failed = context.t('reports.failed');
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$name.csv';
      await ref.read(apiProvider).download('/api/reports/$id?$query&format=csv', path);
      await Share.shareXFiles([XFile(path, mimeType: 'text/csv')], subject: name);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, failed, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    final items = <(String, IconData, Color, String, String, String)>[
      ('attendance', Icons.fact_check_rounded, const Color(0xFF10B981), context.t('reports.attendance'), 'month=$m', 'attendance-$m'),
      ('attendance-daily', Icons.calendar_view_month_rounded, const Color(0xFF0EA5E9), context.t('reports.daily'), 'from=$m-01&to=${ymd(DateTime(_month.year, _month.month + 1, 0))}', 'attendance-daily-$m'),
      ('payroll', Icons.payments_rounded, const Color(0xFF8B5CF6), context.t('reports.payroll'), 'month=$m', 'payroll-$m'),
      ('leaves', Icons.beach_access_rounded, const Color(0xFFF59E0B), context.t('reports.leaves'), 'year=${_month.year}', 'leaves-${_month.year}'),
      ('employees', Icons.people_alt_rounded, const Color(0xFF6366F1), context.t('reports.employees'), '', 'employees'),
      ('points', Icons.emoji_events_rounded, const Color(0xFFEC4899), context.t('reports.points'), '', 'points'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.t('reports.title'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Row(children: [
          IconButton.filledTonal(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(child: Center(child: Text(fmtMonthYear(context, _month), style: context.text.titleMedium))),
          IconButton.filledTonal(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        const SizedBox(height: 6),
        Padding(padding: const EdgeInsets.all(8), child: Text(context.t('reports.hint'), style: TextStyle(color: context.colors.subtext, height: 1.4))),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RowTile(
              leading: IconBadge(it.$2, color: it.$3, size: 46),
              title: it.$4,
              subtitle: context.t('reports.csv'),
              trailing: _busy == it.$1 ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)) : Icon(Icons.ios_share_rounded, color: context.scheme.primary),
              onTap: _busy != null ? null : () => _export(it.$1, it.$5, it.$6),
            ),
          ),
      ]),
    );
  }
}

// ===================================================================== audit log

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String _entity = '';
  static const _entities = ['', 'employee', 'attendance', 'payroll', 'department', 'request', 'points', 'company', 'attendance_rule'];

  IconData _icon(String e) {
    switch (e) {
      case 'employee':
        return Icons.person_rounded;
      case 'attendance':
      case 'attendance_rule':
        return Icons.access_time_rounded;
      case 'payroll':
        return Icons.payments_rounded;
      case 'department':
        return Icons.account_tree_rounded;
      case 'request':
        return Icons.fact_check_rounded;
      case 'points':
        return Icons.emoji_events_rounded;
      default:
        return Icons.settings_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(auditProvider(_entity));
    return Scaffold(
      appBar: AppBar(title: Text(context.t('audit.title'))),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final e in _entities)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(e.isEmpty ? context.t('common.all') : context.t('audit.entity.$e')),
                  selected: _entity == e,
                  showCheckmark: false,
                  selectedColor: context.scheme.primary,
                  labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _entity == e ? Colors.white : context.scheme.onSurface),
                  onSelected: (_) => setState(() => _entity = e),
                ),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(auditProvider(_entity));
              await ref.read(auditProvider(_entity).future).catchError((_) => <AuditEntry>[]);
            },
            child: AsyncBody<List<AuditEntry>>(
              value: log,
              onRetry: () => ref.invalidate(auditProvider(_entity)),
              builder: (items) => items.isEmpty
                  ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.history_rounded, title: context.t('audit.empty')))])
                  : AdaptiveList(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: items.length,
                      gap: 8,
                      itemBuilder: (_, i) {
                        final a = items[i];
                        return AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            IconBadge(_icon(a.entity), color: colorFor(a.entity), size: 38),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${a.user.isEmpty ? '—' : a.user} · ${a.action} ${context.t('audit.entity.${a.entity}')}${a.entityId == null ? '' : ' #${a.entityId}'}', style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
                                if (a.details.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(a.details, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.35))),
                                Padding(padding: const EdgeInsets.only(top: 3), child: Text(timeAgo(context, a.at), style: TextStyle(color: context.colors.subtext, fontSize: 11))),
                              ]),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}
