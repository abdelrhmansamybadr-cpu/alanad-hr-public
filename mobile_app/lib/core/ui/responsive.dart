import 'dart:math' as math;

import 'package:flutter/material.dart';

/// From this window width on the app uses the laptop layout: a side menu, wide pages, grids and dialogs.
const double kDesktopBreakpoint = 900;

extension ResponsiveX on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isDesktop => screenWidth >= kDesktopBreakpoint;
}

/// Keeps a page (a form, a detail page) at a comfortable reading width and centred on a laptop screen.
/// On a phone it does nothing.
class DesktopPage extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  const DesktopPage({super.key, required this.child, this.maxWidth = 880});

  @override
  Widget build(BuildContext context) {
    if (!context.isDesktop) return child;
    return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
  }
}

/// A scrolling list that becomes a multi-column grid when there is room (laptop), and stays a plain list on a phone.
class AdaptiveList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;
  final double gap;
  final double minTileWidth;
  final ScrollPhysics? physics;
  const AdaptiveList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 96),
    this.gap = 10,
    this.minTileWidth = 400,
    this.physics = const AlwaysScrollableScrollPhysics(),
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 760) {
          return ListView.separated(padding: padding, physics: physics, itemCount: itemCount, separatorBuilder: (_, __) => SizedBox(height: gap), itemBuilder: itemBuilder);
        }
        final pad = padding.resolve(Directionality.of(context));
        final avail = c.maxWidth - pad.horizontal;
        final cols = math.max(1, ((avail + gap) / (minTileWidth + gap)).floor());
        final tileW = (avail - gap * (cols - 1)) / cols;
        return ListView(padding: padding, physics: physics, children: [
          Wrap(spacing: gap, runSpacing: gap, children: [for (var i = 0; i < itemCount; i++) SizedBox(width: tileW, child: itemBuilder(context, i))]),
        ]);
      });
}

/// Two columns side by side on a laptop; one after the other (left first, then right) on a phone.
class SplitColumns extends StatelessWidget {
  final List<Widget> left;
  final List<Widget> right;
  final double gap;
  final int leftFlex;
  final int rightFlex;
  final double stackGap; // space between the two blocks when they are stacked (phone)
  const SplitColumns({super.key, required this.left, required this.right, this.gap = 20, this.leftFlex = 1, this.rightFlex = 1, this.stackGap = 0});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 760) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...left, if (stackGap > 0) SizedBox(height: stackGap), ...right]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: leftFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: left)),
          SizedBox(width: gap),
          Expanded(flex: rightFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: right)),
        ]);
      });
}

/// Non-scrolling grid of cards for use inside a ListView: one column on a phone, several on a laptop.
class ResponsiveWrap extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final double gap;
  const ResponsiveWrap({super.key, required this.children, this.minTileWidth = 400, this.gap = 14});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth < 760 ? 1 : math.max(1, ((c.maxWidth + gap) / (minTileWidth + gap)).floor());
        if (cols == 1) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}
