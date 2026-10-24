import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';
import 'point_orb.dart';
import 'reward_effects.dart';
import 'rewards_widgets.dart';

/// My points: level, colours, what cancelled what, the last weeks, and the ranking.
class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  int _tab = 0;
  bool _celebrated = false;

  Future<void> _maybeLevelUp(PointsSummary s) async {
    if (_celebrated) return;
    _celebrated = true;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getInt('rewards_level_seen') ?? 0;
    if (s.level > seen && mounted) {
      await prefs.setInt('rewards_level_seen', s.level);
      if (seen > 0 || s.level > 0) {
        if (!mounted) return;
        showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'levelup',
          barrierColor: Colors.black.withValues(alpha: 0.75),
          pageBuilder: (_, __, ___) => _LevelUpDialog(level: s.level, name: s.levelName),
        );
      }
    } else if (s.level < seen) {
      await prefs.setInt('rewards_level_seen', s.level);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(sessionProvider).company;
    final points = ref.watch(myPointsProvider);
    final showBoard = company?.leaderboardVisible ?? true;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('rewards.title'))),
      body: Column(children: [
        if (showBoard)
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SegmentBar(labels: [context.t('rewards.tab_mine'), context.t('rewards.tab_board')], index: _tab, onChanged: (i) => setState(() => _tab = i))),
        Expanded(
          child: _tab == 0
              ? RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(myPointsProvider);
                    ref.invalidate(myStatsProvider);
                    await ref.read(myPointsProvider.future).catchError((_) => const PointsSummary());
                  },
                  child: AsyncBody<PointsSummary>(
                    value: points,
                    onRetry: () => ref.invalidate(myPointsProvider),
                    loading: const Padding(padding: EdgeInsets.all(16), child: Skeleton(height: 300, radius: 28)),
                    builder: (s) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLevelUp(s));
                      return PointsBody(summary: s);
                    },
                  ),
                )
              : const LeaderboardList(),
        ),
      ]),
    );
  }
}

/// The scrolling content of a points summary (shared with the HR employee view).
class PointsBody extends StatelessWidget {
  final PointsSummary summary;
  final Widget? footer; // HR actions
  final void Function(PointEntry)? onEntryTap; // HR: excuse / restore a day
  const PointsBody({super.key, required this.summary, this.footer, this.onEntryTap});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (!s.enabled) {
      return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.emoji_events_outlined, title: context.t('rewards.off'), subtitle: context.t('rewards.off_hint')))]);
    }
    final progress = s.streakTarget <= 0 ? 0.0 : s.streak / s.streakTarget;
    final toGo = math.max(0, s.streakTarget - s.streak);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), physics: const AlwaysScrollableScrollPhysics(), children: [
      // ---- level hero
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF021A22), Color(0xFF0A3B4A), Color(0xFF00617A)]),
          boxShadow: [BoxShadow(color: const Color(0xFF00617A).withValues(alpha: 0.4), blurRadius: 26, offset: const Offset(0, 12))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          const Positioned.fill(child: Starfield()),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                LevelBadge(level: s.level, progress: progress, size: 80),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('rewards.level').toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
                    Text(s.levelName.isEmpty ? '${s.level}' : s.levelName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(context.t('rewards.next_level', {'days': toGo, 'name': s.nextLevelName}), style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12, height: 1.3)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              StreakBar(streak: s.streak, target: s.streakTarget),
              if (s.bestStreak > 0) ...[
                const SizedBox(height: 10),
                Align(alignment: AlignmentDirectional.centerStart, child: Text(context.t('rewards.best_streak', {'n': s.bestStreak}), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12))),
              ],
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),

      // ---- the three points
      AppCard(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Column(children: [
          OrbRow(green: s.netGreen, red: s.netRed, black: s.netBlack),
          if (s.rawGreen + s.rawRed + s.rawBlack > 0) ...[
            const SizedBox(height: 10),
            Text(context.t('rewards.earned_total', {'g': s.rawGreen, 'r': s.rawRed, 'b': s.rawBlack}), textAlign: TextAlign.center, style: TextStyle(color: context.colors.subtext, fontSize: 12)),
          ],
        ]),
      ),

      // ---- what cancelled what
      if (s.cancelledBlack > 0) ...[const SizedBox(height: 14), ExchangeAnimation(target: PointKind.black, cost: s.blackCost, cancelled: s.cancelledBlack)],
      if (s.cancelledRed > 0) ...[const SizedBox(height: 14), ExchangeAnimation(target: PointKind.red, cost: s.redCost, cancelled: s.cancelledRed)],

      // ---- last weeks
      SectionHeader(context.t('rewards.last_days')),
      AppCard(child: Column(children: [
        DotCalendar(entries: s.history),
        const SizedBox(height: 14),
        Wrap(spacing: 16, runSpacing: 6, alignment: WrapAlignment.center, children: [
          _Key(PointKind.green.base, context.t('rewards.key_green')),
          _Key(PointKind.red.base, context.t('rewards.key_red')),
          _Key(PointKind.black.base, context.t('rewards.key_black')),
        ]),
      ])),

      // ---- activity
      if (s.history.isNotEmpty) ...[
        SectionHeader(context.t('rewards.activity')),
        for (final e in s.history.take(14)) _ActivityTile(entry: e, onTap: onEntryTap == null ? null : () => onEntryTap!(e)),
      ],

      // ---- rules
      SectionHeader(context.t('rewards.how')),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Rule(PointKind.green, context.t('rewards.rule_green')),
        _Rule(PointKind.red, context.t('rewards.rule_red')),
        _Rule(PointKind.black, context.t('rewards.rule_black')),
        const Divider(height: 24),
        _RuleIcon(Icons.swap_horiz_rounded, context.t('rewards.rule_exchange', {'r': s.redCost, 'b': s.blackCost})),
        _RuleIcon(Icons.local_fire_department_rounded, context.t('rewards.rule_level', {'n': s.streakTarget})),
      ])),
      if (footer != null) ...[const SizedBox(height: 16), footer!],
    ]);
  }
}

class _Key extends StatelessWidget {
  final Color color;
  final String text;
  const _Key(this.color, this.text);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: context.colors.subtext, fontSize: 12)),
      ]);
}

class _Rule extends StatelessWidget {
  final PointKind kind;
  final String text;
  const _Rule(this.kind, this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(center: const Alignment(-0.3, -0.4), colors: [kind.light, kind.base, kind.dark], stops: const [0, 0.55, 1])),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35, fontSize: 13))),
        ]),
      );
}

class _RuleIcon extends StatelessWidget {
  final IconData icon;
  final String text;
  const _RuleIcon(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: context.scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35, fontSize: 13))),
        ]),
      );
}

class _ActivityTile extends StatelessWidget {
  final PointEntry entry;
  final VoidCallback? onTap;
  const _ActivityTile({required this.entry, this.onTap});

  @override
  Widget build(BuildContext context) {
    final kind = pointKindOf(entry.color);
    final color = kind?.base ?? context.colors.subtext;
    final reason = entry.source == 'manual' ? (entry.note ?? context.t('rewards.by_hr')) : context.t('rewards.why.${entry.reason}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: kind == null ? null : RadialGradient(center: const Alignment(-0.3, -0.4), colors: [kind.light, kind.base, kind.dark], stops: const [0, 0.55, 1]), color: kind == null ? color.withValues(alpha: 0.3) : null),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, decoration: entry.voided ? TextDecoration.lineThrough : null))),
          const SizedBox(width: 8),
          if (entry.voided) Pill(context.t('rewards.excused'), color: context.colors.info),
          if (entry.voided) const SizedBox(width: 8),
          Text(fmtDayMonth(context, entry.date), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ======================================================================== leaderboard

class LeaderboardList extends ConsumerWidget {
  const LeaderboardList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(leaderboardProvider);
    final me = ref.watch(sessionProvider).user?.employeeId;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(leaderboardProvider);
        await ref.read(leaderboardProvider.future).catchError((_) => <LeaderboardItem>[]);
      },
      child: AsyncBody<List<LeaderboardItem>>(
        value: board,
        onRetry: () => ref.invalidate(leaderboardProvider),
        builder: (items) {
          if (items.isEmpty) {
            return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.leaderboard_rounded, title: context.t('rewards.board_empty'), subtitle: context.t('rewards.board_empty_hint')))]);
          }
          final top = items.take(3).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), physics: const AlwaysScrollableScrollPhysics(), children: [
            _Podium(top: top),
            const SizedBox(height: 12),
            for (final it in items) _BoardTile(item: it, isMe: it.employeeId == me),
          ]);
        },
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  final List<LeaderboardItem> top;
  const _Podium({required this.top});

  @override
  Widget build(BuildContext context) {
    // order: 2nd, 1st, 3rd
    final order = <int>[if (top.length > 1) 1, 0, if (top.length > 2) 2];
    const heights = [110.0, 140.0, 90.0];
    const medals = [Color(0xFFFBBF24), Color(0xFF94A3B8), Color(0xFFD97706)];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A3B4A), Color(0xFF00617A)])),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        const Positioned.fill(child: Starfield(count: 20)),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final idx in order)
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 700 + idx * 180),
                curve: Curves.easeOutBack,
                builder: (_, v, __) {
                  final it = top[idx];
                  final h = heights[idx] * v;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                      Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: medals[idx], width: 3), boxShadow: [BoxShadow(color: medals[idx].withValues(alpha: 0.6), blurRadius: 16)]), child: Avatar(name: it.name, url: it.avatar, size: idx == 0 ? 62 : 52)),
                      if (idx == 0) const Positioned(top: -22, child: Icon(Icons.emoji_events_rounded, color: Color(0xFFFDE047), size: 26)),
                    ]),
                    const SizedBox(height: 6),
                    Text(it.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    Text(it.levelName.isEmpty ? 'L${it.level}' : it.levelName, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
                    const SizedBox(height: 6),
                    Container(
                      height: h,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(top: Radius.circular(14)), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [medals[idx].withValues(alpha: 0.9), medals[idx].withValues(alpha: 0.35)])),
                      child: Center(child: Text('${it.rank}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 30))),
                    ),
                  ]);
                },
              ),
            ),
        ]),
      ]),
    );
  }
}

class _BoardTile extends StatelessWidget {
  final LeaderboardItem item;
  final bool isMe;
  const _BoardTile({required this.item, required this.isMe});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          color: isMe ? context.colors.brandSoft : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            SizedBox(width: 28, child: Text('${item.rank}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: item.rank <= 3 ? const Color(0xFFF59E0B) : context.colors.subtext))),
            Avatar(name: item.name, url: item.avatar, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isMe ? '${item.name} · ${context.t('rewards.you')}' : item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${context.t('rewards.level')} ${item.level}${item.levelName.isEmpty ? '' : ' · ${item.levelName}'}', style: TextStyle(color: context.colors.subtext, fontSize: 12)),
              ]),
            ),
            _Dot(PointKind.green, item.green),
            const SizedBox(width: 8),
            _Dot(PointKind.red, item.red),
            const SizedBox(width: 8),
            _Dot(PointKind.black, item.black),
          ]),
        ),
      );
}

class _Dot extends StatelessWidget {
  final PointKind kind;
  final int value;
  const _Dot(this.kind, this.value);
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(center: const Alignment(-0.3, -0.4), colors: [kind.light, kind.base, kind.dark], stops: const [0, 0.55, 1]))),
        const SizedBox(height: 2),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      ]);
}

// ========================================================================= level up

class _LevelUpDialog extends StatelessWidget {
  final int level;
  final String name;
  const _LevelUpDialog({required this.level, required this.name});

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          behavior: HitTestBehavior.opaque,
          child: Stack(children: [
            const Positioned.fill(child: ParticleBurst(colors: [Color(0xFFFDE047), Color(0xFFF472B6), Color(0xFF38BDF8), Color(0xFF4ADE80), Colors.white], origin: Alignment(0, -0.1), count: 120, duration: Duration(milliseconds: 3400))),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.elasticOut,
                builder: (_, v, __) => Transform.scale(
                  scale: v.clamp(0.0, 1.2),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    LevelBadge(level: level, progress: 1, size: 180),
                    const SizedBox(height: 18),
                    Text(context.t('rewards.level_up'), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(name.isEmpty ? '${context.t('rewards.level')} $level' : name, style: const TextStyle(color: Color(0xFFFDE047), fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    Text(context.t('reward.tap_close'), style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
}
