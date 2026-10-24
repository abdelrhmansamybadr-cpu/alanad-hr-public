import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';
import '../premium/chain_widgets.dart';

const _requestTypes = ['expense', 'certificate', 'attendance_correction', 'equipment', 'other'];

IconData requestIcon(String type) {
  switch (type) {
    case 'expense':
      return Icons.payments_rounded;
    case 'certificate':
      return Icons.description_rounded;
    case 'attendance_correction':
      return Icons.edit_calendar_rounded;
    case 'profile_change':
      return Icons.manage_accounts_rounded;
    case 'equipment':
      return Icons.laptop_mac_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  int _tab = 0;

  static const _mine = (scope: 'mine', status: '');

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final leaves = ref.watch(leavesProvider(_mine));
    final requests = ref.watch(requestsProvider(_mine));
    final balances = ref.watch(leaveBalanceProvider(year));

    Future<void> refresh() async {
      ref.invalidate(leavesProvider(_mine));
      ref.invalidate(requestsProvider(_mine));
      ref.invalidate(leaveBalanceProvider(year));
      await Future.wait([ref.read(leavesProvider(_mine).future).catchError((_) => <LeaveItem>[]), ref.read(requestsProvider(_mine).future).catchError((_) => <RequestItem>[])]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.t('req.title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tab == 0 ? showLeaveForm(context) : showRequestForm(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(_tab == 0 ? context.t('req.new_leave') : context.t('req.new_request')),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SegmentBar(labels: [context.t('req.tab_leave'), context.t('req.tab_other')], index: _tab, onChanged: (i) => setState(() => _tab = i))),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: _tab == 0
                ? AsyncBody<List<LeaveItem>>(
                    value: leaves,
                    onRetry: () => ref.invalidate(leavesProvider(_mine)),
                    builder: (items) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), physics: const AlwaysScrollableScrollPhysics(), children: [
                      balances.maybeWhen(data: (b) => _BalanceStrip(balances: b), orElse: () => const SizedBox.shrink()),
                      if (items.isEmpty)
                        Padding(padding: const EdgeInsets.only(top: 40), child: EmptyState(icon: Icons.beach_access_rounded, title: context.t('req.no_leaves'), subtitle: context.t('req.no_leaves_hint')))
                      else
                        ...items.map((l) => Padding(padding: const EdgeInsets.only(bottom: 10), child: LeaveTile(leave: l, onTap: () => showLeaveDetail(context, ref, l)))),
                    ]),
                  )
                : AsyncBody<List<RequestItem>>(
                    value: requests,
                    onRetry: () => ref.invalidate(requestsProvider(_mine)),
                    builder: (items) => items.isEmpty
                        ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.inbox_rounded, title: context.t('req.no_requests'), subtitle: context.t('req.no_requests_hint')))])
                        : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), physics: const AlwaysScrollableScrollPhysics(), children: items.map((r) => Padding(padding: const EdgeInsets.only(bottom: 10), child: RequestTile(item: r, onTap: () => showRequestDetail(context, ref, r)))).toList()),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _BalanceStrip extends StatelessWidget {
  final List<LeaveBalance> balances;
  const _BalanceStrip({required this.balances});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: balances.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final b = balances[i];
              final c = hexColor(b.color);
              return SizedBox(
                width: 132,
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 6), Expanded(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                    const Spacer(),
                    Text(b.unlimited ? '∞' : '${b.remaining ?? 0}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c)),
                    Text(b.unlimited ? context.t('req.unlimited') : context.t('req.left_of', {'n': b.total}), style: TextStyle(color: context.colors.subtext, fontSize: 11)),
                  ]),
                ),
              );
            },
          ),
        ),
      );
}

// ===================================================================== tiles

class LeaveTile extends StatelessWidget {
  final LeaveItem leave;
  final VoidCallback? onTap;
  final bool showEmployee;
  const LeaveTile({super.key, required this.leave, this.onTap, this.showEmployee = false});

  @override
  Widget build(BuildContext context) {
    final color = hexColor(leave.typeColor);
    return RowTile(
      onTap: onTap,
      leading: showEmployee ? Avatar(name: leave.employeeName, url: leave.employeeAvatar, size: 46) : IconBadge(Icons.beach_access_rounded, color: color, size: 46),
      title: showEmployee ? leave.employeeName : leave.typeName,
      subtitle: showEmployee ? '${leave.typeName} · ${leave.days == 1 ? context.t('common.day') : context.t('common.days', {'n': leave.days})}\n${fmtRange(context, leave.start, leave.end)}' : '${fmtRange(context, leave.start, leave.end)} · ${leave.days == 1 ? context.t('common.day') : context.t('common.days', {'n': leave.days})}',
      trailing: chainStatusChip(context, leave.status, leave.headStatus),
    );
  }
}

class RequestTile extends StatelessWidget {
  final RequestItem item;
  final VoidCallback? onTap;
  final bool showEmployee;
  const RequestTile({super.key, required this.item, this.onTap, this.showEmployee = false});

  @override
  Widget build(BuildContext context) {
    final currency = ProviderScope.containerOf(context).read(sessionProvider).company?.currency ?? '';
    final sub = [
      if (showEmployee) item.employeeName,
      context.t('req.type.${item.type}'),
      if (item.amount != null) money(context, item.amount!, currency),
    ].join(' · ');
    return RowTile(
      onTap: onTap,
      leading: IconBadge(requestIcon(item.type), color: context.scheme.primary, size: 46),
      title: item.title,
      subtitle: sub,
      trailing: chainStatusChip(context, item.status, item.headStatus),
    );
  }
}

// ====================================================================== details

Future<void> showLeaveDetail(BuildContext context, WidgetRef ref, LeaveItem l, {bool canReview = false}) {
  return showAppSheet(
    context,
    title: l.typeName,
    child: _LeaveDetail(leave: l, canReview: canReview),
  );
}

class _LeaveDetail extends ConsumerStatefulWidget {
  final LeaveItem leave;
  final bool canReview;
  const _LeaveDetail({required this.leave, required this.canReview});

  @override
  ConsumerState<_LeaveDetail> createState() => _LeaveDetailState();
}

class _LeaveDetailState extends ConsumerState<_LeaveDetail> {
  bool _busy = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(String status, {bool skip = false}) async {
    if (skip && _note.text.trim().length < 3) {
      toast(context, context.t('chain.note_needed'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/leaves/${widget.leave.id}', {'status': status, if (_note.text.trim().isNotEmpty) 'reviewNote': _note.text.trim(), if (skip) 'skipHead': true});
      ref.invalidate(leavesProvider);
      ref.invalidate(leaveBalanceProvider);
      ref.invalidate(myStatsProvider);
      ref.invalidate(hrStatsProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, context.t(status == 'approved' ? 'approvals.approved_ok' : status == 'rejected' ? 'approvals.rejected_ok' : 'req.cancelled_ok'));
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.leave;
    final me = ref.watch(sessionProvider).user!;
    final isOwner = l.employeeId == me.employeeId;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Avatar(name: l.employeeName, url: l.employeeAvatar, size: 44),
        const SizedBox(width: 12),
        Expanded(child: Text(l.employeeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        StatusChip(l.status),
      ]),
      const SizedBox(height: 8),
      InfoRow(icon: Icons.event_rounded, label: context.t('req.dates'), value: fmtRange(context, l.start, l.end)),
      InfoRow(icon: Icons.timelapse_rounded, label: context.t('req.working_days'), value: '${l.days}'),
      if (l.reason != null) InfoRow(icon: Icons.notes_rounded, label: context.t('req.reason'), value: l.reason!),
      if (l.reviewedBy != null) InfoRow(icon: Icons.verified_user_rounded, label: context.t('req.reviewed_by'), value: l.reviewedBy!),
      if (l.reviewNote != null) InfoRow(icon: Icons.comment_rounded, label: context.t('common.note'), value: l.reviewNote!),
      ChainBanner(headStatus: l.headStatus, status: l.status),
      const SizedBox(height: 16),
      if (widget.canReview && l.status == 'pending' && !isOwner && !(l.headStatus == 'approved' && !me.isHr)) ...[
        AppField(controller: _note, label: l.headStatus == 'pending' && me.isHr ? context.t('chain.skip_reason') : context.t('approvals.note'), icon: Icons.comment_outlined, maxLines: 2),
        if (l.headStatus == 'pending' && me.isHr) Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.t('chain.skip_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: LoadingButton(label: context.t('approvals.reject'), outlined: true, loading: _busy, onPressed: () => _decide('rejected', skip: l.headStatus == 'pending' && me.isHr))),
          const SizedBox(width: 12),
          Expanded(child: LoadingButton(label: l.headStatus == 'pending' ? (me.isHr ? context.t('chain.approve_skip') : context.t('chain.approve_to_hr')) : context.t('approvals.approve'), loading: _busy, onPressed: () => _decide('approved', skip: l.headStatus == 'pending' && me.isHr))),
        ]),
      ] else if (isOwner && l.status == 'pending')
        LoadingButton(label: context.t('req.cancel_request'), outlined: true, loading: _busy, onPressed: () async {
          if (await confirmDialog(context, title: context.t('req.cancel_request'), message: context.t('req.cancel_confirm'), danger: true)) _decide('cancelled');
        }),
    ]);
  }
}

Future<void> showRequestDetail(BuildContext context, WidgetRef ref, RequestItem r, {bool canReview = false}) {
  return showAppSheet(context, title: r.title, child: _RequestDetail(item: r, canReview: canReview));
}

class _RequestDetail extends ConsumerStatefulWidget {
  final RequestItem item;
  final bool canReview;
  const _RequestDetail({required this.item, required this.canReview});

  @override
  ConsumerState<_RequestDetail> createState() => _RequestDetailState();
}

class _RequestDetailState extends ConsumerState<_RequestDetail> {
  bool _busy = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(String status, {bool skip = false}) async {
    if (skip && _note.text.trim().length < 3) {
      toast(context, context.t('chain.note_needed'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/requests/${widget.item.id}', {'status': status, if (_note.text.trim().isNotEmpty) 'reviewNote': _note.text.trim(), if (skip) 'skipHead': true});
      ref.invalidate(requestsProvider);
      ref.invalidate(hrStatsProvider);
      ref.invalidate(myStatsProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, context.t(status == 'approved' ? 'approvals.approved_ok' : status == 'rejected' ? 'approvals.rejected_ok' : 'req.cancelled_ok'));
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.item;
    final me = ref.watch(sessionProvider).user!;
    final currency = ref.watch(sessionProvider).company?.currency ?? '';
    final isOwner = r.employeeId == me.employeeId;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Avatar(name: r.employeeName, url: r.employeeAvatar, size: 44),
        const SizedBox(width: 12),
        Expanded(child: Text(r.employeeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        StatusChip(r.status),
      ]),
      const SizedBox(height: 8),
      InfoRow(icon: requestIcon(r.type), label: context.t('req.type'), value: context.t('req.type.${r.type}')),
      if (r.amount != null) InfoRow(icon: Icons.payments_outlined, label: context.t('req.amount'), value: money(context, r.amount!, currency)),
      if (r.type == 'profile_change') _ChangesView(payload: r.payload),
      if (r.type == 'attendance_correction') _CorrectionView(payload: r.payload),
      if (r.description != null && r.type != 'profile_change') InfoRow(icon: Icons.notes_rounded, label: context.t('req.details'), value: r.description!),
      if (r.createdAt != null) InfoRow(icon: Icons.schedule_rounded, label: context.t('req.sent'), value: fmtDate(context, r.createdAt!)),
      if (r.reviewNote != null) InfoRow(icon: Icons.comment_rounded, label: context.t('common.note'), value: r.reviewNote!),
      ChainBanner(headStatus: r.headStatus, status: r.status),
      const SizedBox(height: 16),
      if (widget.canReview && r.status == 'pending' && !isOwner && !(r.headStatus == 'approved' && !me.isHr)) ...[
        AppField(controller: _note, label: r.headStatus == 'pending' && me.isHr ? context.t('chain.skip_reason') : context.t('approvals.note'), icon: Icons.comment_outlined, maxLines: 2),
        if (r.headStatus == 'pending' && me.isHr) Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.t('chain.skip_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: LoadingButton(label: context.t('approvals.reject'), outlined: true, loading: _busy, onPressed: () => _decide('rejected', skip: r.headStatus == 'pending' && me.isHr))),
          const SizedBox(width: 12),
          Expanded(child: LoadingButton(label: r.headStatus == 'pending' ? (me.isHr ? context.t('chain.approve_skip') : context.t('chain.approve_to_hr')) : context.t('approvals.approve'), loading: _busy, onPressed: () => _decide('approved', skip: r.headStatus == 'pending' && me.isHr))),
        ]),
      ] else if (isOwner && r.status == 'pending')
        LoadingButton(label: context.t('req.cancel_request'), outlined: true, loading: _busy, onPressed: () async {
          if (await confirmDialog(context, title: context.t('req.cancel_request'), message: context.t('req.cancel_confirm'), danger: true)) _decide('cancelled');
        }),
    ]);
  }
}

// ====================================================================== forms

Future<void> showLeaveForm(BuildContext context) => showAppSheet(context, title: context.t('req.new_leave'), child: const _LeaveForm());

class _LeaveForm extends ConsumerStatefulWidget {
  const _LeaveForm();

  @override
  ConsumerState<_LeaveForm> createState() => _LeaveFormState();
}

class _LeaveFormState extends ConsumerState<_LeaveForm> {
  String? _type;
  DateTimeRange? _range;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int _workingDays(List<String> weekend, Set<String> holidays) {
    if (_range == null) return 0;
    const dow = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    var n = 0;
    for (var d = _range!.start; !d.isAfter(_range!.end); d = d.add(const Duration(days: 1))) {
      if (!weekend.contains(dow[d.weekday - 1]) && !holidays.contains(ymd(d))) n++;
    }
    return n;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      builder: (ctx, child) => Directionality(textDirection: Directionality.of(context), child: child!),
    );
    if (r != null) {
      // the server does not accept a request across two calendar years
      final end = r.start.year != r.end.year ? DateTime(r.start.year, 12, 31) : r.end;
      setState(() => _range = DateTimeRange(start: r.start, end: end));
    }
  }

  Future<void> _submit() async {
    if (_type == null) return setState(() => _error = context.t('req.pick_type'));
    if (_range == null) return setState(() => _error = context.t('req.pick_dates'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).post('/leaves', {'type': _type, 'startDate': ymd(_range!.start), 'endDate': ymd(_range!.end), if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim()});
      ref.invalidate(leavesProvider);
      ref.invalidate(leaveBalanceProvider);
      ref.invalidate(myStatsProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, context.t('req.leave_sent'));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(leaveTypesProvider);
    final balances = ref.watch(leaveBalanceProvider(DateTime.now().year)).valueOrNull ?? const <LeaveBalance>[];
    final weekend = ref.watch(sessionProvider).company?.weekendDays ?? const ['fri', 'sat'];
    final holidays = {for (final h in ref.watch(holidaysProvider(_range?.start.year ?? DateTime.now().year)).valueOrNull ?? const <Holiday>[]) ymd(h.date)};
    final days = _workingDays(weekend, holidays);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.t('req.type_label'), style: TextStyle(color: context.colors.subtext, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      types.when(
        data: (list) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in list)
            ChoiceChip(
              selected: _type == t.code,
              onSelected: (_) => setState(() => _type = t.code),
              showCheckmark: false,
              avatar: CircleAvatar(radius: 5, backgroundColor: hexColor(t.color)),
              label: Text('${t.name}${_remaining(balances, t.code)}'),
            ),
        ]),
        loading: () => const Skeleton(height: 40),
        error: (e, _) => Text(errorText(context, e)),
      ),
      const SizedBox(height: 18),
      InkWell(
        onTap: _pickRange,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(labelText: context.t('req.dates'), prefixIcon: const Icon(Icons.event_rounded)),
          child: Text(_range == null ? context.t('req.select_dates') : fmtRange(context, _range!.start, _range!.end), style: TextStyle(color: _range == null ? context.colors.subtext : null)),
        ),
      ),
      if (_range != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, size: 16, color: context.scheme.primary),
            const SizedBox(width: 6),
            Text(days == 0 ? context.t('req.no_working_days') : context.t('req.working_preview', {'n': days}), style: TextStyle(color: days == 0 ? context.colors.danger : context.scheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
      const SizedBox(height: 14),
      AppField(controller: _reason, label: '${context.t('req.reason')} (${context.t('common.optional')})', icon: Icons.notes_rounded, maxLines: 3),
      if (_error != null) ...[
        const SizedBox(height: 14),
        Text(_error!, style: TextStyle(color: context.colors.danger, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 20),
      LoadingButton(label: context.t('req.submit'), loading: _busy, onPressed: _submit),
    ]);
  }

  String _remaining(List<LeaveBalance> b, String code) {
    for (final x in b) {
      if (x.code == code && x.remaining != null) return ' · ${x.remaining}';
    }
    return '';
  }
}

Future<void> showRequestForm(BuildContext context) => showAppSheet(context, title: context.t('req.new_request'), child: const _RequestForm());

class _RequestForm extends ConsumerStatefulWidget {
  const _RequestForm();

  @override
  ConsumerState<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends ConsumerState<_RequestForm> {
  final _form = GlobalKey<FormState>();
  String _type = 'expense';
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  bool _busy = false;
  String? _error;
  DateTime _corrDate = DateTime.now().subtract(const Duration(days: 1));
  TimeOfDay? _corrIn;
  TimeOfDay? _corrOut;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final correction = _type == 'attendance_correction';
    if (!_form.currentState!.validate()) return;
    if (correction && _corrIn == null) return setState(() => _error = context.t('req.corr_need_in'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).post('/requests', {
        'type': _type,
        'title': correction ? '${context.t('req.type.attendance_correction')} · ${ymd(_corrDate)}' : _title.text.trim(),
        if (_desc.text.trim().isNotEmpty && !correction) 'description': _desc.text.trim(),
        if (_type == 'expense') 'amount': double.tryParse(_amount.text.trim()),
        if (correction) 'payload': {'date': ymd(_corrDate), 'check_in': _hhmm(_corrIn!), if (_corrOut != null) 'check_out': _hhmm(_corrOut!), 'reason': _desc.text.trim()},
      });
      ref.invalidate(requestsProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, context.t('req.request_sent'));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).company?.currency ?? '';
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in _requestTypes)
            ChoiceChip(selected: _type == t, onSelected: (_) => setState(() => _type = t), showCheckmark: false, avatar: Icon(requestIcon(t), size: 18), label: Text(context.t('req.type.$t'))),
        ]),
        const SizedBox(height: 18),
        if (_type == 'attendance_correction') ...[
          Text(context.t('req.corr_hint'), style: TextStyle(color: context.colors.subtext, height: 1.4)),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _corrDate, firstDate: DateTime.now().subtract(const Duration(days: 45)), lastDate: DateTime.now());
              if (d != null) setState(() => _corrDate = d);
            },
            child: InputDecorator(decoration: InputDecoration(labelText: context.t('req.corr_date'), prefixIcon: const Icon(Icons.event_rounded)), child: Text(fmtDate(context, _corrDate))),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _corrIn ?? const TimeOfDay(hour: 9, minute: 0));
                  if (t != null) setState(() => _corrIn = t);
                },
                child: InputDecorator(decoration: InputDecoration(labelText: context.t('req.corr_in'), prefixIcon: const Icon(Icons.login_rounded)), child: Text(_corrIn == null ? '—' : _corrIn!.format(context))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _corrOut ?? const TimeOfDay(hour: 17, minute: 0));
                  if (t != null) setState(() => _corrOut = t);
                },
                child: InputDecorator(decoration: InputDecoration(labelText: context.t('req.corr_out'), prefixIcon: const Icon(Icons.logout_rounded)), child: Text(_corrOut == null ? '—' : _corrOut!.format(context))),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          AppField(controller: _desc, label: context.t('req.corr_reason'), icon: Icons.notes_rounded, maxLines: 3, validator: (v) => requiredValidator(context, v)),
        ] else
          AppField(controller: _title, label: context.t('req.title_label'), icon: Icons.title_rounded, capitalization: TextCapitalization.sentences, validator: (v) => requiredValidator(context, v)),
        if (_type == 'expense') ...[
          const SizedBox(height: 14),
          AppField(controller: _amount, label: '${context.t('req.amount')} ($currency)', icon: Icons.payments_outlined, keyboard: const TextInputType.numberWithOptions(decimal: true), validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) > 0 ? null : context.t('common.required')),
        ],
        if (_type != 'attendance_correction') ...[
          const SizedBox(height: 14),
          AppField(controller: _desc, label: '${context.t('req.details')} (${context.t('common.optional')})', icon: Icons.notes_rounded, maxLines: 3),
        ],
        if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: TextStyle(color: context.colors.danger, fontWeight: FontWeight.w600))],
        const SizedBox(height: 20),
        LoadingButton(label: context.t('req.submit'), loading: _busy, onPressed: _submit),
      ]),
    );
  }
}


// ============================================================ payload views

String _fieldLabel(BuildContext context, String key) {
  switch (key) {
    case 'first_name':
      return context.t('people.first_name');
    case 'last_name':
      return context.t('people.last_name');
    case 'phone':
      return context.t('common.phone');
    case 'address':
      return context.t('emp.address');
    case 'birth_date':
      return context.t('emp.birth_date');
    case 'gender':
      return context.t('emp.gender');
    case 'emergency_name':
      return context.t('emp.emergency_name');
    case 'emergency_phone':
      return context.t('emp.emergency_phone');
  }
  return key;
}

/// Old value -> new value for a profile change request.
class _ChangesView extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _ChangesView({required this.payload});

  @override
  Widget build(BuildContext context) {
    final changes = payload['changes'];
    if (changes is! Map) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        for (final e in changes.entries)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: context.colors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_fieldLabel(context, '${e.key}'), style: TextStyle(color: context.colors.subtext, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(((e.value is Map ? e.value['from'] : '') ?? '').toString().isEmpty ? '—' : '${e.value['from']}', style: TextStyle(color: context.colors.danger, decoration: TextDecoration.lineThrough)),
              Text(((e.value is Map ? e.value['to'] : '') ?? '').toString().isEmpty ? '—' : '${e.value['to']}', style: TextStyle(color: context.colors.success, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}

class _CorrectionView extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _CorrectionView({required this.payload});

  @override
  Widget build(BuildContext context) {
    if (payload.isEmpty) return const SizedBox.shrink();
    final date = DateTime.tryParse('${payload['date']}');
    return Column(children: [
      InfoRow(icon: Icons.event_rounded, label: context.t('req.corr_date'), value: date == null ? '${payload['date']}' : fmtDate(context, date)),
      InfoRow(icon: Icons.schedule_rounded, label: context.t('req.corr_times'), value: '${fmtTime(context, payload['check_in']?.toString())}  →  ${payload['check_out'] == null ? '—' : fmtTime(context, payload['check_out'].toString())}'),
      if ('${payload['reason'] ?? ''}'.isNotEmpty) InfoRow(icon: Icons.notes_rounded, label: context.t('req.corr_reason'), value: '${payload['reason']}'),
    ]);
  }
}
