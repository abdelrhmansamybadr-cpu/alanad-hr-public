import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import 'point_orb.dart';
import 'reward_effects.dart';

/// Round level badge: a slowly turning gradient ring, the streak as a bright arc, a passing shine and orbiting sparks.
class LevelBadge extends StatefulWidget {
  final int level;
  final double progress; // 0..1 towards the next level
  final double size;
  const LevelBadge({super.key, required this.level, required this.progress, this.size = 132});

  @override
  State<LevelBadge> createState() => _LevelBadgeState();
}

class _LevelBadgeState extends State<LevelBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _BadgePainter(_c.value, widget.progress),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.workspace_premium_rounded, color: Colors.white.withValues(alpha: 0.95), size: s * 0.27),
              Text('${widget.level}', style: TextStyle(color: Colors.white, fontSize: s * 0.3, fontWeight: FontWeight.w900, height: 1, shadows: const [Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))])),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  final double t;
  final double progress;
  _BadgePainter(this.t, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final outer = Rect.fromCircle(center: c, radius: r);

    // soft halo
    canvas.drawCircle(c, r * 0.98, Paint()..color = const Color(0xFFFBBF24).withValues(alpha: 0.28)..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22));

    // turning gradient ring
    canvas.drawCircle(
      c,
      r * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.09
        ..shader = SweepGradient(
          transform: GradientRotation(t * 2 * math.pi),
          colors: const [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFFC88453), Color(0xFF38BDF8), Color(0xFFFDE68A)],
        ).createShader(outer),
    );

    // body
    final body = Rect.fromCircle(center: c, radius: r * 0.78);
    canvas.drawCircle(c, r * 0.78, Paint()..shader = const RadialGradient(center: Alignment(-0.3, -0.5), colors: [Color(0xFF00617A), Color(0xFF00617A), Color(0xFF021A22)], stops: [0, 0.6, 1]).createShader(body));

    // streak arc
    final arc = Rect.fromCircle(center: c, radius: r * 0.86);
    canvas.drawArc(arc, -math.pi / 2, 2 * math.pi, false, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.045..color = Colors.white.withValues(alpha: 0.14));
    canvas.drawArc(
      arc,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.06
        ..color = Colors.white
        ..maskFilter = MaskFilter.blur(BlurStyle.solid, 1.5),
    );

    // passing shine
    canvas.save();
    canvas.clipPath(Path()..addOval(body));
    final shineX = (t * 2.2 % 1.0) * (size.width * 1.8) - size.width * 0.4;
    final shine = Path()
      ..moveTo(shineX, 0)
      ..lineTo(shineX + r * 0.35, 0)
      ..lineTo(shineX - r * 0.35 + r * 0.45, size.height)
      ..lineTo(shineX - r * 0.35, size.height)
      ..close();
    canvas.drawPath(shine, Paint()..color = Colors.white.withValues(alpha: 0.08));
    canvas.restore();

    // orbiting sparks
    for (var i = 0; i < 3; i++) {
      final a = t * 2 * math.pi * (i.isEven ? 1 : -1) + i * 2.1;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.99;
      canvas.drawCircle(p, r * 0.035, Paint()..color = Colors.white.withValues(alpha: 0.9)..maskFilter = MaskFilter.blur(BlurStyle.normal, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BadgePainter old) => old.t != t || old.progress != progress;
}

/// Flame-topped streak bar that fills when it appears.
class StreakBar extends StatelessWidget {
  final int streak;
  final int target;
  const StreakBar({super.key, required this.streak, required this.target});

  @override
  Widget build(BuildContext context) {
    final p = target <= 0 ? 0.0 : (streak / target).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFB923C), size: 20),
        const SizedBox(width: 6),
        Text(context.t('rewards.streak_days', {'n': streak, 'target': target}), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, box) {
        return Stack(children: [
          Container(height: 12, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8))),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: p),
            duration: const Duration(milliseconds: 1400),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Container(
              height: 12,
              width: math.max(12, box.maxWidth * v),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFFFDE047), Color(0xFFFB923C)]),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: const Color(0xFFFDE047).withValues(alpha: 0.5), blurRadius: 10)],
              ),
            ),
          ),
        ]);
      }),
    ]);
  }
}

/// The three points with their numbers.
class OrbRow extends StatelessWidget {
  final int green;
  final int red;
  final int black;
  final bool dark;
  const OrbRow({super.key, required this.green, required this.red, required this.black, this.dark = false});

  @override
  Widget build(BuildContext context) {
    Widget one(PointKind k, int v, double phase) => Expanded(
          child: Column(children: [
            PointOrb(kind: k, size: 38, phase: phase),
            CountUp(v, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: dark ? Colors.white : null, height: 1)),
            const SizedBox(height: 2),
            Text(context.t('rewards.${k.name}'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dark ? Colors.white70 : context.colors.subtext)),
          ]),
        );
    return Row(children: [one(PointKind.green, green, 0), one(PointKind.red, red, 0.33), one(PointKind.black, black, 0.66)]);
  }
}

/// "5 green points cancelled 1 black point": greens fly into the penalty point, which dissolves.
class ExchangeAnimation extends StatefulWidget {
  final PointKind target; // red | black
  final int cost; // greens that pay for one
  final int cancelled; // how many penalties were removed
  const ExchangeAnimation({super.key, required this.target, required this.cost, required this.cancelled});

  @override
  State<ExchangeAnimation> createState() => _ExchangeAnimationState();
}

class _ExchangeAnimationState extends State<ExchangeAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final greens = math.min(widget.cost, 6);
    final text = context.t(widget.target == PointKind.red ? 'rewards.exchange_red' : 'rewards.exchange_black', {'g': widget.cost * widget.cancelled, 'n': widget.cancelled});
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(children: [
        SizedBox(
          height: 84,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final t = _c.value;
                final fly = Curves.easeInOutCubic.transform(((t - 0.22) / 0.3).clamp(0.0, 1.0));   // greens travel
                final burst = ((t - 0.52) / 0.12).clamp(0.0, 1.0);                                     // flash
                final dissolve = Curves.easeIn.transform(((t - 0.56) / 0.2).clamp(0.0, 1.0));          // penalty fades
                final check = Curves.elasticOut.transform(((t - 0.72) / 0.22).clamp(0.0, 1.0));
                final reset = ((t - 0.93) / 0.07).clamp(0.0, 1.0);                                      // fade out before looping
                final targetX = w - 48.0;
                return Stack(clipBehavior: Clip.none, children: [
                  // penalty point on the right
                  Positioned(
                    left: targetX - 24,
                    top: 0,
                    child: Opacity(
                      opacity: (1 - dissolve) * Curves.easeOut.transform((t / 0.12).clamp(0.0, 1.0)),
                      child: Transform.scale(scale: 1 - 0.5 * dissolve + 0.12 * math.sin(burst * math.pi), child: PointOrb(kind: widget.target, size: 40, float: false)),
                    ),
                  ),
                  // flash ring
                  if (burst > 0 && dissolve < 1)
                    Positioned(
                      left: targetX - 12 - 40 * burst,
                      top: 28 - 40 * burst,
                      child: Container(
                        width: 48 + 80 * burst,
                        height: 48 + 80 * burst,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.9 * (1 - burst)), width: 3), boxShadow: [BoxShadow(color: const Color(0xFF4ADE80).withValues(alpha: 0.5 * (1 - burst)), blurRadius: 24)]),
                      ),
                    ),
                  // result check mark
                  Positioned(
                    left: targetX - 6,
                    top: 26,
                    child: Opacity(opacity: check * (1 - reset), child: Transform.scale(scale: check, child: Icon(Icons.check_circle_rounded, size: 32, color: context.colors.success))),
                  ),
                  // the green points
                  for (var i = 0; i < greens; i++)
                    Builder(builder: (_) {
                      final startX = 6.0 + i * 24;
                      final startY = 26.0 + (i.isEven ? 0 : 8);
                      final x = startX + (targetX - 6 - startX) * fly;
                      final y = startY + (26 - startY) * fly - math.sin(fly * math.pi) * 20;
                      final appear = Curves.easeOutBack.transform(((t - i * 0.03) / 0.16).clamp(0.0, 1.0));
                      final gone = fly >= 1.0 ? 0.0 : 1.0;
                      return Positioned(
                        left: x,
                        top: y,
                        child: Opacity(
                          opacity: gone * (1 - reset),
                          child: Transform.scale(scale: appear * (1 - 0.35 * fly), child: const PointOrb(kind: PointKind.green, size: 18, float: false, showShadow: false)),
                        ),
                      );
                    }),
                ]);
              },
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
      ]),
    );
  }
}

/// A small grid of the most recent days, each a coloured dot that pops in.
class DotCalendar extends StatefulWidget {
  final List<PointEntry> entries;
  const DotCalendar({super.key, required this.entries});

  @override
  State<DotCalendar> createState() => _DotCalendarState();
}

class _DotCalendarState extends State<DotCalendar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byDay = <String, PointEntry>{};
    for (final e in widget.entries.reversed) {
      if (!e.voided && e.source == 'auto') byDay[ymd(e.date)] = e;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // five calendar weeks ending with the current one, Monday first
    final start = today.subtract(Duration(days: today.weekday - 1 + 28));
    const dow = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

    return Column(children: [
      Row(children: [
        for (final d in dow) Expanded(child: Center(child: Text(context.t('weekday.$d').substring(0, context.isAr ? 3 : 1), style: TextStyle(color: context.colors.subtext, fontWeight: FontWeight.w700, fontSize: 11)))),
      ]),
      const SizedBox(height: 6),
      AnimatedBuilder(
        animation: _c,
        builder: (_, __) => GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.5,
          children: [
            for (var i = 0; i < 35; i++)
              Builder(builder: (context) {
                final date = start.add(Duration(days: i));
                final future = date.isAfter(today);
                final e = byDay[ymd(date)];
                final kind = e == null ? null : pointKindOf(e.color);
                final local = (_c.value * 1.8 - i * 0.02).clamp(0.0, 1.0);
                final scale = Curves.elasticOut.transform(local);
                final isToday = date == today;
                return Center(
                  child: Transform.scale(
                    scale: scale,
                    child: future
                        ? const SizedBox(width: 6, height: 6)
                        : Container(
                            width: kind == null ? 9 : 18,
                            height: kind == null ? 9 : 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: kind == null ? null : RadialGradient(center: const Alignment(-0.35, -0.4), colors: [kind.light, kind.base, kind.dark], stops: const [0, 0.55, 1]),
                              color: kind == null ? (e != null ? context.colors.subtext.withValues(alpha: 0.45) : context.colors.border) : null,
                              border: isToday ? Border.all(color: context.scheme.primary, width: 2) : null,
                              boxShadow: kind == null ? null : [BoxShadow(color: kind.glow.withValues(alpha: 0.45), blurRadius: 8)],
                            ),
                          ),
                  ),
                );
              }),
          ],
        ),
      ),
    ]);
  }
}

/// Home screen card: floating points, level and streak in one glance.
class RewardsCard extends StatelessWidget {
  final PointsBrief brief;
  final VoidCallback onTap;
  const RewardsCard({super.key, required this.brief, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = brief.streakTarget <= 0 ? 0.0 : (brief.streak / brief.streakTarget).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF021A22), Color(0xFF0A3B4A), Color(0xFF00617A)]),
          boxShadow: [BoxShadow(color: const Color(0xFF00617A).withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          const Positioned.fill(child: Starfield(count: 22)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.emoji_events_rounded, color: Color(0xFFFDE047), size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(context.t('rewards.title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                  child: Text(brief.levelName.isEmpty ? '${context.t('rewards.level')} ${brief.level}' : '${context.t('rewards.level')} ${brief.level} · ${brief.levelName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 4),
              OrbRow(green: brief.green, red: brief.red, black: brief.black, dark: true),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: p, minHeight: 8, color: const Color(0xFFFDE047), backgroundColor: Colors.white.withValues(alpha: 0.16)),
              ),
              const SizedBox(height: 6),
              Text(context.t('rewards.streak_days', {'n': brief.streak, 'target': brief.streakTarget}), style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}
