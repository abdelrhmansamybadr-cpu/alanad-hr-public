import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import 'point_orb.dart';

/// Particles that burst from a point and fall with gravity (confetti for good days, embers/ash for bad ones).
class ParticleBurst extends StatefulWidget {
  final List<Color> colors;
  final int count;
  final Duration duration;
  final Alignment origin;
  final double gravity;
  final double spread; // radians of the fan (2*pi = all around)
  final bool squares;

  const ParticleBurst({
    super.key,
    required this.colors,
    this.count = 70,
    this.duration = const Duration(milliseconds: 2800),
    this.origin = Alignment.center,
    this.gravity = 900,
    this.spread = math.pi * 2,
    this.squares = true,
  });

  @override
  State<ParticleBurst> createState() => _ParticleBurstState();
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final double spin;
  final Color color;
  final double delay;
  const _Particle(this.angle, this.speed, this.size, this.spin, this.color, this.delay);
}

class _ParticleBurstState extends State<ParticleBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)..forward();
  late final List<_Particle> _ps;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    final start = -math.pi / 2 - widget.spread / 2;
    _ps = List.generate(widget.count, (i) {
      return _Particle(
        start + rnd.nextDouble() * widget.spread,
        180 + rnd.nextDouble() * 520,
        5 + rnd.nextDouble() * 8,
        (rnd.nextDouble() - 0.5) * 14,
        widget.colors[rnd.nextInt(widget.colors.length)],
        rnd.nextDouble() * 0.12,
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(size: Size.infinite, painter: _BurstPainter(_ps, _c.value, widget.duration.inMilliseconds / 1000, widget.origin, widget.gravity, widget.squares)),
        ),
      );
}

class _BurstPainter extends CustomPainter {
  final List<_Particle> ps;
  final double t; // 0..1
  final double seconds;
  final Alignment origin;
  final double gravity;
  final bool squares;
  _BurstPainter(this.ps, this.t, this.seconds, this.origin, this.gravity, this.squares);

  @override
  void paint(Canvas canvas, Size size) {
    final o = Offset(size.width * (origin.x + 1) / 2, size.height * (origin.y + 1) / 2);
    for (final p in ps) {
      final tt = ((t - p.delay).clamp(0.0, 1.0)) * seconds;
      if (tt <= 0) continue;
      final drag = 1 - math.exp(-tt * 2.2);
      final x = o.dx + math.cos(p.angle) * p.speed * drag * 0.9;
      final y = o.dy + math.sin(p.angle) * p.speed * drag * 0.9 + 0.5 * gravity * tt * tt * 0.6;
      final fade = (1 - ((t - 0.65) / 0.35).clamp(0.0, 1.0));
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * tt);
      if (squares) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55), const Radius.circular(1.5)), paint);
      } else {
        canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}

/// Twinkling stars for dark hero cards.
class Starfield extends StatefulWidget {
  final int count;
  const Starfield({super.key, this.count = 26});

  @override
  State<Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<Starfield> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
  late final List<List<double>> _stars;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _stars = List.generate(widget.count, (_) => [rnd.nextDouble(), rnd.nextDouble(), 0.6 + rnd.nextDouble() * 1.8, rnd.nextDouble()]);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(size: Size.infinite, painter: _StarPainter(_stars, _c.value)),
        ),
      );
}

class _StarPainter extends CustomPainter {
  final List<List<double>> stars;
  final double t;
  _StarPainter(this.stars, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stars) {
      final tw = 0.5 + 0.5 * math.sin((t + s[3]) * 2 * math.pi);
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[2], Paint()..color = Colors.white.withValues(alpha: 0.15 + 0.55 * tw));
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) => old.t != t;
}

// ============================================================ end-of-day celebration

/// Full-screen moment shown right after check-out: today's point drops in, bounces and settles.
Future<void> showRewardCelebration(BuildContext context, PointReward reward) {
  final kind = pointKindOf(reward.color);
  if (kind == null) return Future.value();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'reward',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => _Celebration(kind: kind, reason: reward.reason),
    transitionBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  );
}

class _Celebration extends StatefulWidget {
  final PointKind kind;
  final String reason;
  const _Celebration({required this.kind, required this.reason});

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 4200), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final good = widget.kind == PointKind.green;
    final key = widget.kind.name;
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: Stack(children: [
          if (good) const Positioned.fill(child: ParticleBurst(colors: [Color(0xFF22C55E), Color(0xFFFDE047), Color(0xFF38BDF8), Color(0xFFF472B6), Colors.white], origin: Alignment(0, -0.1), count: 90)),
          if (!good)
            Positioned.fill(
              child: ParticleBurst(colors: [widget.kind.glow.withValues(alpha: 0.9), Colors.white24, Colors.white38], origin: const Alignment(0, -0.25), count: 36, squares: false, gravity: 1400, spread: math.pi * 0.9),
            ),
          Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final drop = Curves.bounceOut.transform(_c.value.clamp(0.0, 1.0));
                final shake = good ? 0.0 : math.sin(_c.value * math.pi * 14) * (1 - _c.value) * 10;
                final textIn = Curves.easeOut.transform(((_c.value - 0.55) / 0.45).clamp(0.0, 1.0));
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Transform.translate(
                    offset: Offset(shake, -260 * (1 - drop)),
                    child: Transform.scale(scale: 0.4 + 0.9 * drop.clamp(0.0, 1.0), child: PointOrb(kind: widget.kind, size: 120)),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: textIn,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - textIn)),
                      child: Column(children: [
                        Text(context.t('reward.$key.title'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Text(context.t('reward.reason.${widget.reason}'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15, height: 1.4)),
                        ),
                        const SizedBox(height: 22),
                        Text(context.t('reward.tap_close'), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                      ]),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
