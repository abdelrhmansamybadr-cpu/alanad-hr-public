import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One tab of the floating bar.
class FloatingNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
  const FloatingNavItem({required this.icon, required this.selectedIcon, required this.label, this.badge = 0});
}

/// A floating, pill-shaped bottom bar: dark rounded capsule, a soft highlight that
/// glides to the selected tab, and a red count badge.
class FloatingNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<FloatingNavItem> items;
  const FloatingNavBar({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF26272B) : const Color(0xFF1F2024);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth / items.length;
            final slot = rtl ? items.length - 1 - index : index;
            return Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutBack,
                left: slot * w + 5,
                top: 6,
                width: w - 10,
                height: 54,
                child: Container(decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(32))),
              ),
              Row(children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: items[i].label,
                      child: InkResponse(
                        radius: 34,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onTap(i);
                        },
                        child: Center(child: _Icon(item: items[i], selected: i == index)),
                      ),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  final FloatingNavItem item;
  final bool selected;
  const _Icon({required this.item, required this.selected});

  @override
  Widget build(BuildContext context) {
    final icon = AnimatedScale(
      scale: selected ? 1.12 : 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: Icon(selected ? item.selectedIcon : item.icon, size: 28, color: selected ? Colors.white : Colors.white70),
    );
    if (item.badge <= 0) return icon;
    return Badge(
      backgroundColor: const Color(0xFFE41E3F),
      textColor: Colors.white,
      label: Text(item.badge > 9 ? '9+' : '${item.badge}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
      child: icon,
    );
  }
}
