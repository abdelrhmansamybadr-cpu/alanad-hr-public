import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

// ====================================================================== career

IconData promotionIcon(String type) {
  switch (type) {
    case 'raise':
      return Icons.trending_up_rounded;
    case 'transfer':
      return Icons.swap_horiz_rounded;
    case 'demotion':
      return Icons.tune_rounded;
    default:
      return Icons.rocket_launch_rounded;
  }
}

Color promotionColor(BuildContext context, String type) {
  switch (type) {
    case 'raise':
      return context.colors.success;
    case 'transfer':
      return context.colors.info;
    case 'demotion':
      return context.colors.warning;
    default:
      return const Color(0xFF8B5CF6);
  }
}

/// My career (employee) — promotions, raises and transfers as a timeline.
class CareerScreen extends ConsumerWidget {
  final int? employeeId;
  const CareerScreen({super.key, this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = employeeId ?? ref.watch(sessionProvider).user?.employeeId ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('career.title'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [CareerTimeline(employeeId: id, withHeader: true)]),
    );
  }
}

class CareerTimeline extends ConsumerWidget {
  final int employeeId;
  final bool withHeader;
  const CareerTimeline({super.key, required this.employeeId, this.withHeader = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(promotionsProvider(employeeId));
    final currency = ref.watch(sessionProvider).company?.currency ?? '';
    return AsyncBody<List<Promotion>>(
      value: list,
      onRetry: () => ref.invalidate(promotionsProvider(employeeId)),
      loading: const Skeleton(height: 160, radius: 20),
      builder: (items) {
        if (items.isEmpty) {
          return Padding(padding: const EdgeInsets.only(top: 30), child: EmptyState(icon: Icons.timeline_rounded, title: context.t('career.empty'), subtitle: context.t('career.empty_hint')));
        }
        return Column(children: [
          for (var i = 0; i < items.length; i++)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 450 + i * 120),
              curve: Curves.easeOutCubic,
              builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child)),
              child: _Node(p: items[i], last: i == items.length - 1, currency: currency),
            ),
        ]);
      },
    );
  }
}

class _Node extends StatelessWidget {
  final Promotion p;
  final bool last;
  final String currency;
  const _Node({required this.p, required this.last, required this.currency});

  @override
  Widget build(BuildContext context) {
    final color = promotionColor(context, p.type);
    final lines = <String>[
      if (p.toPosition != null) '${p.fromPosition?.isNotEmpty == true ? p.fromPosition : '—'}  →  ${p.toPosition}',
      if (p.toDepartment != null) '${p.fromDepartment ?? '—'}  →  ${p.toDepartment}',
      if (p.toSalary != null) '${p.fromSalary == null ? '—' : money(context, p.fromSalary!, currency)}  →  ${money(context, p.toSalary!, currency)}',
    ];
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 44,
          child: Column(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: color, width: 2)), child: Icon(promotionIcon(p.type), color: color, size: 20)),
            if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: context.colors.border)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(context.t('career.type.${p.type}'), style: TextStyle(fontWeight: FontWeight.w800, color: color))),
                  if (!p.applied) Pill(context.t('career.scheduled'), color: context.colors.warning),
                  if (!p.applied) const SizedBox(width: 8),
                  Text(fmtDate(context, p.date), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                ]),
                for (final l in lines) Padding(padding: const EdgeInsets.only(top: 6), child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3))),
                if (p.note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(p.note!, style: TextStyle(color: context.colors.subtext, fontSize: 13, height: 1.4))),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ===================================================================== org chart

class OrgScreen extends ConsumerStatefulWidget {
  const OrgScreen({super.key});

  @override
  ConsumerState<OrgScreen> createState() => _OrgScreenState();
}

class _OrgScreenState extends ConsumerState<OrgScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final org = ref.watch(orgProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('org.chart'))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SegmentBar(labels: [context.t('org.tab_departments'), context.t('org.tab_lines')], index: _tab, onChanged: (i) => setState(() => _tab = i))),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(orgProvider);
              await ref.read(orgProvider.future).catchError((_) => const OrgData());
            },
            child: AsyncBody<OrgData>(
              value: org,
              onRetry: () => ref.invalidate(orgProvider),
              builder: (data) => _tab == 0 ? _Departments(data: data) : _Lines(data: data),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final OrgPerson p;
  final bool head;
  final double size;
  const _PersonRow({required this.p, this.head = false, this.size = 40});

  @override
  Widget build(BuildContext context) => Row(children: [
        Avatar(name: p.name, url: p.avatar, size: size, ring: head),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: head ? FontWeight.w800 : FontWeight.w600)),
            if (p.position.isNotEmpty) Text(p.position, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.subtext, fontSize: 12)),
          ]),
        ),
        if (head) Pill(context.t('org.head'), color: const Color(0xFFF59E0B), icon: Icons.star_rounded),
      ]);
}

class _Departments extends StatelessWidget {
  final OrgData data;
  const _Departments({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.departments.isEmpty && data.unassigned.isEmpty) {
      return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.account_tree_outlined, title: context.t('org.no_departments'), subtitle: context.t('org.no_departments_hint')))]);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), physics: const AlwaysScrollableScrollPhysics(), children: [
      for (final d in data.departments)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                leading: IconBadge(Icons.account_tree_rounded, color: colorFor(d.name), size: 42),
                title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(context.t('org.people_count', {'n': d.members.length}), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                children: [
                  if (d.head != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: _PersonRow(p: d.head!, head: true, size: 46)) else Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(context.t('org.no_head'), style: TextStyle(color: context.colors.subtext))),
                  for (final m in d.members.where((m) => m.id != d.head?.id)) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: _PersonRow(p: m)),
                ],
              ),
            ),
          ),
        ),
      if (data.unassigned.isNotEmpty) ...[
        SectionHeader(context.t('org.unassigned')),
        AppCard(child: Column(children: [for (final m in data.unassigned) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: _PersonRow(p: m))])),
      ],
    ]);
  }
}

class _Lines extends StatelessWidget {
  final OrgData data;
  const _Lines({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.tree.isEmpty) {
      return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.people_outline_rounded, title: context.t('org.no_people'), subtitle: null))]);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), physics: const AlwaysScrollableScrollPhysics(), children: [
      for (final root in data.tree) _TreeNode(p: root, depth: 0),
    ]);
  }
}

class _TreeNode extends StatefulWidget {
  final OrgPerson p;
  final int depth;
  const _TreeNode({required this.p, required this.depth});

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  late bool _open = widget.depth < 1;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final has = p.reports.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsetsDirectional.only(start: widget.depth.clamp(0, 6) * 18.0, bottom: 8),
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: has ? () => setState(() => _open = !_open) : null,
          child: Row(children: [
            Expanded(child: _PersonRow(p: p, size: 38)),
            if (has) ...[
              Pill('${p.reports.length}', color: context.scheme.primary, icon: Icons.groups_rounded),
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: context.colors.subtext),
            ],
          ]),
        ),
      ),
      if (has && _open) for (final r in p.reports) _TreeNode(p: r, depth: widget.depth + 1),
    ]);
  }
}
