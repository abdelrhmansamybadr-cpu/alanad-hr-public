import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

class StarRating extends StatelessWidget {
  final int value;
  final double size;
  const StarRating(this.value, {super.key, this.size = 18});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++) Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: i <= value ? context.colors.warning : context.colors.border),
      ]);
}

Future<void> showReviewDetail(BuildContext context, Review r) => showAppSheet(
      context,
      title: r.period.isEmpty ? context.t('me.reviews') : r.period,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(name: r.employeeName, size: 44),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.employeeName, style: const TextStyle(fontWeight: FontWeight.w700)), Text(context.t('rev.by', {'name': r.reviewerName}), style: TextStyle(color: context.colors.subtext, fontSize: 13))])),
          StatusChip(r.status),
        ]),
        const SizedBox(height: 14),
        Center(child: StarRating(r.rating, size: 32)),
        const SizedBox(height: 16),
        if (r.goals != null) _block(context, context.t('rev.goals'), r.goals!),
        if (r.achievements != null) _block(context, context.t('rev.achievements'), r.achievements!),
        if (r.feedback != null) _block(context, context.t('rev.feedback'), r.feedback!),
      ]),
    );

Widget _block(BuildContext context, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: context.colors.subtext, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(height: 1.45)),
      ]),
    );

/// The signed-in employee's shared performance reviews.
class MyReviewsScreen extends ConsumerWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(reviewsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('me.reviews'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reviewsProvider);
          await ref.read(reviewsProvider.future).catchError((_) => <Review>[]);
        },
        child: AsyncBody<List<Review>>(
          value: list,
          onRetry: () => ref.invalidate(reviewsProvider),
          builder: (items) => items.isEmpty
              ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.star_outline_rounded, title: context.t('rev.empty'), subtitle: context.t('rev.empty_hint')))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => RowTile(
                    leading: IconBadge(Icons.star_rounded, color: context.colors.warning, size: 46),
                    title: items[i].period.isEmpty ? context.t('me.reviews') : items[i].period,
                    subtitle: context.t('rev.by', {'name': items[i].reviewerName}),
                    trailing: StarRating(items[i].rating),
                    onTap: () => showReviewDetail(context, items[i]),
                  ),
                ),
        ),
      ),
    );
  }
}
