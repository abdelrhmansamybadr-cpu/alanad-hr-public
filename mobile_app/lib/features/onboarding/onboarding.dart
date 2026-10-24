import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';

// ====================================================================== models

class ObTask {
  final int id;
  final String title;
  final String description;
  final String owner; // employee | hr
  final DateTime? dueDate;
  final bool done;
  final String? doneBy;
  final String? autoKey; // set = the SYSTEM completes this step once the employee really did it
  const ObTask({required this.id, required this.title, this.description = '', this.owner = 'employee', this.dueDate, this.done = false, this.doneBy, this.autoKey});

  factory ObTask.fromJson(dynamic raw) {
    final m = asMap(raw);
    return ObTask(id: jInt(m, 'id'), title: jStr(m, 'title'), description: jStr(m, 'description'), owner: jStr(m, 'owner', 'employee'), dueDate: jDate(m, 'dueDate'), done: jBool(m, 'done'), doneBy: jStrN(m, 'doneByName'), autoKey: jStrN(m, 'autoKey'));
  }

  /// The six starter tasks every company gets are shown translated.
  String label(BuildContext c) => _defaults.containsKey(title) ? c.t('ob.d${_defaults[title]}') : title;
  String note(BuildContext c) => _defaults.containsKey(title) && description.isNotEmpty ? c.t('ob.d${_defaults[title]}n') : description;
}

const _defaults = <String, int>{
  'Read and sign your employment contract': 0,
  'Complete your personal details': 1,
  'Upload your ID and required documents': 2,
  'Set up your work account and equipment': 3,
  'Add the employee to payroll': 4,
  'Meet your manager and team': 5,
  'Read the company policies': 6,
  'Turn on notifications and check in once from the app': 7,
};

class ObView {
  final int employeeId;
  final int total;
  final int done;
  final bool complete;
  final List<ObTask> tasks;
  const ObView({this.employeeId = 0, this.total = 0, this.done = 0, this.complete = false, this.tasks = const []});
  double get progress => total == 0 ? 0 : done / total;

  factory ObView.fromJson(dynamic raw) {
    final m = asMap(raw);
    return ObView(employeeId: jInt(m, 'employeeId'), total: jInt(m, 'total'), done: jInt(m, 'done'), complete: jBool(m, 'complete'), tasks: asMapList(m['tasks']).map(ObTask.fromJson).toList());
  }
}

class ObRow {
  final int employeeId;
  final String name;
  final String? avatar;
  final String position;
  final int total;
  final int done;
  final int overdue;
  const ObRow({required this.employeeId, required this.name, this.avatar, this.position = '', this.total = 0, this.done = 0, this.overdue = 0});
  factory ObRow.fromJson(dynamic raw) {
    final m = asMap(raw);
    return ObRow(employeeId: jInt(m, 'employeeId'), name: jStr(m, 'name'), avatar: jStrN(m, 'avatar'), position: jStr(m, 'position'), total: jInt(m, 'total'), done: jInt(m, 'done'), overdue: jInt(m, 'overdue'));
  }
}

class ObTemplate {
  final int id;
  final String title;
  final String owner;
  final int dueDays;
  const ObTemplate({required this.id, required this.title, required this.owner, required this.dueDays});
  factory ObTemplate.fromJson(dynamic raw) {
    final m = asMap(raw);
    return ObTemplate(id: jInt(m, 'id'), title: jStr(m, 'title'), owner: jStr(m, 'owner', 'employee'), dueDays: jInt(m, 'dueDays', 7));
  }
}

// =================================================================== providers

/// The step the employee was sent off to do. While set, [ObFlowWatcher] asks the server whether it really happened.
final obFlowProvider = StateProvider<String?>((ref) => null);

/// My checklist (employee). [employeeId] 0 means "me".
final onboardingProvider = FutureProvider.autoDispose.family<ObView, int>((ref, employeeId) async {
  final api = ref.read(apiProvider);
  return ObView.fromJson(await api.get(employeeId == 0 ? '/onboarding/me' : '/onboarding/employee/$employeeId'));
});

final onboardingOverviewProvider = FutureProvider.autoDispose<List<ObRow>>((ref) async {
  final d = await ref.read(apiProvider).get('/onboarding/overview');
  return d is List ? d.map(ObRow.fromJson).toList() : <ObRow>[];
});

final onboardingTemplatesProvider = FutureProvider.autoDispose<List<ObTemplate>>((ref) async {
  final d = await ref.read(apiProvider).get('/onboarding/templates');
  return d is List ? d.map(ObTemplate.fromJson).toList() : <ObTemplate>[];
});

// ============================================================== checklist page

/// One person's checklist. Employees see their own; HR opens it for anyone (`/onboarding/:id`).
class OnboardingScreen extends ConsumerWidget {
  final int employeeId; // 0 = me
  final String? name;
  const OnboardingScreen({super.key, this.employeeId = 0, this.name});

  Future<void> _toggle(BuildContext context, WidgetRef ref, ObTask t) async {
    try {
      await ref.read(apiProvider).put('/onboarding/tasks/${t.id}', {'done': !t.done});
      ref.invalidate(onboardingProvider(employeeId));
      ref.invalidate(onboardingOverviewProvider);
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  /// Send the employee to the page where the step is really done. The system ticks it (never the employee).
  Future<void> _launch(BuildContext context, WidgetRef ref, ObTask t) async {
    final key = t.autoKey;
    if (key == null) return;
    ref.read(obFlowProvider.notifier).state = key;
    switch (key) {
      case 'contract':
      case 'details':
      case 'policies':
        await context.push('/onb-step/$key');
      case 'documents':
        await context.push('/documents');
      case 'team':
        toast(context, context.t('ob.flow_team'));
        await context.push('/directory');
      case 'checkin':
        context.go('/e/time');
        return;
      default:
        ref.read(obFlowProvider.notifier).state = null;
        return;
    }
    if (!context.mounted) return; // the watcher already brought us back
    ref.read(obFlowProvider.notifier).state = null;
    ref.invalidate(onboardingProvider(employeeId));
    ref.invalidate(onboardingOverviewProvider);
  }

  /// Add a task (task == null) or edit one (HR): title, note, who does it, and the due date.
  Future<void> _taskSheet(BuildContext context, WidgetRef ref, {ObTask? task}) async {
    final title = TextEditingController(text: task?.title ?? '');
    final desc = TextEditingController(text: task?.description ?? '');
    bool hr = task?.owner == 'hr';
    DateTime? due = task?.dueDate;
    bool busy = false;
    await showAppSheet(
      context,
      title: task == null ? context.t('ob.add_task') : context.t('ob.edit_task'),
      child: StatefulBuilder(builder: (ctx, setS) => Column(children: [
        AppField(controller: title, label: ctx.t('ob.task_title'), icon: Icons.checklist_rounded, capitalization: TextCapitalization.sentences),
        const SizedBox(height: 10),
        AppField(controller: desc, label: ctx.t('ob.note'), icon: Icons.notes_rounded, maxLines: 2, capitalization: TextCapitalization.sentences),
        const SizedBox(height: 12),
        SegmentBar(labels: [ctx.t('ob.owner_employee'), ctx.t('ob.owner_hr')], index: hr ? 1 : 0, onChanged: (i) => setS(() => hr = i == 1)),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final d = await showDatePicker(context: ctx, initialDate: due ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 730)));
            if (d != null) setS(() => due = d);
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: ctx.t('ob.due'), prefixIcon: const Icon(Icons.event_rounded), suffixIcon: due == null ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setS(() => due = null))),
            child: Text(due == null ? '—' : fmtLongDate(ctx, due!)),
          ),
        ),
        const SizedBox(height: 18),
        LoadingButton(
          label: task == null ? ctx.t('common.add') : ctx.t('common.save'),
          loading: busy,
          onPressed: () async {
            if (title.text.trim().isEmpty) return;
            final nav = Navigator.of(ctx);
            setS(() => busy = true);
            final body = <String, dynamic>{'title': title.text.trim(), 'description': desc.text.trim(), 'owner': hr ? 'hr' : 'employee', 'dueDate': due == null ? null : ymd(due!)};
            try {
              if (task == null) {
                body.removeWhere((k, v) => v == null);
                await ref.read(apiProvider).post('/onboarding/employee/$employeeId/tasks', body);
              } else {
                await ref.read(apiProvider).put('/onboarding/tasks/${task.id}', body);
              }
              ref.invalidate(onboardingProvider(employeeId));
              ref.invalidate(onboardingOverviewProvider);
              nav.pop();
            } on ApiException catch (e) {
              setS(() => busy = false);
              if (ctx.mounted) toast(ctx, e.message, error: true);
            }
          },
        ),
      ])),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHr = ref.watch(sessionProvider).user?.isHr ?? false;
    final mine = employeeId == 0;
    final v = ref.watch(onboardingProvider(employeeId));
    return Scaffold(
      appBar: AppBar(title: Text(mine ? context.t('ob.title') : (name ?? context.t('ob.title')))),
      floatingActionButton: isHr && !mine ? FloatingActionButton.extended(onPressed: () => _taskSheet(context, ref), icon: const Icon(Icons.add_rounded), label: Text(context.t('ob.add_task'))) : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(onboardingProvider(employeeId)),
        child: AsyncBody<ObView>(
          value: v,
          onRetry: () => ref.invalidate(onboardingProvider(employeeId)),
          builder: (d) {
            if (d.total == 0) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: EmptyState(icon: Icons.checklist_rounded, title: context.t('ob.empty'), subtitle: isHr && !mine ? null : context.t('ob.empty_hint')),
                ),
                if (isHr && !mine)
                  Center(
                    child: FilledButton(
                      onPressed: () async {
                        await ref.read(apiProvider).post('/onboarding/employee/$employeeId/start');
                        ref.invalidate(onboardingProvider(employeeId));
                      },
                      child: Text(context.t('ob.start')),
                    ),
                  ),
              ]);
            }
            final open = d.tasks.where((t) => !t.done).toList();
            final done = d.tasks.where((t) => t.done).toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), physics: const AlwaysScrollableScrollPhysics(), children: [
              AppCard(
                child: Row(children: [
                  ProgressRing(
                    value: d.progress,
                    color: d.complete ? context.colors.success : context.scheme.primary,
                    size: 64,
                    stroke: 7,
                    child: Text('${(d.progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.complete ? context.t('ob.all_done') : context.t('ob.n_of', {'a': d.done, 'b': d.total}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(d.complete ? context.t('ob.all_done_hint') : context.t('ob.progress_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.3)),
                    ]),
                  ),
                ]),
              ),
              if (open.isNotEmpty) SectionHeader(context.t('ob.todo')),
              for (final t in open) _TaskTile(task: t, system: mine && t.owner == 'employee' && t.autoKey != null, onGo: () => _launch(context, ref, t), canTick: isHr || t.owner == 'employee', onTick: () => _toggle(context, ref, t), onEdit: isHr && !mine ? () => _taskSheet(context, ref, task: t) : null, onDelete: isHr && !mine ? () => _delete(context, ref, t) : null),
              if (done.isNotEmpty) SectionHeader(context.t('ob.completed')),
              for (final t in done) _TaskTile(task: t, system: mine && t.owner == 'employee' && t.autoKey != null, onGo: () {}, canTick: isHr || t.owner == 'employee', onTick: () => _toggle(context, ref, t), onEdit: isHr && !mine ? () => _taskSheet(context, ref, task: t) : null, onDelete: isHr && !mine ? () => _delete(context, ref, t) : null),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, ObTask t) async {
    if (!await confirmDialog(context, title: context.t('ob.delete_task'), danger: true)) return;
    await ref.read(apiProvider).delete('/onboarding/tasks/${t.id}');
    ref.invalidate(onboardingProvider(employeeId));
  }
}

class _TaskTile extends StatelessWidget {
  final ObTask task;
  final bool canTick;
  final bool system; // a step the system completes: the employee opens the page, never ticks
  final VoidCallback onGo;
  final VoidCallback onTick;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  const _TaskTile({required this.task, required this.canTick, required this.onTick, required this.onGo, this.system = false, this.onDelete, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final late = !task.done && task.dueDate != null && task.dueDate!.isBefore(DateTime.now().subtract(const Duration(days: 1)));
    final note = task.note(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        onTap: system ? (task.done ? null : onGo) : (canTick ? onTick : null),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: IconButton(
              key: ValueKey(task.done),
              onPressed: system ? (task.done ? null : onGo) : (canTick ? onTick : null),
              icon: Icon(task.done ? Icons.check_circle_rounded : (system ? Icons.arrow_circle_right_rounded : Icons.radio_button_unchecked_rounded), color: task.done ? context.colors.success : (canTick ? context.scheme.primary : context.colors.subtext), size: 26),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(task.label(context), style: TextStyle(fontWeight: FontWeight.w700, decoration: task.done ? TextDecoration.lineThrough : null, color: task.done ? context.colors.subtext : null)),
                if (system && !task.done) Padding(padding: const EdgeInsets.only(top: 2), child: Text(context.t('ob.auto_hint'), style: TextStyle(color: context.scheme.primary, fontSize: 12, height: 1.3, fontWeight: FontWeight.w600))),
                if (note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(note, style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.3))),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  Pill(task.owner == 'hr' ? context.t('ob.owner_hr') : context.t('ob.owner_employee'), color: task.owner == 'hr' ? context.colors.info : context.scheme.primary),
                  if (task.dueDate != null && !task.done) Pill(fmtDayMonth(context, task.dueDate!), color: late ? context.colors.danger : context.colors.subtext, icon: Icons.event_rounded),
                  if (task.done && task.doneBy != null) Pill(task.doneBy == 'System' ? context.t('ob.by_system') : task.doneBy!, color: context.colors.success, icon: task.doneBy == 'System' ? Icons.verified_rounded : Icons.check_rounded),
                  if (system && !task.done) Pill(context.t('ob.go'), color: context.scheme.primary, icon: Icons.arrow_forward_rounded),
                ]),
              ]),
            ),
          ),
          if (onEdit != null) IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 20)),
          if (onDelete != null) IconButton(onPressed: onDelete, icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      ),
    );
  }
}

// ==================================================================== HR overview

class OnboardingOverviewScreen extends ConsumerWidget {
  const OnboardingOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(onboardingOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('ob.hr_title')),
        actions: [
          IconButton(
            tooltip: context.t('ob.start_all'),
            icon: const Icon(Icons.rocket_launch_outlined),
            onPressed: () async {
              try {
                final m = asMap(await ref.read(apiProvider).post('/onboarding/start-all', {}));
                ref.invalidate(onboardingOverviewProvider);
                if (context.mounted) toast(context, context.t('ob.started_n', {'n': jInt(m, 'started')}));
              } on ApiException catch (e) {
                if (context.mounted) toast(context, e.message, error: true);
              }
            },
          ),
          IconButton(tooltip: context.t('ob.template'), icon: const Icon(Icons.tune_rounded), onPressed: () => _templates(context, ref)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(onboardingOverviewProvider),
        child: AsyncBody<List<ObRow>>(
          value: rows,
          onRetry: () => ref.invalidate(onboardingOverviewProvider),
          builder: (list) {
            if (list.isEmpty) return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.checklist_rounded, title: context.t('ob.hr_empty'), subtitle: context.t('ob.hr_empty_hint')))]);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              for (final r in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () => context.push('/onboarding/${r.employeeId}', extra: r.name),
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Avatar(name: r.name, url: r.avatar, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: r.total == 0 ? 0 : r.done / r.total, minHeight: 6, color: r.done == r.total ? context.colors.success : context.scheme.primary, backgroundColor: context.colors.border)),
                          if (r.overdue > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Pill(context.t('ob.overdue_n', {'n': r.overdue}), color: context.colors.danger, icon: Icons.warning_amber_rounded)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Text('${r.done}/${r.total}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }

  /// The company's standard checklist: what every new hire gets.
  Future<void> _templates(BuildContext context, WidgetRef ref) async {
    await showAppSheet(
      context,
      title: context.t('ob.template'),
      child: Consumer(builder: (ctx, ref, _) {
        final list = ref.watch(onboardingTemplatesProvider);
        final title = TextEditingController();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ctx.t('ob.template_hint'), style: TextStyle(color: ctx.colors.subtext, fontSize: 12.5)),
          const SizedBox(height: 10),
          list.when(
            loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text(errorText(ctx, e)),
            data: (items) => Column(children: [
              for (final t in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${t.owner == 'hr' ? ctx.t('ob.owner_hr') : ctx.t('ob.owner_employee')} · ${ctx.t('ob.within_days', {'n': t.dueDays})}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      await ref.read(apiProvider).delete('/onboarding/templates/${t.id}');
                      ref.invalidate(onboardingTemplatesProvider);
                    },
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: AppField(controller: title, label: ctx.t('ob.task_title'), icon: Icons.add_task_rounded, capitalization: TextCapitalization.sentences)),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                await ref.read(apiProvider).post('/onboarding/templates', {'title': title.text.trim(), 'owner': 'employee', 'dueDays': 7});
                title.clear();
                ref.invalidate(onboardingTemplatesProvider);
              },
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
        ]);
      }),
    );
  }
}

// =================================================================== home card

/// A small "Getting started" card for the employee home while the checklist is unfinished.
class OnboardingCard extends ConsumerWidget {
  const OnboardingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(onboardingProvider(0)).valueOrNull;
    if (v == null || v.total == 0 || v.complete) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        onTap: () => context.push('/onboarding'),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          ProgressRing(value: v.progress, color: context.scheme.primary, size: 44, stroke: 5, child: Text('${v.done}/${v.total}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('ob.card_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(context.t('ob.card_hint', {'n': v.total - v.done}), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}
