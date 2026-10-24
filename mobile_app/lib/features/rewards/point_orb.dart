import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The three point colours.
enum PointKind { green, red, black }

PointKind? pointKindOf(String color) {
  switch (color) {
    case 'green':
      return PointKind.green;
    case 'red':
      return PointKind.red;
    case 'black':
      return PointKind.black;
  }
  return null;
}

extension PointKindX on PointKind {
  Color get base {
    switch (this) {
      case PointKind.green:
        return const Color(0xFF22C55E);
      case PointKind.red:
        return const Color(0xFFEF4444);
      case PointKind.black:
        return const Color(0xFF1F2937);
    }
  }

  Color get light {
    switch (this) {
      case PointKind.green:
        return const Color(0xFFBBF7D0);
      case PointKind.red:
        return const Color(0xFFFECACA);
      case PointKind.black:
        return const Color(0xFF6B7280);
    }
  }

  Color get dark {
    switch (this) {
      case PointKind.green:
        return const Color(0xFF15803D);
      case PointKind.red:
        return const Color(0xFFB91C1C);
      case PointKind.black:
        return const Color(0xFF030712);
    }
  }

  /// Colour of the glow around the orb (black glows a cold white-blue so it stays visible on dark cards).
  Color get glow {
    switch (this) {
      case PointKind.green:
        return const Color(0xFF4ADE80);
      case PointKind.red:
        return const Color(0xFFF87171);
      case PointKind.black:
        return const Color(0xFF94A3B8);
    }
  }
}

/// A glossy, softly floating point with a glow and a moving shadow on the ground.
class PointOrb extends StatefulWidget {
  final PointKind kind;
  final double size;
  final bool float;
  final double phase; // 0..1 offset so several orbs do not bob in sync
  final Widget? child;
  final bool showShadow;

  const PointOrb({super.key, required this.kind, this.size = 56, this.float = true, this.phase = 0, this.child, this.showShadow = true});

  @override
  State<PointOrb> createState() => _PointOrbState();
}

class _PointOrbState extends State<PointOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));

  @override
  void initState() {
    super.initState();
    if (widget.float) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant PointOrb old) {
    super.didUpdateWidget(old);
    if (widget.float && !_c.isAnimating) _c.repeat();
    if (!widget.float && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.5,
      height: s * 1.42,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = (_c.value + widget.phase) % 1.0;
          final bob = widget.float ? math.sin(t * 2 * math.pi) : 0.0; // -1..1
          return CustomPaint(
            painter: _OrbPainter(kind: widget.kind, bob: bob, t: t, showShadow: widget.showShadow),
            child: widget.child == null ? null : Align(alignment: const Alignment(0, -0.22), child: Transform.translate(offset: Offset(0, -bob * s * 0.05), child: widget.child)),
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final PointKind kind;
  final double bob;
  final double t;
  final bool showShadow;
  const _OrbPainter({required this.kind, required this.bob, required this.t, required this.showShadow});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 3; // orb radius (canvas is 1.5 x size wide)
    final cx = size.width / 2;
    final groundY = size.height - r * 0.22;
    final cy = groundY - r * 1.25 - bob * r * 0.14; // floats above its shadow

    // ---- shadow on the ground: narrower and fainter while the orb rises
    if (showShadow) {
      final k = 1 - 0.18 * (bob + 1) / 2 * 2; // 1 .. 0.64
      final shadow = Rect.fromCenter(center: Offset(cx, groundY), width: r * 1.7 * k, height: r * 0.42 * k);
      canvas.drawOval(
        shadow,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.26 * k)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
      );
    }

    // ---- glow (breathes)
    final glow = 0.75 + 0.25 * math.sin(t * 2 * math.pi * 2);
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.22,
      Paint()
        ..color = kind.glow.withValues(alpha: 0.42 * glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55),
    );

    // ---- body
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.0,
          colors: [kind.light, kind.base, kind.dark],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(rect),
    );

    // ---- rim light, a slowly turning sweep
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..shader = SweepGradient(
          transform: GradientRotation(t * 2 * math.pi),
          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.34), Colors.white.withValues(alpha: 0)],
          stops: const [0.0, 0.12, 0.3],
        ).createShader(rect),
    );
    canvas.restore();

    // ---- glossy highlight
    final hl = Rect.fromCenter(center: Offset(cx - r * 0.3, cy - r * 0.46), width: r * 0.9, height: r * 0.5);
    canvas.drawOval(
      hl,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0.0)]).createShader(hl),
    );
    // small secondary sparkle
    canvas.drawCircle(Offset(cx + r * 0.42, cy + r * 0.38), r * 0.06, Paint()..color = Colors.white.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => old.bob != bob || old.t != t || old.kind != kind;
}

/// Counts up to [value] when it appears or changes.
class CountUp extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  const CountUp(this.value, {super.key, this.style, this.duration = const Duration(milliseconds: 1100)});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('${v.round()}', style: style),
      );
}
