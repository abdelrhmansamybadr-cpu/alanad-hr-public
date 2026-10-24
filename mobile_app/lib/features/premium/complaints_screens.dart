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

/// scope 'mine' = the complaints I filed (head) or all of the company (HR); 'owner' = the ones sent up to the owner.
final complaintsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, scope) async {
  return asMapList(await ref.read(apiProvider).get(scope == 'owner' ? '/complaints/owner' : '/complaints'));
});

final complaintProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async => asMap(await ref.read(apiProvider).get('/complaints/$id')));

final complaintTeamProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => asMapList(await ref.read(apiProvider).get('/complaints/team')));

Color _statusColor(BuildContext c, String s) => switch (s) {
      'open' => c.colors.warning,
      'in_review' => c.colors.info,
      'escalated' => const Color(0xFF8B5CF6),
      'resolved' => c.colors.success,
      _ => c.colors.subtext,
    };

Color _severityColor(BuildContext c, String s) => switch (s) {
      'high' => c.colors.danger,
      'low' => c.colors.subtext,
      _ => c.colors.warning,
    };

/// Complaints: a team head files them (about a member of the team, or to HR); HR answers or sends them to the owner.
class ComplaintsScreen extends ConsumerStatefulWidget {
  final bool ownerView;
  const ComplaintsScreen({super.key, this.ownerView = false});
  @override
  ConsumerState<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends ConsumerState<ComplaintsScreen> {
  int _filter = 0; // 0 all, 1 open, 2 in review, 3 sent to owner, 4 closed

  @override
  Widget build(BuildContext context) {
    final scope = widget.ownerView ? 'owner' : 'mine';
    final data = ref.watch(complaintsProvider(scope));
    final me = ref.watch(sessionProvider).user;
    final canFile = !widget.ownerView && (me?.isTeamLead ?? false);
    return Scaffold(
      appBar: AppBar(title: Text(context.t(widget.ownerView ? 'cmp.title_owner' : 'cmp.title'))),
      floatingActionButton: canFile
          ? FloatingActionButton.extended(onPressed: () => showComplaintForm(context, ref), icon: const Icon(Icons.add_comment_rounded), label: Text(context.t('cmp.new')))
          : null,
      body: Column(children: [
        const SizedBox(height: 4),
        FilterChips(labels: [context.t('cmp.f_all'), context.t('cmp.s_open'), context.t('cmp.s_in_review'), context.t('cmp.s_escalated'), context.t('cmp.f_closed')], index: _filter, onChanged: (i) => setState(() => _filter = i)),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(complaintsProvider(scope));
              await ref.read(complaintsProvider(scope).future).catchError((_) => <Map<String, dynamic>>[]);
            },
            child: data.when(
              loading: () => const SkeletonList(),
              error: (e, _) => isFeatureOff(e) ? const FeatureOff() : ErrorState(e, onRetry: () => ref.invalidate(complaintsProvider(scope))),
              data: (all) {
                final items = all.where((c) {
                  final st = jStr(c, 'status');
                  switch (_filter) {
                    case 1:
                      return st == 'open';
                    case 2:
                      return st == 'in_review';
                    case 3:
                      return st == 'escalated';
                    case 4:
                      return st == 'resolved' || st == 'dismissed';
                    default:
                      return true;
                  }
                }).toList();
                if (items.isEmpty) {
                  return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: 380, child: EmptyState(icon: Icons.report_gmailerrorred_rounded, title: context.t('cmp.empty'), subtitle: context.t(canFile ? 'cmp.empty_hint' : 'cmp.empty_hint_hr')))]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ComplaintTile(items[i], showCompany: widget.ownerView),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _ComplaintTile extends StatelessWidget {
  final Map<String, dynamic> c;
  final bool showCompany;
  const _ComplaintTile(this.c, {this.showCompany = false});

  @override
  Widget build(BuildContext context) {
    final st = jStr(c, 'status');
    final about = jStr(c, 'kind') == 'member' ? context.t('cmp.about', {'name': jStr(c, 'targetName')}) : context.t('cmp.to_hr');
    return RowTile(
      leading: IconBadge(jStr(c, 'kind') == 'member' ? Icons.person_search_rounded : Icons.support_agent_rounded, color: _severityColor(context, jStr(c, 'severity')), size: 44),
      title: jStr(c, 'subject'),
      subtitle: [if (showCompany) jStr(c, 'companyName'), jStr(c, 'authorName'), about].where((e) => e.isNotEmpty).join(' · '),
      trailing: Pill(context.t('cmp.s_$st'), color: _statusColor(context, st)),
      onTap: () => context.push('/complaint/${jInt(c, 'id')}'),
    );
  }
}

// ===================================================================== one complaint

class ComplaintDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const ComplaintDetailScreen({super.key, required this.id});
  @override
  ConsumerState<ComplaintDetailScreen> createState() => _ComplaintDetailState();
}

class _ComplaintDetailState extends ConsumerState<ComplaintDetailScreen> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _act(String action, {String? status}) async {
    final note = _note.text.trim();
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/complaints/${widget.id}', {'action': action, if (status != null) 'status': status, 'note': note});
      _note.clear();
      ref.invalidate(complaintProvider(widget.id));
      ref.invalidate(complaintsProvider);
      if (mounted) toast(context, context.t('cmp.saved'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(complaintProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: Text(context.t('cmp.details'))),
      body: data.when(
        loading: () => const SkeletonList(),
        error: (e, _) => isFeatureOff(e) ? const FeatureOff() : ErrorState(e, onRetry: () => ref.invalidate(complaintProvider(widget.id))),
        data: (c) {
          final st = jStr(c, 'status');
          final role = jStr(c, 'myRole');
          final canRespond = jBool(c, 'canRespond');
          final canEscalate = jBool(c, 'canEscalate');
          final canComment = jBool(c, 'canComment');
          final events = asMapList(c['events']);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 6, children: [
                  Pill(context.t('cmp.s_$st'), color: _statusColor(context, st)),
                  Pill(context.t('cmp.sev_${jStr(c, 'severity')}'), color: _severityColor(context, jStr(c, 'severity'))),
                  if (jStr(c, 'companyName').isNotEmpty) Pill(jStr(c, 'companyName'), icon: Icons.business_rounded),
                ]),
                const SizedBox(height: 10),
                Text(jStr(c, 'subject'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                InfoRow(icon: Icons.edit_note_rounded, label: context.t('cmp.filed_by'), value: jStr(c, 'authorName')),
                InfoRow(icon: jStr(c, 'kind') == 'member' ? Icons.person_search_rounded : Icons.support_agent_rounded, label: context.t('cmp.regarding'), value: jStr(c, 'kind') == 'member' ? [jStr(c, 'targetName'), jStr(c, 'targetPosition')].where((e) => e.isNotEmpty).join(' · ') : context.t('cmp.to_hr')),
                const SizedBox(height: 8),
                Text(jStr(c, 'body'), style: const TextStyle(height: 1.5)),
              ]),
            ),
            SectionHeader(context.t('cmp.thread')),
            ...events.map((e) => _EventTile(e)),
            const SizedBox(height: 16),
            if (canComment || canRespond || canEscalate) ...[
              AppField(controller: _note, label: context.t('cmp.note'), icon: Icons.comment_outlined, maxLines: 3),
              const SizedBox(height: 12),
              if (canComment) LoadingButton(label: context.t('cmp.send_note'), outlined: true, loading: _busy, icon: Icons.send_rounded, onPressed: () => _act('comment')),
              if (canRespond && st != 'resolved' && st != 'dismissed') ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: LoadingButton(label: context.t('cmp.in_review'), outlined: true, loading: _busy, onPressed: () => _act('respond', status: 'in_review'))),
                  const SizedBox(width: 10),
                  Expanded(child: LoadingButton(label: context.t('cmp.dismiss'), outlined: true, loading: _busy, onPressed: () => _act('respond', status: 'dismissed'))),
                ]),
                const SizedBox(height: 10),
                LoadingButton(label: context.t('cmp.resolve'), loading: _busy, icon: Icons.check_circle_rounded, onPressed: () => _act('respond', status: 'resolved')),
              ],
              if (canEscalate) ...[
                const SizedBox(height: 10),
                LoadingButton(label: context.t('cmp.escalate'), color: const Color(0xFF8B5CF6), loading: _busy, icon: Icons.arrow_circle_up_rounded, onPressed: () => _act('escalate')),
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.t('cmp.escalate_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
              ],
            ],
            if (role == 'head' && (st == 'resolved' || st == 'dismissed')) Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.t('cmp.closed_note'), style: TextStyle(color: context.colors.subtext))),
          ]);
        },
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> e;
  const _EventTile(this.e);

  @override
  Widget build(BuildContext context) {
    final role = jStr(e, 'actorRole');
    final color = role == 'owner' ? const Color(0xFF8B5CF6) : (role == 'hr' ? context.colors.info : context.scheme.primary);
    final action = jStr(e, 'action');
    final when = parseUtc(jStrN(e, 'createdAt'));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: .07), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Pill(context.t('cmp.role_$role'), color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(jStr(e, 'actorName'), style: const TextStyle(fontWeight: FontWeight.w700))),
          if (when != null) Text('${when.day}/${when.month} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}', style: TextStyle(color: context.colors.subtext, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        Text(context.t('cmp.a_$action'), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        if (jStrN(e, 'note') != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(jStr(e, 'note'), style: const TextStyle(height: 1.4))),
      ]),
    );
  }
}

// ===================================================================== new complaint

/// [targetId]: open the form already pointing at a member of the team.
Future<void> showComplaintForm(BuildContext context, WidgetRef ref, {int? targetId}) {
  return showAppSheet(context, title: context.t('cmp.new'), child: _ComplaintForm(targetId: targetId));
}

class _ComplaintForm extends ConsumerStatefulWidget {
  final int? targetId;
  const _ComplaintForm({this.targetId});
  @override
  ConsumerState<_ComplaintForm> createState() => _ComplaintFormState();
}

class _ComplaintFormState extends ConsumerState<_ComplaintForm> {
  late int _kind = widget.targetId != null ? 0 : 0; // 0 about a member, 1 to HR
  int? _target;
  String _severity = 'normal';
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _target = widget.targetId;
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_kind == 0 && _target == null) {
      toast(context, context.t('cmp.pick_member'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).post('/complaints', {'kind': _kind == 0 ? 'member' : 'hr', if (_kind == 0) 'targetEmployeeId': _target, 'subject': _subject.text.trim(), 'body': _body.text.trim(), 'severity': _severity});
      ref.invalidate(complaintsProvider);
      ref.invalidate(complaintTeamProvider);
      if (mounted) {
        final id = jInt(asMap(r), 'id');
        Navigator.pop(context);
        toast(context, context.t('cmp.sent'));
        if (id > 0) context.push('/complaint/$id');
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(complaintTeamProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentBar(labels: [context.t('cmp.k_member'), context.t('cmp.k_hr')], index: _kind, onChanged: (i) => setState(() => _kind = i)),
      const SizedBox(height: 14),
      if (_kind == 0)
        team.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e', style: TextStyle(color: context.colors.danger)),
          data: (members) => DropdownButtonFormField<int>(
            initialValue: members.any((m) => jInt(m, 'id') == _target) ? _target : null,
            decoration: InputDecoration(labelText: context.t('cmp.member'), prefixIcon: const Icon(Icons.person_search_rounded)),
            items: members.map((m) => DropdownMenuItem(value: jInt(m, 'id'), child: Text(jStr(m, 'name')))).toList(),
            onChanged: (v) => setState(() => _target = v),
          ),
        ),
      if (_kind == 0) const SizedBox(height: 12),
      AppField(controller: _subject, label: context.t('cmp.subject'), icon: Icons.title_rounded),
      const SizedBox(height: 12),
      AppField(controller: _body, label: context.t('cmp.body'), icon: Icons.notes_rounded, maxLines: 5),
      const SizedBox(height: 12),
      Text(context.t('cmp.severity'), style: TextStyle(color: context.colors.subtext, fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        for (final s in const ['low', 'normal', 'high'])
          ChoiceChip(label: Text(context.t('cmp.sev_$s')), selected: _severity == s, onSelected: (_) => setState(() => _severity = s)),
      ]),
      const SizedBox(height: 8),
      Text(context.t(_kind == 0 ? 'cmp.privacy' : 'cmp.privacy_hr'), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
      const SizedBox(height: 14),
      LoadingButton(label: context.t('cmp.submit'), loading: _busy, icon: Icons.send_rounded, onPressed: _send),
    ]);
  }
}
