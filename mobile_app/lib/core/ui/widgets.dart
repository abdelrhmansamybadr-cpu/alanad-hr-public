import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'responsive.dart';
import '../api/api.dart';
import '../i18n/strings.dart';
import 'format.dart';

// ======================================================================= surfaces

/// The standard card: rounded, soft border, optional tap.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final bool shadow;

  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.gradient, this.shadow = false});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? context.scheme.surface) : null,
        gradient: gradient,
        borderRadius: radius,
        border: gradient == null ? Border.all(color: context.colors.border) : null,
        boxShadow: shadow
            ? [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.06), blurRadius: 18, offset: const Offset(0, 6))]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Brand-coloured gradient used for hero cards and headers.
LinearGradient brandGradient(BuildContext context) {
  final p = context.scheme.primary;
  final hsl = HSLColor.fromColor(p);
  final darker = hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).withHue((hsl.hue + 18) % 360).toColor();
  return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p, darker]);
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 10)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(title, style: context.text.titleMedium)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

// ==================================================================== small pieces

Color statusColor(BuildContext c, String status) {
  final k = c.colors;
  switch (status) {
    case 'approved':
    case 'paid':
    case 'present':
    case 'active':
    case 'hired':
    case 'open':
      return k.success;
    case 'half_day':
      return const Color(0xFFF97316);
    case 'pending':
    case 'late':
    case 'draft':
    case 'screening':
    case 'interview':
      return k.warning;
    case 'rejected':
    case 'absent':
    case 'cancelled':
    case 'disabled':
    case 'suspended':
      return k.danger;
    case 'on_leave':
    case 'offer':
    case 'submitted':
    case 'new':
      return k.info;
    default:
      return k.subtext;
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  final String? label;
  final Color? color;
  const StatusChip(this.status, {super.key, this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(label ?? context.t('status.$status'), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final bool ring;
  const Avatar({super.key, required this.name, this.url, this.size = 44, this.ring = false});

  @override
  Widget build(BuildContext context) {
    final base = colorFor(name);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [base, base.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Text(initials(name), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
    Widget child = (url == null || url!.isEmpty)
        ? fallback
        : ClipOval(
            child: CachedNetworkImage(
              imageUrl: absUrl(url!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            ),
          );
    if (ring) {
      child = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.scheme.primary, width: 2)),
        child: child,
      );
    }
    return child;
  }
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(this.icon, {super.key, required this.color, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.32)),
        child: Icon(icon, color: color, size: size * 0.52),
      );
}

/// A label + big value tile used in KPI grids.
class StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;
  const StatTile({super.key, required this.icon, required this.color, required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          IconBadge(icon, color: color, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.05, fontSize: 20), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(label, style: TextStyle(color: context.colors.subtext, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const InfoRow({super.key, required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(icon, size: 20, color: context.colors.subtext),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: context.colors.subtext))),
            const SizedBox(width: 12),
            Flexible(child: Text(value.isEmpty ? '—' : value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
      );
}

/// Circular progress with a child in the middle (leave balances, attendance rate).
class ProgressRing extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;
  const ProgressRing({super.key, required this.value, required this.color, this.size = 72, this.stroke = 8, this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(size: Size.square(size), painter: _RingPainter(v, color, context.colors.border, stroke)),
          ),
          if (child != null) child!,
        ]),
      );
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double stroke;
  _RingPainter(this.value, this.color, this.track, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final deflated = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(deflated, 0, math.pi * 2, false, base);
    if (value > 0) {
      canvas.drawArc(deflated, -math.pi / 2, math.pi * 2 * value, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

// ============================================================== states / loading

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: context.colors.brandSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 38, color: context.scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: TextStyle(color: context.colors.subtext), textAlign: TextAlign.center),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, style: FilledButton.styleFrom(minimumSize: const Size(160, 48)), child: Text(actionLabel!)),
            ],
          ]),
        ),
      );
}

class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const ErrorState(this.error, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final network = error is ApiException && (error as ApiException).isNetwork;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(network ? Icons.wifi_off_rounded : Icons.error_outline_rounded, size: 52, color: context.colors.subtext),
          const SizedBox(height: 14),
          Text(errorText(context, error), textAlign: TextAlign.center, style: TextStyle(color: context.colors.subtext)),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(context.t('common.retry')), style: OutlinedButton.styleFrom(minimumSize: const Size(160, 46))),
          ],
        ]),
      ),
    );
  }
}

String errorText(BuildContext context, Object e) => e is ApiException ? e.message : context.t('common.error.generic');

/// Pulsing placeholder block.
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const Skeleton({super.key, this.width, this.height = 16, this.radius = 10});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.surfaceAlt;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(base, context.colors.border, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;
  const SkeletonList({super.key, this.count = 6, this.itemHeight = 76});

  @override
  Widget build(BuildContext context) => ListView.separated(
        shrinkWrap: true, // also works inside another scrolling list (e.g. the payroll page)
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Skeleton(width: 46, height: 46, radius: 23),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Skeleton(width: 140 + (count % 3) * 20.0, height: 14),
              const SizedBox(height: 10),
              const Skeleton(width: 90, height: 12),
            ])),
          ]),
        ),
      );
}

/// Renders an [AsyncValue] with skeleton / error / data states. Keeps old data visible while refreshing.
class AsyncBody<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  final Widget? loading;
  const AsyncBody({super.key, required this.value, required this.builder, required this.onRetry, this.loading});

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) return ErrorState(value.error!, onRetry: onRetry);
    return loading ?? const SkeletonList();
  }
}

// ================================================================ buttons & fields

class LoadingButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? color;
  final bool outlined;
  const LoadingButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon, this.color, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: outlined ? null : Colors.white))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]);
    final action = loading ? null : onPressed;
    if (outlined) return OutlinedButton(onPressed: action, child: child);
    return FilledButton(onPressed: action, style: color == null ? null : FilledButton.styleFrom(backgroundColor: color), child: child);
  }
}

class AppField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final int maxLines;
  final bool enabled;
  final String? hint;
  final TextInputAction? action;
  final void Function(String)? onSubmitted;
  final void Function(String)? onChanged;
  final Widget? suffix;
  final List<TextInputFormatter>? formatters;
  final TextCapitalization capitalization;
  final bool autofocus;
  final int? maxLength;
  final String? initialValue;
  final bool readOnly;
  final VoidCallback? onTap;

  const AppField({
    super.key,
    this.controller,
    required this.label,
    this.icon,
    this.obscure = false,
    this.keyboard,
    this.validator,
    this.maxLines = 1,
    this.enabled = true,
    this.hint,
    this.action,
    this.onSubmitted,
    this.onChanged,
    this.suffix,
    this.formatters,
    this.capitalization = TextCapitalization.none,
    this.autofocus = false,
    this.maxLength,
    this.initialValue,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        obscureText: obscure,
        keyboardType: keyboard,
        validator: validator,
        maxLines: obscure ? 1 : maxLines,
        enabled: enabled,
        readOnly: readOnly,
        onTap: onTap,
        textInputAction: action,
        onFieldSubmitted: onSubmitted,
        onChanged: onChanged,
        inputFormatters: formatters,
        textCapitalization: capitalization,
        autofocus: autofocus,
        maxLength: maxLength,
        decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: icon == null ? null : Icon(icon, size: 22), suffixIcon: suffix, counterText: ''),
      );
}

String? requiredValidator(BuildContext c, String? v) => (v == null || v.trim().isEmpty) ? c.t('common.required') : null;

String? emailValidator(BuildContext c, String? v) {
  if (v == null || v.trim().isEmpty) return c.t('common.required');
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : c.t('common.invalid_email');
}

/// An optional mobile number: empty is fine, otherwise 8 to 15 digits (a leading + and common separators are allowed).
String? phoneOptionalValidator(BuildContext c, String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return null;
  if (!RegExp(r'^\+?[0-9\s\-().]+$').hasMatch(t)) return c.t('common.invalid_phone');
  final digits = t.replaceAll(RegExp(r'\D'), '').length;
  return digits >= 8 && digits <= 15 ? null : c.t('common.invalid_phone');
}

/// Sign-in name: an e-mail address OR a mobile number.
String? identityValidator(BuildContext c, String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return c.t('common.required');
  if (t.contains('@')) return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : c.t('common.invalid_email');
  return phoneOptionalValidator(c, t) == null ? null : c.t('common.invalid_identity');
}

String? passwordValidator(BuildContext c, String? v) {
  if (v == null || v.isEmpty) return c.t('common.required');
  return v.length >= 8 ? null : c.t('common.min_password');
}

// ==================================================================== sheets, toasts

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Row(children: [
      Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: error ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7), size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ]),
    duration: Duration(seconds: error ? 4 : 2),
  ));
}

Future<T?> showAppSheet<T>(BuildContext context, {required String title, required Widget child, bool scroll = true}) {
  // On a laptop a sheet that slides up from the bottom looks wrong: show a centred dialog instead.
  if (context.isDesktop) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 620, maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 4),
              child: Row(children: [
                Expanded(child: Text(title, style: ctx.text.titleLarge)),
                IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Flexible(
              child: scroll ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), child: child) : Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), child: child),
            ),
          ]),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(width: 44, height: 5, decoration: BoxDecoration(color: ctx.colors.border, borderRadius: BorderRadius.circular(3))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
          child: Row(children: [
            Expanded(child: Text(title, style: ctx.text.titleLarge)),
            IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Flexible(
          child: scroll ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), child: child) : Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), child: child),
        ),
      ]),
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? message, String? confirmLabel, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('common.cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44), backgroundColor: danger ? ctx.colors.danger : null),
          child: Text(confirmLabel ?? ctx.t('common.confirm')),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// A two-line list row with leading widget, used everywhere (people, requests, notifications...).
class RowTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? bottom;
  const RowTile({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.bottom});

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: TextStyle(color: context.colors.subtext, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ]),
          if (bottom != null) ...[const SizedBox(height: 12), bottom!],
        ]),
      );
}

/// Segmented pill switcher (e.g. Leaves | Requests).
class SegmentBar extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const SegmentBar({super.key, required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: context.colors.surfaceAlt, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? context.scheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: i == index ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))] : null,
                  ),
                  child: Text(labels[i], style: TextStyle(fontWeight: i == index ? FontWeight.w800 : FontWeight.w600, color: i == index ? context.scheme.primary : context.colors.subtext)),
                ),
              ),
            ),
        ]),
      );
}

/// Horizontal filter chips.
class FilterChips extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const FilterChips({super.key, required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => ChoiceChip(
            label: Text(labels[i]),
            selected: i == index,
            onSelected: (_) => onChanged(i),
            showCheckmark: false,
            selectedColor: context.scheme.primary,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: i == index ? Colors.white : context.scheme.onSurface),
          ),
        ),
      );
}


/// The bell in the dashboard header. Always a 44 px rounded square with the icon in the middle;
/// the unread count is a small badge pinned to the corner, so it never changes the button's size or shape.
class NotificationBell extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const NotificationBell({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : '$count';
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: Material(
            color: context.scheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: context.colors.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: const Center(child: Icon(Icons.notifications_none_rounded))),
          ),
        ),
        if (count > 0)
          PositionedDirectional(
            top: -6,
            end: -6,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: context.colors.danger, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.scheme.surface, width: 2)),
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.1)),
              ),
            ),
          ),
      ]),
    );
  }
}
