import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/ui/widgets.dart';
import 'meeting_models.dart';
import 'meeting_session.dart';

String _when(BuildContext context, DateTime d) => DateFormat('EEE d MMM · HH:mm', context.isAr ? 'ar' : 'en').format(d);

/// My meetings: live now, upcoming, and the last two weeks. HR (and team leads) can start or schedule one.
class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(meetingsListProvider);
    final boot = ref.watch(meetingsBootstrapProvider).valueOrNull;
    final host = ref.watch(meetingHostProvider);
    final inCall = host.current != null && !host.current!.over ? host.current : null;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('meet.title'))),
      floatingActionButton: (boot?.canSchedule ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => showAppSheet(context, title: context.t('meet.new'), child: _MeetingForm(invitable: boot!.invitable)),
              icon: const Icon(Icons.video_call_rounded),
              label: Text(context.t('meet.new')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(meetingsListProvider);
          await ref.read(meetingsListProvider.future).catchError((_) => <Meeting>[]);
        },
        child: AsyncBody<List<Meeting>>(
          value: list,
          onRetry: () => ref.invalidate(meetingsListProvider),
          builder: (items) {
            final live = items.where((m) => m.isLive && !m.isOver).toList();
            final upcoming = items.where((m) => !m.isLive && !m.isOver && m.scheduledAt.isAfter(DateTime.now().subtract(Duration(minutes: m.durationMin + 30)))).toList();
            final past = items.where((m) => !live.contains(m) && !upcoming.contains(m)).toList().reversed.toList();
            Widget section(String key, List<Meeting> ms) => ms.isEmpty
                ? const SizedBox.shrink()
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SectionHeader(context.t(key)),
                    for (final m in ms) Padding(padding: const EdgeInsets.only(bottom: 10), child: _MeetingCard(m)),
                  ]);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (inCall != null)
                  AppCard(
                    color: context.colors.brandSoft,
                    onTap: () => context.push('/meeting/${inCall.meeting.id}'),
                    child: Row(children: [
                      Icon(Icons.graphic_eq_rounded, color: context.scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${context.t('meet.in_meeting')}: ${inCall.meeting.title}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text(context.t('meet.return'), style: TextStyle(color: context.scheme.primary, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                if (items.isEmpty) SizedBox(height: 420, child: EmptyState(icon: Icons.videocam_off_rounded, title: context.t('meet.empty'), subtitle: context.t('meet.empty_hint'))),
                section('meet.live_now', live),
                section('meet.upcoming', upcoming),
                section('meet.past', past),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MeetingCard extends ConsumerWidget {
  final Meeting m;
  const _MeetingCard(this.m);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = m.isLive && !m.isOver;
    final color = m.isOver ? context.colors.subtext : (live ? context.colors.success : context.scheme.primary);
    return RowTile(
      leading: IconBadge(live ? Icons.videocam_rounded : Icons.event_rounded, color: color, size: 42),
      title: m.title,
      subtitle: '${_when(context, m.scheduledAt)} · ${context.t('meet.people_n', {'n': m.active.length})}',
      trailing: m.canJoin
          ? FilledButton(
              onPressed: () => _open(context, ref),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16)),
              child: Text(context.t('meet.join')),
            )
          : Pill(context.t('meet.status.${m.status}'), color: color),
      bottom: live && m.inCall > 0
          ? Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Icon(Icons.people_alt_rounded, size: 16, color: color), const SizedBox(width: 6), Text(context.t('meet.in_call_n', {'n': m.inCall}), style: TextStyle(color: color, fontSize: 12.5))]))
          : null,
      onTap: m.canJoin ? () => _open(context, ref) : () => showAppSheet(context, title: m.title, child: _MeetingDetails(m)),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final host = ref.read(meetingHostProvider);
    final cur = host.current;
    if (cur != null && cur.meeting.id != m.id && !cur.over) {
      toast(context, context.t('meet.already_in'), error: true);
      return;
    }
    context.push('/meeting/${m.id}');
  }
}

class _MeetingDetails extends ConsumerWidget {
  final Meeting m;
  const _MeetingDetails(this.m);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meetingsBootstrapProvider).valueOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_when(context, m.scheduledAt), style: context.text.titleMedium),
      const SizedBox(height: 4),
      Text('${m.durationMin} min · ${context.t('meet.status.${m.status}')}', style: TextStyle(color: context.colors.subtext)),
      if ((m.notes ?? '').isNotEmpty) ...[const SizedBox(height: 12), Text(m.notes!)],
      const SizedBox(height: 16),
      Text(context.t('meet.people'), style: context.text.titleSmall),
      const SizedBox(height: 6),
      for (final p in m.active)
        ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Avatar(name: p.name, size: 34), title: Text(p.name), trailing: p.isHost ? Pill(context.t('meet.host'), color: context.scheme.primary) : null),
      if (!m.isOver && ((me?.canSchedule ?? false)))
        TextButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            if (!await confirmDialog(context, title: context.t('meet.cancel'), message: context.t('meet.cancel_q'), danger: true, confirmLabel: context.t('meet.cancel'))) return;
            try {
              await ref.read(apiProvider).delete('/meetings/${m.id}');
              ref.invalidate(meetingsListProvider);
              if (context.mounted) toast(context, context.t('meet.cancelled'));
              nav.pop();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          },
          child: Text(context.t('meet.cancel'), style: TextStyle(color: context.colors.danger)),
        ),
    ]);
  }
}

class _MeetingForm extends ConsumerStatefulWidget {
  final List<Invitee> invitable;
  const _MeetingForm({required this.invitable});

  @override
  ConsumerState<_MeetingForm> createState() => _MeetingFormState();
}

class _MeetingFormState extends ConsumerState<_MeetingForm> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  bool _now = true;
  DateTime? _at;
  int _duration = 30;
  final Set<int> _picked = {};
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_picked.isEmpty) return toast(context, context.t('meet.form.pick_people'), error: true);
    if (!_now && _at == null) return toast(context, context.t('meet.form.pick_time'), error: true);
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final r = await ref.read(apiProvider).post('/meetings', {
        'title': _title.text.trim(),
        'userIds': _picked.toList(),
        'durationMin': _duration,
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        if (_now) 'startNow': true else 'scheduledAt': _at!.toUtc().toIso8601String(),
      });
      ref.invalidate(meetingsListProvider);
      if (mounted) toast(context, context.t('meet.created'));
      nav.pop();
      if (_now && r is Map && mounted) context.push('/meeting/${r['id']}');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(controller: _title, label: context.t('meet.form.title'), icon: Icons.title_rounded, capitalization: TextCapitalization.sentences, validator: (v) => requiredValidator(context, v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('meet.form.start_now')), value: _now, onChanged: (v) => setState(() => _now = v)),
          if (!_now)
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.event_rounded),
              label: Text(_at == null ? context.t('meet.form.when') : _when(context, _at!)),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _duration,
            decoration: InputDecoration(labelText: context.t('meet.form.duration'), prefixIcon: const Icon(Icons.timer_outlined)),
            items: const [15, 30, 45, 60, 90, 120].map((m) => DropdownMenuItem(value: m, child: Text('$m'))).toList(),
            onChanged: (v) => setState(() => _duration = v ?? 30),
          ),
          const SizedBox(height: 12),
          AppField(controller: _notes, label: context.t('meet.form.notes'), icon: Icons.notes_rounded),
          const SizedBox(height: 16),
          Text(context.t('meet.form.invite'), style: context.text.titleSmall),
          for (final p in widget.invitable)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _picked.contains(p.id),
              title: Text(p.name),
              onChanged: (v) => setState(() => v == true ? _picked.add(p.id) : _picked.remove(p.id)),
            ),
          const SizedBox(height: 14),
          LoadingButton(label: _now ? context.t('meet.form.start_now') : context.t('common.save'), loading: _busy, onPressed: _save),
        ]),
      );
}
