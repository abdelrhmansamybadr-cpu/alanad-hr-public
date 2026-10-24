import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

// ====================================================================== badges

class KudoBadge {
  final String key;
  final IconData icon;
  final Color color;
  const KudoBadge(this.key, this.icon, this.color);
}

const kudoBadges = <KudoBadge>[
  KudoBadge('thanks', Icons.favorite_rounded, Color(0xFFEC4899)),
  KudoBadge('great_job', Icons.thumb_up_rounded, Color(0xFF22C55E)),
  KudoBadge('teamwork', Icons.diversity_3_rounded, Color(0xFF0EA5E9)),
  KudoBadge('creative', Icons.lightbulb_rounded, Color(0xFFF59E0B)),
  KudoBadge('helpful', Icons.volunteer_activism_rounded, Color(0xFF8B5CF6)),
  KudoBadge('leader', Icons.flag_rounded, Color(0xFFEF4444)),
];

KudoBadge badgeOf(String key) => kudoBadges.firstWhere((b) => b.key == key, orElse: () => kudoBadges.first);

// ======================================================================= models

class Kudo {
  final int id;
  final String badge;
  final String message;
  final DateTime? createdAt;
  final int fromId;
  final int toId;
  final String fromName;
  final String toName;
  final String? fromAvatar;
  final String? toAvatar;
  const Kudo({required this.id, required this.badge, required this.message, this.createdAt, this.fromId = 0, this.toId = 0, this.fromName = '', this.toName = '', this.fromAvatar, this.toAvatar});

  factory Kudo.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Kudo(
      id: jInt(m, 'id'),
      badge: jStr(m, 'badge', 'thanks'),
      message: jStr(m, 'message'),
      createdAt: jDate(m, 'createdAt'),
      fromId: jInt(m, 'fromEmployeeId'),
      toId: jInt(m, 'toEmployeeId'),
      fromName: jStr(m, 'fromName'),
      toName: jStr(m, 'toName'),
      fromAvatar: jStrN(m, 'fromAvatar'),
      toAvatar: jStrN(m, 'toAvatar'),
    );
  }
}

class MyKudos {
  final int total;
  final Map<String, int> byBadge;
  final List<Kudo> items;
  const MyKudos({this.total = 0, this.byBadge = const {}, this.items = const []});
  factory MyKudos.fromJson(dynamic raw) {
    final m = asMap(raw);
    return MyKudos(total: jInt(m, 'total'), byBadge: {for (final e in asMap(m['byBadge']).entries) e.key: int.tryParse('${e.value}') ?? 0}, items: asMapList(m['items']).map(Kudo.fromJson).toList());
  }
}

// ==================================================================== providers

final kudosFeedProvider = FutureProvider.autoDispose<List<Kudo>>((ref) async {
  final d = await ref.read(apiProvider).get('/kudos');
  return d is List ? d.map(Kudo.fromJson).toList() : <Kudo>[];
});

final myKudosProvider = FutureProvider.autoDispose<MyKudos>((ref) async => MyKudos.fromJson(await ref.read(apiProvider).get('/kudos/me')));

// ====================================================================== screen

class KudosScreen extends ConsumerStatefulWidget {
  const KudosScreen({super.key});
  @override
  ConsumerState<KudosScreen> createState() => _KudosScreenState();
}

class _KudosScreenState extends ConsumerState<KudosScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user!;
    final canGive = (user.employeeId ?? 0) > 0;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('kudos.title'))),
      floatingActionButton: canGive ? FloatingActionButton.extended(onPressed: () => giveKudos(context, ref), icon: const Icon(Icons.favorite_rounded), label: Text(context.t('kudos.give'))) : null,
      body: Column(children: [
        if (canGive) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SegmentBar(labels: [context.t('kudos.feed'), context.t('kudos.mine')], index: _tab, onChanged: (i) => setState(() => _tab = i))),
        Expanded(child: _tab == 0 ? _Feed(canDeleteAny: user.isHr, me: user.employeeId ?? 0) : const _Mine()),
      ]),
    );
  }
}

class _Feed extends ConsumerWidget {
  final bool canDeleteAny;
  final int me;
  const _Feed({required this.canDeleteAny, required this.me});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(kudosFeedProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(kudosFeedProvider),
      child: AsyncBody<List<Kudo>>(
        value: feed,
        onRetry: () => ref.invalidate(kudosFeedProvider),
        builder: (list) {
          if (list.isEmpty) return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.favorite_border_rounded, title: context.t('kudos.empty'), subtitle: context.t('kudos.empty_hint')))]);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
            for (final k in list)
              KudoCard(
                kudo: k,
                onDelete: canDeleteAny || k.fromId == me
                    ? () async {
                        if (!await confirmDialog(context, title: context.t('kudos.delete'), danger: true)) return;
                        try {
                          await ref.read(apiProvider).delete('/kudos/${k.id}');
                          ref.invalidate(kudosFeedProvider);
                          ref.invalidate(myKudosProvider);
                        } on ApiException catch (e) {
                          if (context.mounted) toast(context, e.message, error: true);
                        }
                      }
                    : null,
              ),
          ]);
        },
      ),
    );
  }
}

class _Mine extends ConsumerWidget {
  const _Mine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myKudosProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myKudosProvider),
      child: AsyncBody<MyKudos>(
        value: mine,
        onRetry: () => ref.invalidate(myKudosProvider),
        builder: (m) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('kudos.received_n', {'n': m.total}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final b in kudoBadges.where((b) => (m.byBadge[b.key] ?? 0) > 0)) Pill('${context.t('kudos.b.${b.key}')} · ${m.byBadge[b.key]}', color: b.color, icon: b.icon),
              ]),
              if (m.total == 0) Text(context.t('kudos.none_yet'), style: TextStyle(color: context.colors.subtext)),
            ]),
          ),
          const SizedBox(height: 10),
          for (final k in m.items) KudoCard(kudo: k, showTo: false),
        ]),
      ),
    );
  }
}

class KudoCard extends StatelessWidget {
  final Kudo kudo;
  final bool showTo;
  final VoidCallback? onDelete;
  const KudoCard({super.key, required this.kudo, this.showTo = true, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final b = badgeOf(kudo.badge);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(name: kudo.fromName, url: kudo.fromAvatar, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(showTo ? context.t('kudos.from_to', {'a': kudo.fromName, 'b': kudo.toName}) : kudo.fromName, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(timeAgo(context, kudo.createdAt), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
              ]),
            ),
            IconBadge(b.icon, color: b.color, size: 34),
            if (onDelete != null) IconButton(onPressed: onDelete, icon: const Icon(Icons.close_rounded, size: 18)),
          ]),
          const SizedBox(height: 10),
          Text(kudo.message, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 8),
          Pill(context.t('kudos.b.${b.key}'), color: b.color),
        ]),
      ),
    );
  }
}

// ================================================================== give kudos

Future<void> giveKudos(BuildContext context, WidgetRef ref, {Employee? to}) async {
  final me = ref.read(sessionProvider).user?.employeeId ?? 0;
  final msg = TextEditingController();
  final search = TextEditingController();
  Employee? pick = to;
  String badge = 'thanks';
  String q = '';
  bool busy = false;

  await showAppSheet(
    context,
    title: context.t('kudos.give'),
    child: StatefulBuilder(builder: (ctx, setS) {
      return Consumer(builder: (ctx, ref, _) {
        final people = pick == null ? ref.watch(directoryProvider(q)) : null;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (pick == null) ...[
            AppField(controller: search, label: ctx.t('kudos.who'), icon: Icons.search_rounded, onChanged: (v) => setS(() => q = v.trim())),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: people!.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text(errorText(ctx, e)),
                data: (list) {
                  final others = list.where((e) => e.id != me).toList();
                  return ListView(children: [
                    for (final e in others)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(name: e.fullName, url: e.avatar, size: 34),
                        title: Text(e.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(e.position, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => setS(() => pick = e),
                      ),
                  ]);
                },
              ),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(name: pick!.fullName, url: pick!.avatar, size: 40),
              title: Text(pick!.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
              trailing: to == null ? TextButton(onPressed: () => setS(() => pick = null), child: Text(ctx.t('kudos.change'))) : null,
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in kudoBadges)
                ChoiceChip(
                  selected: badge == b.key,
                  onSelected: (_) => setS(() => badge = b.key),
                  avatar: Icon(b.icon, size: 18, color: badge == b.key ? Colors.white : b.color),
                  label: Text(ctx.t('kudos.b.${b.key}')),
                  selectedColor: b.color,
                  labelStyle: TextStyle(color: badge == b.key ? Colors.white : null, fontWeight: FontWeight.w600),
                ),
            ]),
            const SizedBox(height: 12),
            AppField(controller: msg, label: ctx.t('kudos.message'), icon: Icons.edit_note_rounded, maxLines: 3, maxLength: 500, capitalization: TextCapitalization.sentences),
            const SizedBox(height: 12),
            LoadingButton(
              label: ctx.t('kudos.send'),
              loading: busy,
              onPressed: () async {
                if (msg.text.trim().isEmpty) return;
                final nav = Navigator.of(ctx);
                setS(() => busy = true);
                try {
                  await ref.read(apiProvider).post('/kudos', {'toEmployeeId': pick!.id, 'badge': badge, 'message': msg.text.trim()});
                  ref.invalidate(kudosFeedProvider);
                  nav.pop();
                  if (context.mounted) toast(context, context.t('kudos.sent'));
                } on ApiException catch (e) {
                  setS(() => busy = false);
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
            ),
          ],
        ]);
      });
    }),
  );
}

// ==================================================================== home card

/// Home card: the latest kudos you received, or an invitation to praise a colleague.
class KudosCard extends ConsumerWidget {
  const KudosCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myKudosProvider).valueOrNull;
    if (mine == null) return const SizedBox.shrink();
    final latest = mine.items.isEmpty ? null : mine.items.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        onTap: () => context.push('/kudos'),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          IconBadge(latest == null ? Icons.favorite_border_rounded : badgeOf(latest.badge).icon, color: latest == null ? context.scheme.primary : badgeOf(latest.badge).color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(latest == null ? context.t('kudos.card_empty') : context.t('kudos.card_from', {'name': latest.fromName}), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(latest == null ? context.t('kudos.card_hint') : latest.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.subtext, fontSize: 12.5)),
            ]),
          ),
          if (mine.total > 0) Pill('${mine.total}', color: context.scheme.primary),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}
