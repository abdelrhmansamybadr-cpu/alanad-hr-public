import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../../core/ui/responsive.dart';
import '../data/providers.dart';

const _pipeline = ['new', 'screening', 'interview', 'offer', 'hired', 'rejected'];
const _jobTypes = ['full_time', 'part_time', 'contract', 'internship'];

Future<void> _guard(BuildContext context, Future<void> Function() action, {String? done, bool pop = true}) async {
  final nav = Navigator.of(context);
  try {
    await action();
    if (done != null && context.mounted) toast(context, done);
    if (pop) nav.pop();
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
}

// ================================================================ main screen

class RecruitmentScreen extends ConsumerStatefulWidget {
  const RecruitmentScreen({super.key});

  @override
  ConsumerState<RecruitmentScreen> createState() => _RecruitmentScreenState();
}

class _RecruitmentScreenState extends ConsumerState<RecruitmentScreen> {
  int _tab = 0;
  int _filter = 0; // 0 all, then pipeline statuses

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider);
    final apps = ref.watch(applicationsProvider(null));

    return Scaffold(
      appBar: AppBar(title: Text(context.t('rec.title')), actions: [IconButton(tooltip: context.t('rec.talent_pool'), icon: const Icon(Icons.workspace_premium_rounded), onPressed: () => context.push('/h/talent'))]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tab == 0 ? showAppSheet(context, title: context.t('rec.add_job'), child: const _JobForm()) : showAppSheet(context, title: context.t('rec.add_applicant'), child: const _ApplicantForm()),
        icon: const Icon(Icons.add_rounded),
        label: Text(_tab == 0 ? context.t('rec.add_job') : context.t('rec.add_applicant')),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: SegmentBar(labels: [context.t('rec.jobs'), context.t('rec.applicants')], index: _tab, onChanged: (i) => setState(() => _tab = i))),
        if (_tab == 1) ...[
          FilterChips(labels: [context.t('common.all'), for (final s in _pipeline) context.t('status.$s')], index: _filter, onChanged: (i) => setState(() => _filter = i)),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(jobsProvider);
              ref.invalidate(applicationsProvider);
              await ref.read(jobsProvider.future).catchError((_) => <Job>[]);
            },
            child: _tab == 0
                ? AsyncBody<List<Job>>(
                    value: jobs,
                    onRetry: () => ref.invalidate(jobsProvider),
                    builder: (items) => items.isEmpty
                        ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.work_outline_rounded, title: context.t('rec.no_jobs'), subtitle: context.t('rec.no_jobs_hint')))])
                        : AdaptiveList(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: items.length,
                            gap: 10,
                            itemBuilder: (_, i) {
                              final j = items[i];
                              return RowTile(
                                leading: IconBadge(Icons.work_rounded, color: j.status == 'open' ? context.colors.success : context.colors.subtext, size: 46),
                                title: j.title,
                                subtitle: [if (j.departmentName != null) j.departmentName!, if (j.location.isNotEmpty) j.location, if (j.type.isNotEmpty) context.t('rec.type.${j.type}')].join(' · '),
                                trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [StatusChip(j.status), const SizedBox(height: 6), Text(context.t('rec.n_applicants', {'n': j.applicants}), style: TextStyle(color: context.colors.subtext, fontSize: 11))]),
                                onTap: () => showAppSheet(context, title: j.title, child: _JobForm(existing: j)),
                              );
                            },
                          ),
                  )
                : AsyncBody<List<Application>>(
                    value: apps,
                    onRetry: () => ref.invalidate(applicationsProvider(null)),
                    builder: (all) {
                      final items = _filter == 0 ? all : all.where((a) => a.status == _pipeline[_filter - 1]).toList();
                      return items.isEmpty
                          ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.person_search_rounded, title: context.t('rec.no_applicants'), subtitle: context.t('rec.no_applicants_hint')))])
                          : AdaptiveList(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: items.length,
                              gap: 10,
                              itemBuilder: (_, i) {
                                final a = items[i];
                                return RowTile(leading: Avatar(name: a.name, size: 46), title: a.name, subtitle: [a.jobTitle, if (a.appliedAt != null) fmtDayMonth(context, a.appliedAt!)].where((s) => s.isNotEmpty).join(' · '), trailing: StatusChip(a.status), onTap: () => showAppSheet(context, title: a.name, child: _ApplicantSheet(app: a)));
                              },
                            );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

// =================================================================== job form

class _JobForm extends ConsumerStatefulWidget {
  final Job? existing;
  const _JobForm({this.existing});

  @override
  ConsumerState<_JobForm> createState() => _JobFormState();
}

class _JobFormState extends ConsumerState<_JobForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _location = TextEditingController(text: widget.existing?.location);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _req = TextEditingController(text: widget.existing?.requirements);
  late final _salary = TextEditingController(text: widget.existing?.salary);
  late int? _dept = widget.existing?.departmentId;
  late String _type = _jobTypes.contains(widget.existing?.type) ? widget.existing!.type : 'full_time';
  late bool _open = (widget.existing?.status ?? 'open') == 'open';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _location, _desc, _req, _salary]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await _guard(context, () async {
      final body = {'title': _title.text.trim(), 'departmentId': _dept, 'location': _location.text.trim(), 'type': _type, 'description': _desc.text.trim(), 'requirements': _req.text.trim(), 'salary': _salary.text.trim(), 'status': _open ? 'open' : 'closed'};
      final api = ref.read(apiProvider);
      widget.existing == null ? await api.post('/jobs', body) : await api.put('/jobs/${widget.existing!.id}', body);
      ref.invalidate(jobsProvider);
      ref.invalidate(hrStatsProvider);
    }, done: context.t('common.saved'));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final depts = ref.watch(departmentsProvider).valueOrNull ?? const <Department>[];
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppField(controller: _title, label: context.t('rec.job_title'), icon: Icons.work_outline_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
        const SizedBox(height: 14),
        DropdownButtonFormField<int?>(
          initialValue: depts.any((d) => d.id == _dept) ? _dept : null,
          decoration: InputDecoration(labelText: context.t('people.department'), prefixIcon: const Icon(Icons.account_tree_outlined)),
          items: [DropdownMenuItem<int?>(value: null, child: Text(context.t('common.none'))), for (final d in depts) DropdownMenuItem<int?>(value: d.id, child: Text(d.name))],
          onChanged: (v) => setState(() => _dept = v),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, children: [for (final t in _jobTypes) ChoiceChip(label: Text(context.t('rec.type.$t')), selected: _type == t, showCheckmark: false, onSelected: (_) => setState(() => _type = t))]),
        const SizedBox(height: 14),
        AppField(controller: _location, label: context.t('rec.location'), icon: Icons.location_on_outlined),
        const SizedBox(height: 14),
        AppField(controller: _salary, label: '${context.t('rec.salary_range')} (${context.t('common.optional')})', icon: Icons.payments_outlined),
        const SizedBox(height: 14),
        AppField(controller: _desc, label: context.t('org.description'), icon: Icons.notes_rounded, maxLines: 4),
        const SizedBox(height: 14),
        AppField(controller: _req, label: context.t('rec.requirements'), icon: Icons.checklist_rounded, maxLines: 3),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('rec.accepting')), value: _open, onChanged: (v) => setState(() => _open = v)),
        const SizedBox(height: 10),
        LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
      ]),
    );
  }
}

// ============================================================== applicants

class _ApplicantForm extends ConsumerStatefulWidget {
  const _ApplicantForm();

  @override
  ConsumerState<_ApplicantForm> createState() => _ApplicantFormState();
}

class _ApplicantFormState extends ConsumerState<_ApplicantForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _cover = TextEditingController();
  int? _job;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _cover]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_job == null) return toast(context, context.t('rec.pick_job'), error: true);
    setState(() => _busy = true);
    await _guard(context, () async {
      await ref.read(apiProvider).post('/applications', {'jobId': _job, 'applicantName': _name.text.trim(), 'email': _email.text.trim(), 'phone': _phone.text.trim(), 'coverLetter': _cover.text.trim()});
      ref.invalidate(applicationsProvider);
      ref.invalidate(jobsProvider);
      ref.invalidate(hrStatsProvider);
    }, done: context.t('common.saved'));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final jobs = (ref.watch(jobsProvider).valueOrNull ?? const <Job>[]).where((j) => j.status == 'open').toList();
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<int>(
          initialValue: _job,
          decoration: InputDecoration(labelText: context.t('rec.job'), prefixIcon: const Icon(Icons.work_outline_rounded)),
          items: [for (final j in jobs) DropdownMenuItem(value: j.id, child: Text(j.title))],
          onChanged: (v) => setState(() => _job = v),
        ),
        const SizedBox(height: 14),
        AppField(controller: _name, label: context.t('common.name'), icon: Icons.person_outline_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
        const SizedBox(height: 14),
        AppField(controller: _email, label: context.t('common.email'), icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress),
        const SizedBox(height: 14),
        AppField(controller: _phone, label: context.t('common.phone'), icon: Icons.phone_outlined, keyboard: TextInputType.phone),
        const SizedBox(height: 14),
        AppField(controller: _cover, label: context.t('rec.notes'), icon: Icons.notes_rounded, maxLines: 3),
        const SizedBox(height: 20),
        LoadingButton(label: context.t('common.add'), loading: _busy, onPressed: _save),
      ]),
    );
  }
}

class _ApplicantSheet extends ConsumerStatefulWidget {
  final Application app;
  const _ApplicantSheet({required this.app});

  @override
  ConsumerState<_ApplicantSheet> createState() => _ApplicantSheetState();
}

class _ApplicantSheetState extends ConsumerState<_ApplicantSheet> {
  late String _status = widget.app.status;
  bool _busy = false;

  Future<void> _set(String status) async {
    setState(() {
      _status = status;
      _busy = true;
    });
    await _guard(context, () async {
      await ref.read(apiProvider).put('/applications/${widget.app.id}', {'status': status});
      ref.invalidate(applicationsProvider);
      ref.invalidate(talentBankProvider);
      ref.invalidate(hrStatsProvider);
    }, done: context.t('common.saved'), pop: false);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.app;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (a.jobTitle.isNotEmpty) InfoRow(icon: Icons.work_outline_rounded, label: context.t('rec.job'), value: a.jobTitle),
      InfoRow(icon: Icons.alternate_email_rounded, label: context.t('common.email'), value: a.email),
      InfoRow(icon: Icons.phone_outlined, label: context.t('common.phone'), value: a.phone ?? ''),
      if (a.coverLetter != null) InfoRow(icon: Icons.notes_rounded, label: context.t('rec.notes'), value: a.coverLetter!),
      const SizedBox(height: 14),
      Text(context.t('rec.stage'), style: TextStyle(color: context.colors.subtext, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in _pipeline)
          ChoiceChip(
            label: Text(context.t('status.$s')),
            selected: _status == s,
            showCheckmark: false,
            onSelected: _busy ? null : (_) => _set(s),
            selectedColor: statusColor(context, s),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _status == s ? Colors.white : null),
          ),
      ]),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: _busy ? null : () async {
        final nav = Navigator.of(context);
        await _set('talent_pool');
        if (mounted) nav.pop();
      }, icon: const Icon(Icons.workspace_premium_rounded), label: Text(context.t('rec.to_talent_pool'))),
      TextButton(
        onPressed: () async {
          if (!await confirmDialog(context, title: context.t('common.delete'), danger: true, confirmLabel: context.t('common.delete'))) return;
          if (!context.mounted) return;
          await _guard(context, () async {
            await ref.read(apiProvider).delete('/applications/${a.id}');
            ref.invalidate(applicationsProvider);
            ref.invalidate(jobsProvider);
          }, done: context.t('common.deleted'));
        },
        child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
      ),
    ]);
  }
}

// ============================================================== talent pool

class TalentPoolScreen extends ConsumerWidget {
  const TalentPoolScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(talentBankProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('rec.talent_pool'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showAppSheet(context, title: context.t('rec.add_candidate'), child: const _CandidateForm()), icon: const Icon(Icons.add_rounded), label: Text(context.t('rec.add_candidate'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(talentBankProvider);
          await ref.read(talentBankProvider.future).catchError((_) => <Candidate>[]);
        },
        child: AsyncBody<List<Candidate>>(
          value: list,
          onRetry: () => ref.invalidate(talentBankProvider),
          builder: (items) {
            if (items.isEmpty) {
              return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.workspace_premium_outlined, title: context.t('rec.no_candidates'), subtitle: context.t('rec.no_candidates_hint')))]);
            }
            final groups = <String, List<Candidate>>{};
            for (final c in items) {
              groups.putIfAbsent(c.departmentName ?? context.t('rec.no_department'), () => []).add(c);
            }
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), physics: const AlwaysScrollableScrollPhysics(), children: [
              for (final g in groups.entries) ...[
                SectionHeader('${g.key} (${g.value.length})', padding: const EdgeInsets.fromLTRB(4, 16, 4, 8)),
                for (final c in g.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RowTile(leading: Avatar(name: c.name, size: 46), title: c.name, subtitle: [if (c.jobTitle != null) c.jobTitle!, c.email].where((s) => s.isNotEmpty).join(' · '), onTap: () => showAppSheet(context, title: c.name, child: _CandidateSheet(c: c))),
                  ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

class _CandidateForm extends ConsumerStatefulWidget {
  const _CandidateForm();

  @override
  ConsumerState<_CandidateForm> createState() => _CandidateFormState();
}

class _CandidateFormState extends ConsumerState<_CandidateForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  int? _dept;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _title, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await _guard(context, () async {
      await ref.read(apiProvider).post('/talent-pool/talent-bank/candidates', {'name': _name.text.trim(), 'email': _email.text.trim(), 'phone': _phone.text.trim(), 'jobTitle': _title.text.trim(), 'departmentId': _dept, 'notes': _notes.text.trim()});
      ref.invalidate(talentBankProvider);
    }, done: context.t('common.saved'));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final depts = ref.watch(departmentsProvider).valueOrNull ?? const <Department>[];
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppField(controller: _name, label: context.t('common.name'), icon: Icons.person_outline_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
        const SizedBox(height: 14),
        AppField(controller: _email, label: context.t('common.email'), icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress),
        const SizedBox(height: 14),
        AppField(controller: _phone, label: context.t('common.phone'), icon: Icons.phone_outlined, keyboard: TextInputType.phone),
        const SizedBox(height: 14),
        AppField(controller: _title, label: context.t('rec.job_title'), icon: Icons.work_outline_rounded),
        const SizedBox(height: 14),
        DropdownButtonFormField<int?>(
          initialValue: _dept,
          decoration: InputDecoration(labelText: context.t('people.department'), prefixIcon: const Icon(Icons.account_tree_outlined)),
          items: [DropdownMenuItem<int?>(value: null, child: Text(context.t('common.none'))), for (final d in depts) DropdownMenuItem<int?>(value: d.id, child: Text(d.name))],
          onChanged: (v) => setState(() => _dept = v),
        ),
        const SizedBox(height: 14),
        AppField(controller: _notes, label: context.t('rec.notes'), icon: Icons.notes_rounded, maxLines: 3),
        const SizedBox(height: 20),
        LoadingButton(label: context.t('common.add'), loading: _busy, onPressed: _save),
      ]),
    );
  }
}

class _CandidateSheet extends ConsumerStatefulWidget {
  final Candidate c;
  const _CandidateSheet({required this.c});

  @override
  ConsumerState<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends ConsumerState<_CandidateSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (c.jobTitle != null) InfoRow(icon: Icons.work_outline_rounded, label: context.t('rec.job_title'), value: c.jobTitle!),
      if (c.departmentName != null) InfoRow(icon: Icons.account_tree_outlined, label: context.t('people.department'), value: c.departmentName!),
      InfoRow(icon: Icons.alternate_email_rounded, label: context.t('common.email'), value: c.email),
      InfoRow(icon: Icons.phone_outlined, label: context.t('common.phone'), value: c.phone ?? ''),
      if (c.notes != null) InfoRow(icon: Icons.notes_rounded, label: context.t('rec.notes'), value: c.notes!),
      const SizedBox(height: 16),
      LoadingButton(
        label: context.t('rec.hire'),
        icon: Icons.how_to_reg_rounded,
        loading: _busy,
        onPressed: c.email.isEmpty
            ? () => toast(context, context.t('rec.hire_needs_email'), error: true)
            : () async {
                setState(() => _busy = true);
                await _guard(context, () async {
                  final data = asMap(await ref.read(apiProvider).post('/talent-pool/candidates/${c.id}/hire-as-employee', {'email': c.email}));
                  ref.invalidate(talentBankProvider);
                  ref.invalidate(employeesProvider);
                  ref.invalidate(hrStatsProvider);
                  final id = jInt(data, 'id');
                  if (context.mounted && id > 0) context.push('/h/employee/$id/edit');
                }, done: context.t('rec.hired_ok'));
                if (mounted) setState(() => _busy = false);
              },
      ),
      TextButton(
        onPressed: () async {
          if (!await confirmDialog(context, title: context.t('common.delete'), danger: true, confirmLabel: context.t('common.delete'))) return;
          if (!context.mounted) return;
          await _guard(context, () async {
            await ref.read(apiProvider).delete('/talent-pool/talent-bank/candidates/${c.id}');
            ref.invalidate(talentBankProvider);
          }, done: context.t('common.deleted'));
        },
        child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
      ),
    ]);
  }
}
