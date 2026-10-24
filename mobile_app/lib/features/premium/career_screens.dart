import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import 'premium_common.dart';

final careerMeProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => asMap(await ref.read(apiProvider).get('/career/me')));
final careerTeamProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/career/team')));
final careerLevelsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/career/levels')));
final careerSkillsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/career/skills')));

String _levelName(BuildContext c, Map? l) => l == null || l.isEmpty ? c.t('car.not_placed') : pick(c, l, 'name');

/// My career path (and, for managers and HR, the team's readiness and the ladder).
class CareerPathScreen extends ConsumerStatefulWidget {
  const CareerPathScreen({super.key});
  @override
  ConsumerState<CareerPathScreen> createState() => _CareerPathScreenState();
}

class _CareerPathScreenState extends ConsumerState<CareerPathScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    final isHr = user != null && user.role != 'employee';
    final isLead = isHr || (user?.isTeamLead ?? false);
    final hasPlan = user?.employeeId != null;
    final tabs = [if (hasPlan) context.t('car.tab_me'), if (isLead) context.t('car.tab_team')];
    final tabIndex = _tab.clamp(0, tabs.isEmpty ? 0 : tabs.length - 1);
    final showMe = hasPlan && tabIndex == 0;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('car.title')), actions: [if (isHr) IconButton(tooltip: context.t('car.ladder'), icon: const Icon(Icons.stairs_rounded), onPressed: () => context.push('/career-ladder'))]),
      body: Column(children: [
        if (tabs.length > 1) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SegmentBar(labels: tabs, index: tabIndex, onChanged: (i) => setState(() => _tab = i))),
        Expanded(child: showMe ? const _MyPlan() : (isLead ? const _TeamPlans() : const SizedBox.shrink())),
      ]),
    );
  }
}

class _MyPlan extends ConsumerWidget {
  const _MyPlan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(careerMeProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(careerMeProvider);
        await ref.read(careerMeProvider.future).catchError((_) => <String, dynamic>{});
      },
      child: data.when(
        loading: () => const SkeletonList(count: 3, itemHeight: 120),
        error: (e, _) => isFeatureOff(e) ? const FeatureOff() : ErrorState(e, onRetry: () => ref.invalidate(careerMeProvider)),
        data: (p) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), physics: const AlwaysScrollableScrollPhysics(), children: [PlanView(plan: p)]),
      ),
    );
  }
}

/// One person's plan: where they are, what the next level needs, and what is still missing.
class PlanView extends StatelessWidget {
  final Map<String, dynamic> plan;
  const PlanView({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final cur = asMap(plan['current']);
    final next = asMap(plan['next']);
    final blockers = asMapList(plan['blockers']);
    final pct = jIntN(plan, 'readiness');
    final ready = plan['ready'] == true && next.isNotEmpty;
    final eta = jIntN(plan, 'etaMonths');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        gradient: brandGradient(context),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('car.you_are'), style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text(_levelName(context, cur), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              if (next.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${context.t('car.next')}: ${_levelName(context, next)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
          if (pct != null) ProgressRing(value: pct / 100, color: Colors.white, size: 74, stroke: 8, child: Text('$pct%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
        ]),
      ),
      if (plan['topLevel'] == true) Padding(padding: const EdgeInsets.only(top: 14), child: AppCard(child: Row(children: [Icon(Icons.emoji_events_rounded, color: context.colors.warning), const SizedBox(width: 12), Expanded(child: Text(context.t('car.top'), style: const TextStyle(fontWeight: FontWeight.w700)))]))),
      if (ready)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: AppCard(
            color: context.colors.success.withValues(alpha: 0.12),
            child: Row(children: [Icon(Icons.verified_rounded, color: context.colors.success), const SizedBox(width: 12), Expanded(child: Text(context.t('car.ready'), style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)))]),
          ),
        ),
      if (next.isNotEmpty && !ready) ...[
        SectionHeader(context.t('car.missing')),
        AppCard(
          child: Column(children: [
            for (final b in blockers) _BlockerRow(b: b, plan: plan),
            if (eta != null && eta > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Icon(Icons.schedule_rounded, size: 18, color: context.colors.subtext), const SizedBox(width: 8), Expanded(child: Text(context.t('car.eta', {'n': eta}), style: TextStyle(color: context.colors.subtext)))])),
            if (eta == null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.t('car.eta_unknown'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5))),
          ]),
        ),
      ],
      if (next.isNotEmpty) ...[
        SectionHeader(context.t('car.requirements', {'l': _levelName(context, next)})),
        AppCard(
          child: Column(children: [
            if (jInt(next, 'minMonths') > 0) InfoRow(icon: Icons.work_history_rounded, label: context.t('car.req_months'), value: '${jInt(plan, 'monthsOfService')} / ${jInt(next, 'minMonths')}'),
            if (jInt(next, 'minPoints') > 0 && plan['pointsEnabled'] == true) InfoRow(icon: Icons.emoji_events_rounded, label: context.t('car.req_points'), value: '${jInt(plan, 'pointsScore')} / ${jInt(next, 'minPoints')}'),
            for (final s in asMapList(next['skills'])) InfoRow(icon: Icons.psychology_rounded, label: pick(context, s, 'name'), value: '${jInt(s, 'have')} / ${jInt(s, 'need')}'),
            if (jInt(next, 'minMonths') == 0 && jInt(next, 'minPoints') == 0 && asMapList(next['skills']).isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(context.t('car.no_req'), style: TextStyle(color: context.colors.subtext))),
          ]),
        ),
      ],
    ]);
  }
}

class _BlockerRow extends StatelessWidget {
  final Map<String, dynamic> b;
  final Map<String, dynamic> plan;
  const _BlockerRow({required this.b, required this.plan});

  @override
  Widget build(BuildContext context) {
    final type = jStr(b, 'type');
    final need = jInt(b, 'need');
    final have = jInt(b, 'have');
    final label = switch (type) {
      'tenure' => context.t('car.b_tenure', {'n': jInt(b, 'left')}),
      'points' => context.t('car.b_points', {'n': jInt(b, 'left')}),
      _ => context.t('car.b_skill', {'s': pick(context, b, 'name'), 'need': need, 'have': have}),
    };
    final icon = type == 'tenure' ? Icons.work_history_rounded : (type == 'points' ? Icons.emoji_events_rounded : Icons.psychology_rounded);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 18, color: context.colors.warning), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3)))]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: need == 0 ? 1 : (have / need).clamp(0, 1).toDouble(), minHeight: 7, color: context.colors.warning, backgroundColor: context.colors.surfaceAlt)),
      ]),
    );
  }
}

// ----------------------------------------------------------------------------------------- team

class _TeamPlans extends ConsumerWidget {
  const _TeamPlans();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(careerTeamProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(careerTeamProvider);
        await ref.read(careerTeamProvider.future).catchError((_) => <Map<String, dynamic>>[]);
      },
      child: data.when(
        loading: () => const SkeletonList(),
        error: (e, _) => isFeatureOff(e) ? const FeatureOff() : ErrorState(e, onRetry: () => ref.invalidate(careerTeamProvider)),
        data: (rows) {
          if (rows.isEmpty) return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: 360, child: EmptyState(icon: Icons.groups_rounded, title: context.t('car.team_empty')))]);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = rows[i];
              final pct = jIntN(r, 'readiness');
              final ready = r['ready'] == true;
              return RowTile(
                leading: Avatar(name: jStr(r, 'name'), size: 44),
                title: jStr(r, 'name'),
                subtitle: '${_levelName(context, asMap(r['current']))}${r['next'] == null ? '' : '  →  ${_levelName(context, asMap(r['next']))}'}',
                trailing: ready ? Pill(context.t('car.ready_short'), color: context.colors.success, icon: Icons.check_rounded) : (pct == null ? null : Pill('$pct%', color: context.colors.warning)),
                onTap: () => showAppSheet(context, title: jStr(r, 'name'), child: _PersonPlanSheet(employeeId: jInt(r, 'employeeId'))),
              );
            },
          );
        },
      ),
    );
  }
}

class _PersonPlanSheet extends ConsumerStatefulWidget {
  final int employeeId;
  const _PersonPlanSheet({required this.employeeId});
  @override
  ConsumerState<_PersonPlanSheet> createState() => _PersonPlanSheetState();
}

class _PersonPlanSheetState extends ConsumerState<_PersonPlanSheet> {
  Map<String, dynamic>? _plan;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await ref.read(apiProvider).get('/career/employee/${widget.employeeId}'));
      if (mounted) setState(() => _plan = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _call(Future<dynamic> Function() f) async {
    setState(() => _busy = true);
    try {
      final r = asMap(await f());
      ref.invalidate(careerTeamProvider);
      if (mounted) setState(() => _plan = r);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHr = (ref.watch(sessionProvider).user?.role ?? 'employee') != 'employee';
    if (_error != null) return ErrorState(_error!, onRetry: () { setState(() => _error = null); _load(); });
    if (_plan == null) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    final p = _plan!;
    final skills = ref.watch(careerSkillsProvider).valueOrNull ?? const [];
    final mine = {for (final s in asMapList(p['mySkills'])) jInt(s, 'skillId'): jInt(s, 'proficiency')};
    final levels = ref.watch(careerLevelsProvider).valueOrNull ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PlanView(plan: p),
      if (skills.isNotEmpty) ...[
        SectionHeader(context.t('car.skills_title')),
        for (final s in skills)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Text(pick(context, s, 'name'), style: const TextStyle(fontWeight: FontWeight.w600))),
              for (var lv = 1; lv <= 5; lv++)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _busy ? null : () => _call(() => ref.read(apiProvider).put('/career/employees/${widget.employeeId}/skills', {'skills': [{'skill_id': jInt(s, 'id'), 'proficiency': mine[jInt(s, 'id')] == lv ? 0 : lv}]})),
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: (mine[jInt(s, 'id')] ?? 0) >= lv ? context.scheme.primary : context.colors.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                      child: Text('$lv', style: TextStyle(fontWeight: FontWeight.w700, color: (mine[jInt(s, 'id')] ?? 0) >= lv ? Colors.white : context.colors.subtext)),
                    ),
                  ),
                ),
            ]),
          ),
      ],
      if (isHr) ...[
        const SizedBox(height: 10),
        if (levels.isNotEmpty)
          DropdownButtonFormField<int?>(
            initialValue: asMap(p['current']).isEmpty ? null : jInt(asMap(p['current']), 'id'),
            decoration: InputDecoration(labelText: context.t('car.place_on')),
            items: [for (final l in levels) DropdownMenuItem(value: jInt(l, 'id'), child: Text(pick(context, l, 'name')))],
            onChanged: _busy ? null : (v) => _call(() => ref.read(apiProvider).put('/career/employees/${widget.employeeId}/level', {'level_id': v})),
          ),
        const SizedBox(height: 12),
        if (asMap(p['next']).isNotEmpty)
          LoadingButton(
            label: context.t('car.promote_to', {'l': _levelName(context, asMap(p['next']))}),
            icon: Icons.trending_up_rounded,
            loading: _busy,
            onPressed: () async {
              final force = p['ready'] != true;
              final ok = await confirmDialog(context, title: context.t('car.promote_q'), message: force ? context.t('car.promote_force') : context.t('car.promote_msg'), confirmLabel: context.t('car.promote'));
              if (!ok) return;
              await _call(() => ref.read(apiProvider).post('/career/employees/${widget.employeeId}/promote', {if (force) 'force': true}));
              if (context.mounted) toast(context, context.t('car.promoted'));
            },
          ),
      ],
    ]);
  }
}

// ----------------------------------------------------------------------------------------- ladder (HR)

class CareerLadderScreen extends ConsumerWidget {
  const CareerLadderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = ref.watch(careerLevelsProvider);
    final skills = ref.watch(careerSkillsProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(context.t('car.ladder'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAppSheet(context, title: context.t('car.new_level'), child: _LevelForm(skills: skills, levels: levels.valueOrNull ?? const [])),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('car.new_level')),
      ),
      body: AsyncBody<List<Map<String, dynamic>>>(
        value: levels,
        onRetry: () => ref.invalidate(careerLevelsProvider),
        builder: (rows) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
          Text(context.t('car.ladder_hint'), style: TextStyle(color: context.colors.subtext, height: 1.45)),
          const SizedBox(height: 12),
          if (rows.isEmpty) SizedBox(height: 300, child: EmptyState(icon: Icons.stairs_rounded, title: context.t('car.ladder_empty'))),
          for (final l in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RowTile(
                leading: CircleAvatar(backgroundColor: context.colors.brandSoft, child: Text('${jInt(l, 'rankNo')}', style: TextStyle(fontWeight: FontWeight.w800, color: context.scheme.primary))),
                title: pick(context, l, 'name'),
                subtitle: [
                  if (jInt(l, 'minMonths') > 0) context.t('car.months_n', {'n': jInt(l, 'minMonths')}),
                  if (jInt(l, 'minPoints') > 0) context.t('car.points_n', {'n': jInt(l, 'minPoints')}),
                  ...asMapList(l['skills']).map((s) => '${pick(context, s, 'name')} ≥ ${jInt(s, 'min')}'),
                ].join(' · '),
                onTap: () => showAppSheet(context, title: pick(context, l, 'name'), child: _LevelForm(skills: skills, levels: rows, level: l)),
              ),
            ),
          SectionHeader(context.t('car.skills_catalogue'), action: context.t('car.add_skill'), onAction: () => showAppSheet(context, title: context.t('car.add_skill'), child: const _SkillForm())),
          if (skills.isEmpty) Text(context.t('car.no_skills'), style: TextStyle(color: context.colors.subtext)),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final s in skills) Chip(label: Text(pick(context, s, 'name')))]),
        ]),
      ),
    );
  }
}

class _SkillForm extends ConsumerStatefulWidget {
  const _SkillForm();
  @override
  ConsumerState<_SkillForm> createState() => _SkillFormState();
}

class _SkillFormState extends ConsumerState<_SkillForm> {
  final _en = TextEditingController();
  final _ar = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _en.dispose();
    _ar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppField(controller: _en, label: context.t('car.name_en')),
        const SizedBox(height: 10),
        AppField(controller: _ar, label: context.t('car.name_ar')),
        const SizedBox(height: 16),
        LoadingButton(
          label: context.t('common.save'),
          loading: _busy,
          onPressed: () async {
            setState(() => _busy = true);
            try {
              await ref.read(apiProvider).post('/career/skills', {'name_en': _en.text.trim(), 'name_ar': _ar.text.trim()});
              ref.invalidate(careerSkillsProvider);
              if (context.mounted) Navigator.pop(context);
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ),
      ]);
}

class _LevelForm extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> skills;
  final List<Map<String, dynamic>> levels;
  final Map<String, dynamic>? level;
  const _LevelForm({required this.skills, required this.levels, this.level});
  @override
  ConsumerState<_LevelForm> createState() => _LevelFormState();
}

class _LevelFormState extends ConsumerState<_LevelForm> {
  late final _en = TextEditingController(text: jStr(widget.level ?? {}, 'nameEn'));
  late final _ar = TextEditingController(text: jStr(widget.level ?? {}, 'nameAr'));
  late final _rank = TextEditingController(text: widget.level == null ? '${(widget.levels.map((l) => jInt(l, 'rankNo')).fold<int>(0, (a, b) => a > b ? a : b)) + 1}' : '${jInt(widget.level!, 'rankNo')}');
  late final _months = TextEditingController(text: '${jInt(widget.level ?? {}, 'minMonths')}');
  late final _points = TextEditingController(text: '${jInt(widget.level ?? {}, 'minPoints')}');
  late final Map<int, int> _req = {for (final s in asMapList(widget.level?['skills'])) jInt(s, 'skillId'): jInt(s, 'min')};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_en, _ar, _rank, _months, _points]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final body = {
        'name_en': _en.text.trim(),
        'name_ar': _ar.text.trim(),
        'rank_no': int.tryParse(_rank.text.trim()) ?? 0,
        'min_months': int.tryParse(_months.text.trim()) ?? 0,
        'min_points': int.tryParse(_points.text.trim()) ?? 0,
        'skills': [for (final e in _req.entries) {'skill_id': e.key, 'min': e.value}],
      };
      final api = ref.read(apiProvider);
      if (widget.level == null) {
        await api.post('/career/levels', body);
      } else {
        await api.put('/career/levels/${jInt(widget.level!, 'id')}', body);
      }
      ref.invalidate(careerLevelsProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: context.t('car.delete_level_q'), danger: true, confirmLabel: context.t('common.delete'));
    if (!ok) return;
    try {
      await ref.read(apiProvider).delete('/career/levels/${jInt(widget.level!, 'id')}');
      ref.invalidate(careerLevelsProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: _en, label: context.t('car.name_en')),
      const SizedBox(height: 10),
      AppField(controller: _ar, label: context.t('car.name_ar')),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: AppField(controller: _rank, label: context.t('car.rank'), keyboard: TextInputType.number)),
        const SizedBox(width: 10),
        Expanded(child: AppField(controller: _months, label: context.t('car.min_months'), keyboard: TextInputType.number)),
        const SizedBox(width: 10),
        Expanded(child: AppField(controller: _points, label: context.t('car.min_points'), keyboard: TextInputType.number)),
      ]),
      if (widget.skills.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(context.t('car.req_skills'), style: context.text.titleSmall),
        for (final s in widget.skills)
          Row(children: [
            Expanded(child: Text(pick(context, s, 'name'))),
            DropdownButton<int>(
              value: _req[jInt(s, 'id')] ?? 0,
              items: [DropdownMenuItem(value: 0, child: Text(context.t('car.not_required'))), for (var i = 1; i <= 5; i++) DropdownMenuItem(value: i, child: Text('≥ $i'))],
              onChanged: (v) => setState(() => (v ?? 0) == 0 ? _req.remove(jInt(s, 'id')) : _req[jInt(s, 'id')] = v!),
            ),
          ]),
      ],
      const SizedBox(height: 16),
      LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
      if (widget.level != null) TextButton(onPressed: _delete, child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger))),
    ]);
  }
}
