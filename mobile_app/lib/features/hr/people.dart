import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/config.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/suggest_field.dart';
import '../../core/ui/widgets.dart';
import '../common/career_org.dart';
import '../common/directory_screen.dart';
import '../rewards/point_orb.dart';
import 'career_actions.dart';
import '../data/providers.dart';

final _employeeBalanceProvider = FutureProvider.autoDispose.family<List<LeaveBalance>, int>((ref, id) async {
  final m = asMap(await ref.read(apiProvider).get('/leaves/balance', query: {'employeeId': id, 'year': DateTime.now().year}));
  return asMapList(m['balances']).map(LeaveBalance.fromJson).toList();
});

final _employeeSummaryProvider = FutureProvider.autoDispose.family<AttendanceSummary, int>((ref, id) async {
  final now = DateTime.now();
  return AttendanceSummary.fromJson(await ref.read(apiProvider).get('/attendance/summary', query: {'employeeId': id, 'month': now.month, 'year': now.year}));
});

// ====================================================================== list

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  int _filter = 0; // 0 all, 1 active, 2 on leave, 3 inactive

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(employeesProvider(_q));
    const statuses = ['', 'active', 'on_leave', 'inactive'];

    return Scaffold(
      appBar: AppBar(title: Text(context.t('nav.people'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => context.push('/h/employee/new'), icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(context.t('people.add'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: _search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _q = v.trim()));
            },
            decoration: InputDecoration(hintText: context.t('dir.search'), prefixIcon: const Icon(Icons.search_rounded)),
          ),
        ),
        FilterChips(labels: [context.t('common.all'), context.t('status.active'), context.t('status.on_leave'), context.t('status.inactive')], index: _filter, onChanged: (i) => setState(() => _filter = i)),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(employeesProvider(_q));
              await ref.read(employeesProvider(_q).future).catchError((_) => <Employee>[]);
            },
            child: AsyncBody<List<Employee>>(
              value: list,
              onRetry: () => ref.invalidate(employeesProvider(_q)),
              builder: (all) {
                final items = _filter == 0 ? all : all.where((e) => e.status == statuses[_filter]).toList();
                if (items.isEmpty) {
                  return ListView(children: [Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.people_outline_rounded, title: all.isEmpty && _q.isEmpty ? context.t('people.empty') : context.t('common.no_results'), subtitle: all.isEmpty && _q.isEmpty ? context.t('people.empty_hint') : null, actionLabel: all.isEmpty && _q.isEmpty ? context.t('people.add') : null, onAction: () => context.push('/h/employee/new')))]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final e = items[i];
                    return RowTile(
                      leading: Avatar(name: e.fullName, url: e.avatar, size: 48),
                      title: e.fullName,
                      subtitle: [e.position, if (e.departmentName != null) e.departmentName!].where((s) => s.isNotEmpty).join(' · '),
                      trailing: e.status == 'active' ? null : StatusChip(e.status),
                      onTap: () => context.push('/h/employee/${e.id}'),
                    );
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

// ==================================================================== detail

class EmployeeDetailScreen extends ConsumerWidget {
  final int id;
  const EmployeeDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emp = ref.watch(employeeProvider(id));
    final currency = ref.watch(sessionProvider).company?.currency ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('people.profile')),
        actions: [
          IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () async {
            await context.push('/h/employee/$id/edit');
            ref.invalidate(employeeProvider(id));
          }),
        ],
      ),
      body: AsyncBody<Employee>(
        value: emp,
        onRetry: () => ref.invalidate(employeeProvider(id)),
        builder: (e) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(employeeProvider(id));
            ref.invalidate(_employeeBalanceProvider(id));
            ref.invalidate(_employeeSummaryProvider(id));
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), physics: const AlwaysScrollableScrollPhysics(), children: [
            AppCard(
              shadow: true,
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Avatar(name: e.fullName, url: e.avatar, size: 88, ring: true),
                const SizedBox(height: 12),
                Text(e.fullName, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text(e.position.isEmpty ? '—' : e.position, style: TextStyle(color: context.colors.subtext)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
                  StatusChip(e.status),
                  if (e.departmentName != null) Pill(e.departmentName!, icon: Icons.account_tree_rounded, color: context.colors.info),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  _Act(Icons.call_rounded, context.t('dir.call'), context.colors.success, e.phone == null ? null : () => showContactSheet(context, e)),
                  _Act(Icons.chat_rounded, context.t('dir.whatsapp'), const Color(0xFF25D366), e.phone == null ? null : () => showContactSheet(context, e)),
                  _Act(Icons.email_rounded, context.t('dir.email'), context.scheme.primary, () => showContactSheet(context, e)),
                  _Act(Icons.key_rounded, context.t('people.invite'), context.colors.warning, () => showInviteSheet(context, ref, e)),
                  if (e.status != 'inactive') _Act(Icons.trending_up_rounded, context.t('promote.action'), const Color(0xFF8B5CF6), () => showPromoteSheet(context, e)),
                ]),
                if (e.status == 'inactive' && (e.terminationDate != null || e.terminationReason != null)) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: context.colors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                    child: Text('${context.t('terminate.left_on', {'date': e.terminationDate == null ? '—' : fmtDate(context, e.terminationDate!)})}${e.terminationReason == null ? '' : '\n${e.terminationReason}'}', style: TextStyle(color: context.colors.danger, fontWeight: FontWeight.w600, height: 1.4)),
                  ),
                ],
              ]),
            ),
            SectionHeader(context.t('people.employment')),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                InfoRow(icon: Icons.supervisor_account_rounded, label: context.t('me.manager'), value: e.managerName ?? ''),
                InfoRow(icon: Icons.schedule_rounded, label: context.t('me.shift'), value: e.shiftName ?? ''),
                InfoRow(icon: Icons.event_available_rounded, label: context.t('me.joined'), value: e.startDate == null ? '' : fmtDate(context, e.startDate!)),
                InfoRow(icon: Icons.payments_outlined, label: context.t('people.salary'), value: e.salary == null ? '' : money(context, e.salary!, currency)),
              ]),
            ),
            if (ref.watch(sessionProvider).company?.pointsEnabled ?? true) ...[
              SectionHeader(context.t('rewards.title'), action: context.t('common.view_all'), onAction: () => context.push('/h/employee/$id/points', extra: e.fullName)),
              _PointsGlance(id: id),
            ],
            SectionHeader(context.t('career.title'), action: e.status == 'inactive' ? null : context.t('promote.action'), onAction: e.status == 'inactive' ? null : () => showPromoteSheet(context, e)),
            CareerTimeline(employeeId: id),
            SectionHeader(context.t('people.contact')),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                InfoRow(icon: Icons.alternate_email_rounded, label: context.t('common.email'), value: e.email),
                InfoRow(icon: Icons.phone_outlined, label: context.t('common.phone'), value: e.phone ?? ''),
                InfoRow(icon: Icons.home_outlined, label: context.t('emp.address'), value: e.address ?? ''),
                InfoRow(icon: Icons.cake_outlined, label: context.t('emp.birth_date'), value: e.birthDate == null ? '' : fmtDate(context, e.birthDate!)),
                InfoRow(icon: Icons.contact_emergency_outlined, label: context.t('emp.emergency'), value: [e.emergencyName, e.emergencyPhone].whereType<String>().join(' · ')),
              ]),
            ),
            SectionHeader(context.t('home.leave_balance')),
            ref.watch(_employeeBalanceProvider(id)).when(
                  data: (b) => SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: b.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final c = hexColor(b[i].color);
                        return SizedBox(
                          width: 120,
                          child: AppCard(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                            const Spacer(),
                            Text(b[i].unlimited ? '∞' : '${b[i].remaining}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c)),
                            Text(b[i].unlimited ? context.t('req.unlimited') : context.t('req.left_of', {'n': b[i].total}), style: TextStyle(color: context.colors.subtext, fontSize: 11)),
                          ])),
                        );
                      },
                    ),
                  ),
                  loading: () => const Skeleton(height: 96, radius: 20),
                  error: (e, _) => ErrorState(e),
                ),
            SectionHeader(context.t('people.attendance_month')),
            ref.watch(_employeeSummaryProvider(id)).when(
                  data: (s) => Row(children: [
                    Expanded(child: _Mini('${s.present + s.late + s.half}', context.t('time.s.present'), context.colors.success)),
                    const SizedBox(width: 8),
                    Expanded(child: _Mini('${s.late}', context.t('time.s.late'), context.colors.warning)),
                    const SizedBox(width: 8),
                    Expanded(child: _Mini('${s.half}', context.t('status.half_day'), statusColor(context, 'half_day'))),
                    const SizedBox(width: 8),
                    Expanded(child: _Mini('${s.absent}', context.t('time.s.absent'), context.colors.danger)),
                    const SizedBox(width: 8),
                    Expanded(child: _Mini('${s.leave}', context.t('time.s.leave'), context.colors.info)),
                    const SizedBox(width: 8),
                    Expanded(child: _Mini(s.hours.toStringAsFixed(0), context.t('time.s.hours'), context.scheme.primary)),
                  ]),
                  loading: () => const Skeleton(height: 70, radius: 20),
                  error: (e, _) => ErrorState(e),
                ),
            const SizedBox(height: 16),
            AppCard(
              onTap: () => context.push('/h/employee/$id/documents', extra: e.fullName),
              child: Row(children: [
                IconBadge(Icons.folder_copy_rounded, color: context.colors.warning),
                const SizedBox(width: 14),
                Expanded(child: Text(context.t('home.qa.documents'), style: const TextStyle(fontWeight: FontWeight.w700))),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
            const SizedBox(height: 12),
            if (e.status != 'inactive')
              OutlinedButton.icon(
                onPressed: () => showTerminateSheet(context, e),
                icon: Icon(Icons.person_off_rounded, color: context.colors.danger),
                label: Text(context.t('people.deactivate'), style: TextStyle(color: context.colors.danger)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: context.colors.danger.withValues(alpha: 0.4))),
              )
            else
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await ref.read(apiProvider).post('/employees/$id/reinstate');
                    ref.invalidate(employeeProvider(id));
                    ref.invalidate(employeesProvider);
                  } on ApiException catch (err) {
                    if (context.mounted) toast(context, err.message, error: true);
                  }
                },
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(context.t('people.reactivate')),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Compact points line on an employee's profile.
class _PointsGlance extends ConsumerWidget {
  final int id;
  const _PointsGlance({required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pts = ref.watch(employeePointsProvider(id));
    return pts.when(
      loading: () => const Skeleton(height: 84, radius: 20),
      error: (e, _) => const SizedBox.shrink(),
      data: (s) {
        if (!s.enabled) return const SizedBox.shrink();
        return AppCard(
          onTap: () => context.push('/h/employee/$id/points'),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            for (final k in PointKind.values)
              Expanded(
                child: Column(children: [
                  Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(center: const Alignment(-0.3, -0.4), colors: [k.light, k.base, k.dark], stops: const [0, 0.55, 1]))),
                  const SizedBox(height: 4),
                  Text('${k == PointKind.green ? s.netGreen : k == PointKind.red ? s.netRed : s.netBlack}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ]),
              ),
            Container(width: 1, height: 40, color: context.colors.border),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${context.t('rewards.level')} ${s.level}${s.levelName.isEmpty ? '' : ' · ${s.levelName}'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(context.t('rewards.streak_days', {'n': s.streak, 'target': s.streakTarget}), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Act extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _Act(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: Column(children: [
              Container(width: 52, height: 52, decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: color)),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
            ]),
          ),
        ),
      );
}

class _Mini extends StatelessWidget {
  final String v;
  final String l;
  final Color c;
  const _Mini(this.v, this.l, this.c);

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(children: [Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 20)), Text(l, style: TextStyle(color: context.colors.subtext, fontSize: 11), maxLines: 1)]),
      );
}

// ================================================================ invite code

/// Generates a one-time code for the employee and lets HR copy / share it.
Future<void> showInviteSheet(BuildContext context, WidgetRef ref, Employee e, {String? existingCode, bool sendEmail = false, bool? emailed}) async {
  String? code = existingCode;
  String purpose = 'activate';
  if (code == null) {
    try {
      final m = asMap(await ref.read(apiProvider).post('/employees/${e.id}/invite', sendEmail ? {'sendEmail': true} : null));
      code = jStr(m, 'code');
      purpose = jStr(m, 'purpose', 'activate');
      if (sendEmail) emailed = m['emailed'] == true;
    } on ApiException catch (err) {
      if (context.mounted) toast(context, err.message, error: true);
      return;
    }
  }
  if (!context.mounted) return;
  final finalCode = code;
  final message = context.t('invite.message', {'name': e.firstName, 'email': e.email, 'code': finalCode, 'link': '${AppConfig.baseUrl}/app/alanad/AlAnad-HR.apk'});
  await showAppSheet(
    context,
    title: purpose == 'reset' ? context.t('invite.reset_title') : context.t('invite.title'),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(purpose == 'reset' ? context.t('invite.reset_hint', {'name': e.firstName}) : context.t('invite.hint', {'name': e.firstName}), style: TextStyle(color: context.colors.subtext, height: 1.4)),
      if (emailed != null) ...[
        const SizedBox(height: 10),
        Pill(emailed ? context.t('invite.emailed', {'email': e.email}) : context.t('invite.email_failed'), color: emailed ? context.colors.success : context.colors.warning, icon: emailed ? Icons.mark_email_read_outlined : Icons.mail_outline_rounded),
      ],
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(color: context.colors.brandSoft, borderRadius: BorderRadius.circular(20)),
        child: Center(child: Text(finalCode.split('').join(' '), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4, color: context.scheme.primary))),
      ),
      const SizedBox(height: 10),
      Center(child: Text(context.t('invite.expires', {'n': purpose == 'reset' ? 1 : 7}), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () {
          Clipboard.setData(ClipboardData(text: finalCode));
          toast(context, context.t('common.copied'));
        }, icon: const Icon(Icons.copy_rounded), label: Text(context.t('common.copy')))),
        const SizedBox(width: 12),
        Expanded(child: FilledButton.icon(onPressed: () => Share.share(message), icon: const Icon(Icons.share_rounded), label: Text(context.t('common.share')))),
      ]),
      if (e.email.contains('@') && emailed != true) ...[
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            showInviteSheet(context, ref, e, sendEmail: true);
          },
          icon: const Icon(Icons.mail_outline_rounded),
          label: Text(context.t('invite.email_new')),
        ),
      ],
    ]),
  );
}

// ====================================================================== form

class EmployeeFormScreen extends ConsumerStatefulWidget {
  final int? id; // null = create
  final int? initialDepartment;
  const EmployeeFormScreen({super.key, this.id, this.initialDepartment});

  @override
  ConsumerState<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _form = GlobalKey<FormState>();
  bool _sendEmail = false;
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _position = TextEditingController();
  final _salary = TextEditingController();
  final _address = TextEditingController();
  final _emName = TextEditingController();
  final _emPhone = TextEditingController();
  late int? _dept = widget.initialDepartment;
  int? _manager;
  int? _shift;
  DateTime? _start = DateTime.now();
  DateTime? _birth;
  String? _gender;
  String _status = 'active';
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_first, _last, _email, _phone, _position, _salary, _address, _emName, _emPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Employee e) {
    if (_loaded) return;
    _loaded = true;
    _first.text = e.firstName;
    _last.text = e.lastName;
    _email.text = e.email;
    _phone.text = e.phone ?? '';
    _position.text = e.position;
    _salary.text = e.salary == null ? '' : e.salary!.toStringAsFixed(e.salary! == e.salary!.roundToDouble() ? 0 : 2);
    _address.text = e.address ?? '';
    _emName.text = e.emergencyName ?? '';
    _emPhone.text = e.emergencyPhone ?? '';
    _dept = e.departmentId;
    _manager = e.managerId;
    _shift = e.shiftId;
    _start = e.startDate;
    _birth = e.birthDate;
    _gender = e.gender;
    _status = e.status;
  }

  Future<void> _pick(DateTime? initial, ValueChanged<DateTime> done, {DateTime? first, DateTime? last}) async {
    final d = await showDatePicker(context: context, initialDate: initial ?? DateTime.now(), firstDate: first ?? DateTime(1940), lastDate: last ?? DateTime(2100));
    if (d != null) setState(() => done(d));
  }

  String _deptName() => (ref.read(departmentsProvider).valueOrNull ?? const <Department>[]).where((d) => d.id == _dept).map((d) => d.name).firstOrNull ?? '';
  List<String> _titlesIn() => (ref.read(employeesProvider('')).valueOrNull ?? const <Employee>[]).where((p) => p.departmentId == _dept && p.position.isNotEmpty).map((p) => p.position).toList();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!await confirmNewTitle(context, _position.text, _deptName(), _titlesIn())) return;     // a title that is not in the list: ask first
    setState(() => _busy = true);
    final editing = widget.id != null;
    final body = <String, dynamic>{
      'firstName': _first.text.trim(),
      'lastName': _last.text.trim(),
      'email': _email.text.trim().toLowerCase(),
      'phone': _phone.text.trim(),
      'position': _position.text.trim(),
      'departmentId': _dept,
      'managerId': _manager,
      'shiftId': _shift,
      'startDate': _start == null ? null : ymd(_start!),
      'salary': _salary.text.trim().isEmpty ? null : double.tryParse(_salary.text.trim()),
      'birthDate': _birth == null ? '' : ymd(_birth!),
      'gender': _gender ?? '',
      'address': _address.text.trim(),
      'emergencyName': _emName.text.trim(),
      'emergencyPhone': _emPhone.text.trim(),
      if (editing) 'status': _status,
      if (!editing && _sendEmail) 'sendEmail': true,
    };
    try {
      final api = ref.read(apiProvider);
      final data = editing ? await api.put('/employees/${widget.id}', body) : await api.post('/employees', body);
      ref.invalidate(employeesProvider);
      ref.invalidate(hrStatsProvider);
      ref.invalidate(directoryProvider);
      if (widget.id != null) ref.invalidate(employeeProvider(widget.id!));
      if (!mounted) return;
      final created = Employee.fromJson(data);
      if (!editing && created.inviteCode != null) {
        await showInviteSheet(context, ref, created, existingCode: created.inviteCode, emailed: _sendEmail ? asMap(data)['emailed'] == true : null);
      } else {
        toast(context, context.t('common.saved'));
      }
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.id != null;
    final depts = ref.watch(departmentsProvider).valueOrNull ?? const <Department>[];
    final shifts = ref.watch(shiftsProvider).valueOrNull ?? const <Shift>[];
    final people = ref.watch(employeesProvider('')).valueOrNull ?? const <Employee>[];
    final AsyncValue<Employee?> async = editing ? ref.watch(employeeProvider(widget.id!)).whenData<Employee?>((e) => e) : const AsyncData<Employee?>(null);
    if (editing && async.hasValue && async.value != null) _fill(async.value!);

    if (editing && !async.hasValue) {
      return Scaffold(appBar: AppBar(title: Text(context.t('people.edit'))), body: async.hasError ? ErrorState(async.error!, onRetry: () => ref.invalidate(employeeProvider(widget.id!))) : const SkeletonList(count: 4));
    }

    Widget date(String label, IconData icon, DateTime? v, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: InputDecorator(decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)), child: Text(v == null ? '—' : fmtDate(context, v))),
        );

    return Scaffold(
      appBar: AppBar(title: Text(editing ? context.t('people.edit') : context.t('people.add'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          Row(children: [
            Expanded(child: AppField(controller: _first, label: context.t('people.first_name'), capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v))),
            const SizedBox(width: 12),
            Expanded(child: AppField(controller: _last, label: context.t('people.last_name'), capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v))),
          ]),
          const SizedBox(height: 14),
          AppField(controller: _email, label: context.t('auth.email.label'), icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress, validator: (v) => emailValidator(context, v)),
          if (widget.id == null) SwitchListTile(contentPadding: EdgeInsets.zero, value: _sendEmail, onChanged: (v) => setState(() => _sendEmail = v), title: Text(context.t('invite.email_toggle'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          const SizedBox(height: 14),
          AppField(controller: _phone, label: context.t('common.phone'), icon: Icons.phone_outlined, keyboard: TextInputType.phone),
          SectionHeader(context.t('people.employment')),
          titleSuggestField(context, _position, label: context.t('emp.position'), department: _deptName, existing: _titlesIn),
          const SizedBox(height: 14),
          DropdownButtonFormField<int?>(
            initialValue: depts.any((d) => d.id == _dept) ? _dept : null,
            decoration: InputDecoration(labelText: context.t('people.department'), prefixIcon: const Icon(Icons.account_tree_outlined)),
            items: [DropdownMenuItem<int?>(value: null, child: Text(context.t('common.none'))), for (final d in depts) DropdownMenuItem<int?>(value: d.id, child: Text(d.name))],
            onChanged: (v) => setState(() => _dept = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int?>(
            initialValue: people.any((p) => p.id == _manager && p.id != widget.id) ? _manager : null,
            decoration: InputDecoration(labelText: context.t('me.manager'), prefixIcon: const Icon(Icons.supervisor_account_outlined)),
            items: [DropdownMenuItem<int?>(value: null, child: Text(context.t('common.none'))), for (final p in people.where((p) => p.id != widget.id && p.status != 'inactive')) DropdownMenuItem<int?>(value: p.id, child: Text(p.fullName))],
            onChanged: (v) => setState(() => _manager = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int?>(
            initialValue: shifts.any((s) => s.id == _shift) ? _shift : null,
            decoration: InputDecoration(labelText: context.t('me.shift'), prefixIcon: const Icon(Icons.schedule_rounded)),
            items: [DropdownMenuItem<int?>(value: null, child: Text(context.t('common.none'))), for (final s in shifts) DropdownMenuItem<int?>(value: s.id, child: Text('${s.name} (${s.startTime.length >= 5 ? s.startTime.substring(0, 5) : s.startTime}–${s.endTime.length >= 5 ? s.endTime.substring(0, 5) : s.endTime})'))],
            onChanged: (v) => setState(() => _shift = v),
          ),
          const SizedBox(height: 14),
          date(context.t('me.joined'), Icons.event_available_rounded, _start, () => _pick(_start, (d) => _start = d)),
          const SizedBox(height: 14),
          AppField(controller: _salary, label: context.t('people.salary'), icon: Icons.payments_outlined, keyboard: const TextInputType.numberWithOptions(decimal: true)),
          if (editing) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(labelText: context.t('common.status'), prefixIcon: const Icon(Icons.toggle_on_outlined)),
              items: [for (final s in ['active', 'on_leave', 'inactive']) DropdownMenuItem(value: s, child: Text(context.t('status.$s')))],
              onChanged: (v) => setState(() => _status = v ?? 'active'),
            ),
          ],
          SectionHeader(context.t('people.personal')),
          date(context.t('emp.birth_date'), Icons.cake_outlined, _birth, () => _pick(_birth ?? DateTime(1995), (d) => _birth = d, last: DateTime.now())),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: InputDecoration(labelText: context.t('emp.gender'), prefixIcon: const Icon(Icons.wc_rounded)),
            items: [DropdownMenuItem(value: 'male', child: Text(context.t('emp.male'))), DropdownMenuItem(value: 'female', child: Text(context.t('emp.female')))],
            onChanged: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 14),
          AppField(controller: _address, label: context.t('emp.address'), icon: Icons.home_outlined, maxLines: 2),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: AppField(controller: _emName, label: context.t('emp.emergency_name'))),
            const SizedBox(width: 12),
            Expanded(child: AppField(controller: _emPhone, label: context.t('emp.emergency_phone'), keyboard: TextInputType.phone)),
          ]),
          const SizedBox(height: 26),
          LoadingButton(label: editing ? context.t('common.save') : context.t('people.create'), loading: _busy, onPressed: _save),
          if (!editing) Padding(padding: const EdgeInsets.only(top: 12), child: Text(context.t('people.invite_after'), textAlign: TextAlign.center, style: TextStyle(color: context.colors.subtext, fontSize: 12))),
        ]),
      ),
    );
  }
}
