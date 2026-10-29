import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/ui/widgets.dart';
import '../../core/ui/responsive.dart';
import '../common/reviews_screen.dart';
import '../data/providers.dart';

class ReviewsManageScreen extends ConsumerWidget {
  const ReviewsManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(reviewsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('me.reviews'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showAppSheet(context, title: context.t('rev.new'), child: const _ReviewForm()), icon: const Icon(Icons.add_rounded), label: Text(context.t('rev.new'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reviewsProvider);
          await ref.read(reviewsProvider.future).catchError((_) => <Review>[]);
        },
        child: AsyncBody<List<Review>>(
          value: list,
          onRetry: () => ref.invalidate(reviewsProvider),
          builder: (items) => items.isEmpty
              ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.star_outline_rounded, title: context.t('rev.none'), subtitle: context.t('rev.none_hint')))])
              : AdaptiveList(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  gap: 10,
                  itemBuilder: (_, i) {
                    final r = items[i];
                    return RowTile(
                      leading: Avatar(name: r.employeeName, size: 46),
                      title: r.employeeName,
                      subtitle: r.period,
                      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [StarRating(r.rating, size: 15), const SizedBox(height: 6), StatusChip(r.status)]),
                      onTap: () => showAppSheet(context, title: r.employeeName, child: _ReviewForm(existing: r)),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _ReviewForm extends ConsumerStatefulWidget {
  final Review? existing;
  const _ReviewForm({this.existing});

  @override
  ConsumerState<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<_ReviewForm> {
  late int? _employee = widget.existing?.employeeId;
  int? _reviewer;
  late final _period = TextEditingController(text: widget.existing?.period ?? 'Q${((DateTime.now().month - 1) ~/ 3) + 1} ${DateTime.now().year}');
  late final _goals = TextEditingController(text: widget.existing?.goals);
  late final _ach = TextEditingController(text: widget.existing?.achievements);
  late final _feedback = TextEditingController(text: widget.existing?.feedback);
  late int _rating = widget.existing?.rating ?? 3;
  late String _status = widget.existing?.status ?? 'draft';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_period, _goals, _ach, _feedback]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_employee == null) return toast(context, context.t('payroll.pick_employee'), error: true);
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final body = {'period': _period.text.trim(), 'rating': _rating, 'goals': _goals.text.trim(), 'achievements': _ach.text.trim(), 'feedback': _feedback.text.trim(), 'status': _status};
      final api = ref.read(apiProvider);
      if (widget.existing == null) {
        await api.post('/reviews', {...body, 'employeeId': _employee, if (_reviewer != null) 'reviewerId': _reviewer});
      } else {
        await api.put('/reviews/${widget.existing!.id}', body);
      }
      ref.invalidate(reviewsProvider);
      if (mounted) toast(context, context.t('common.saved'));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = (ref.watch(employeesProvider('')).valueOrNull ?? const <Employee>[]).where((e) => e.status != 'inactive').toList();
    final editing = widget.existing != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!editing) ...[
        DropdownButtonFormField<int>(
          initialValue: _employee,
          decoration: InputDecoration(labelText: context.t('payroll.employee'), prefixIcon: const Icon(Icons.person_outline_rounded)),
          items: [for (final e in people) DropdownMenuItem(value: e.id, child: Text(e.fullName))],
          onChanged: (v) => setState(() {
            _employee = v;
            _reviewer = people.firstWhere((e) => e.id == v).managerId ?? _reviewer;
          }),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: _reviewer,
          decoration: InputDecoration(labelText: context.t('rev.reviewer'), prefixIcon: const Icon(Icons.supervisor_account_outlined)),
          items: [for (final e in people) DropdownMenuItem(value: e.id, child: Text(e.fullName))],
          onChanged: (v) => setState(() => _reviewer = v),
        ),
        const SizedBox(height: 14),
      ],
      AppField(controller: _period, label: context.t('rev.period'), icon: Icons.event_note_rounded),
      const SizedBox(height: 14),
      Text(context.t('rev.rating'), style: TextStyle(color: context.colors.subtext, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 1; i <= 5; i++) IconButton(onPressed: () => setState(() => _rating = i), iconSize: 38, icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= _rating ? context.colors.warning : context.colors.border)),
      ]),
      AppField(controller: _goals, label: context.t('rev.goals'), icon: Icons.flag_outlined, maxLines: 2),
      const SizedBox(height: 14),
      AppField(controller: _ach, label: context.t('rev.achievements'), icon: Icons.emoji_events_outlined, maxLines: 2),
      const SizedBox(height: 14),
      AppField(controller: _feedback, label: context.t('rev.feedback'), icon: Icons.comment_outlined, maxLines: 3),
      const SizedBox(height: 14),
      SegmentBar(labels: [context.t('status.draft'), context.t('status.submitted'), context.t('status.approved')], index: ['draft', 'submitted', 'approved'].indexOf(_status), onChanged: (i) => setState(() => _status = ['draft', 'submitted', 'approved'][i])),
      Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.t('rev.share_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
      const SizedBox(height: 18),
      LoadingButton(label: context.t('common.save'), loading: _busy, onPressed: _save),
      if (editing)
        TextButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            if (!await confirmDialog(context, title: context.t('common.delete'), danger: true, confirmLabel: context.t('common.delete'))) return;
            try {
              await ref.read(apiProvider).delete('/reviews/${widget.existing!.id}');
              ref.invalidate(reviewsProvider);
              nav.pop();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          },
          child: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
        ),
    ]);
  }
}
