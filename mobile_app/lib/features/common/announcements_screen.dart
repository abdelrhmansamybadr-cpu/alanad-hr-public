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

// ================================================================ announcements

class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(announcementsProvider);
    final isHr = ref.watch(sessionProvider).user!.isHr;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('home.announcements'))),
      floatingActionButton: isHr ? FloatingActionButton.extended(onPressed: () => showAnnouncementForm(context), icon: const Icon(Icons.add_rounded), label: Text(context.t('ann.new'))) : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(announcementsProvider);
          await ref.read(announcementsProvider.future).catchError((_) => <Announcement>[]);
        },
        child: AsyncBody<List<Announcement>>(
          value: list,
          onRetry: () => ref.invalidate(announcementsProvider),
          builder: (items) => items.isEmpty
              ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.campaign_outlined, title: context.t('ann.empty'), subtitle: isHr ? context.t('ann.empty_hr') : null))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final a = items[i];
                    final high = a.priority == 'high';
                    return AppCard(
                      onTap: () => _detail(context, ref, a, isHr),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          IconBadge(Icons.campaign_rounded, color: high ? context.colors.danger : context.scheme.primary, size: 40),
                          const SizedBox(width: 12),
                          Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                          if (high) StatusChip('high', label: context.t('priority.high'), color: context.colors.danger),
                        ]),
                        if (a.content.isNotEmpty) ...[const SizedBox(height: 10), Text(a.content, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.subtext, height: 1.4))],
                        const SizedBox(height: 10),
                        Text('${a.author} · ${timeAgo(context, a.createdAt)}', style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                      ]),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _detail(BuildContext context, WidgetRef ref, Announcement a, bool isHr) {
    showAppSheet(
      context,
      title: a.title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${a.author} · ${a.createdAt == null ? '' : fmtDate(context, a.createdAt!)}', style: TextStyle(color: context.colors.subtext, fontSize: 13)),
        const SizedBox(height: 14),
        Text(a.content, style: const TextStyle(height: 1.5, fontSize: 15)),
        if (isHr) ...[
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                showAnnouncementForm(context, existing: a);
              },
              icon: const Icon(Icons.edit_rounded),
              label: Text(context.t('common.edit')),
            )),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(
              onPressed: () async {
                final nav = Navigator.of(context);
                if (!await confirmDialog(context, title: context.t('common.delete'), message: a.title, danger: true, confirmLabel: context.t('common.delete'))) return;
                try {
                  await ref.read(apiProvider).delete('/announcements/${a.id}');
                  ref.invalidate(announcementsProvider);
                  nav.pop();
                } on ApiException catch (e) {
                  if (context.mounted) toast(context, e.message, error: true);
                }
              },
              icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger),
              label: Text(context.t('common.delete'), style: TextStyle(color: context.colors.danger)),
            )),
          ]),
        ],
      ]),
    );
  }
}

Future<void> showAnnouncementForm(BuildContext context, {Announcement? existing}) =>
    showAppSheet(context, title: existing == null ? context.t('ann.new') : context.t('common.edit'), child: _AnnouncementForm(existing: existing));

class _AnnouncementForm extends ConsumerStatefulWidget {
  final Announcement? existing;
  const _AnnouncementForm({this.existing});

  @override
  ConsumerState<_AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends ConsumerState<_AnnouncementForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _content = TextEditingController(text: widget.existing?.content);
  late String _priority = widget.existing?.priority ?? 'medium';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final body = {'title': _title.text.trim(), 'content': _content.text.trim(), 'priority': _priority};
      if (widget.existing == null) {
        await ref.read(apiProvider).post('/announcements', body);
      } else {
        await ref.read(apiProvider).put('/announcements/${widget.existing!.id}', body);
      }
      ref.invalidate(announcementsProvider);
      ref.invalidate(myStatsProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, widget.existing == null ? context.t('ann.sent') : context.t('common.saved'));
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(children: [
          AppField(controller: _title, label: context.t('req.title_label'), icon: Icons.title_rounded, capitalization: TextCapitalization.sentences, validator: (v) => requiredValidator(context, v)),
          const SizedBox(height: 14),
          AppField(controller: _content, label: context.t('ann.message'), icon: Icons.notes_rounded, maxLines: 5, validator: (v) => requiredValidator(context, v)),
          const SizedBox(height: 14),
          SegmentBar(labels: [context.t('priority.low'), context.t('priority.medium'), context.t('priority.high')], index: ['low', 'medium', 'high'].indexOf(_priority), onChanged: (i) => setState(() => _priority = ['low', 'medium', 'high'][i])),
          if (widget.existing == null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(context.t('ann.notify_hint'), style: TextStyle(color: context.colors.subtext, fontSize: 12))),
          const SizedBox(height: 20),
          LoadingButton(label: widget.existing == null ? context.t('ann.publish') : context.t('common.save'), loading: _busy, onPressed: _save),
        ]),
      );
}

// ==================================================================== holidays

class HolidaysScreen extends ConsumerStatefulWidget {
  const HolidaysScreen({super.key});

  @override
  ConsumerState<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends ConsumerState<HolidaysScreen> {
  int _year = DateTime.now().year;

  Future<void> _add() async {
    final name = TextEditingController();
    DateTime? date;
    await showAppSheet(
      context,
      title: context.t('hol.add'),
      child: StatefulBuilder(builder: (ctx, setS) {
        bool busy = false;
        return Column(children: [
          AppField(controller: name, label: ctx.t('hol.name'), icon: Icons.celebration_outlined, capitalization: TextCapitalization.words),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final d = await showDatePicker(context: ctx, initialDate: DateTime(_year, DateTime.now().month, DateTime.now().day), firstDate: DateTime(_year - 1), lastDate: DateTime(_year + 2));
              if (d != null) setS(() => date = d);
            },
            child: InputDecorator(decoration: InputDecoration(labelText: ctx.t('common.date'), prefixIcon: const Icon(Icons.event_rounded)), child: Text(date == null ? '—' : fmtLongDate(ctx, date!))),
          ),
          const SizedBox(height: 20),
          LoadingButton(
            label: ctx.t('common.add'),
            loading: busy,
            onPressed: () async {
              if (name.text.trim().isEmpty || date == null) return;
              final nav = Navigator.of(ctx);
              try {
                await ref.read(apiProvider).post('/holidays', {'name': name.text.trim(), 'date': ymd(date!)});
                ref.invalidate(holidaysProvider);
                nav.pop();
              } on ApiException catch (e) {
                if (ctx.mounted) toast(ctx, e.message, error: true);
              }
            },
          ),
        ]);
      }),
    );
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(holidaysProvider(_year));
    final isHr = ref.watch(sessionProvider).user!.isHr;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('me.holidays'))),
      floatingActionButton: isHr ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: Text(context.t('hol.add'))) : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            IconButton.filledTonal(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(child: Center(child: Text('$_year', style: context.text.titleMedium))),
            IconButton.filledTonal(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
        ),
        Expanded(
          child: AsyncBody<List<Holiday>>(
            value: list,
            onRetry: () => ref.invalidate(holidaysProvider(_year)),
            builder: (items) => items.isEmpty
                ? EmptyState(icon: Icons.celebration_outlined, title: context.t('hol.empty'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final h = items[i];
                      final past = h.date.isBefore(DateTime.now().subtract(const Duration(days: 1)));
                      return Opacity(
                        opacity: past ? 0.55 : 1,
                        child: RowTile(
                          leading: Container(
                            width: 50,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(color: context.colors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                            child: Column(children: [
                              Text('${h.date.day}', style: TextStyle(color: context.colors.warning, fontWeight: FontWeight.w800, fontSize: 18)),
                              Text(fmtWeekdayShort(context, h.date), style: TextStyle(color: context.colors.warning, fontSize: 10)),
                            ]),
                          ),
                          title: h.name,
                          subtitle: fmtLongDate(context, h.date),
                          trailing: isHr
                              ? IconButton(
                                  icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger),
                                  onPressed: () async {
                                    try {
                                      await ref.read(apiProvider).delete('/holidays/${h.id}');
                                      ref.invalidate(holidaysProvider);
                                    } on ApiException catch (e) {
                                      if (context.mounted) toast(context, e.message, error: true);
                                    }
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
