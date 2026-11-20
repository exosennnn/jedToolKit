import 'dart:ui';

import 'package:flutter/cupertino.dart';

/// Space reserved at the bottom of each screen so content scrolls above the dock.
const double kDockClearance = 110;

/// The dock holds at most this many tabs. Everything else lives on Home.
const int kDockMaxItems = 3;

class JedDockItem {
  final String label;
  final IconData icon;

  /// Filled glyph shown when selected. Falls back to [icon].
  final IconData? activeIcon;

  const JedDockItem({required this.label, required this.icon, this.activeIcon});
}

/// Floating, frosted-glass, iOS-style tab dock (max [kDockMaxItems] items).
class JedDock extends StatelessWidget {
  final List<JedDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const JedDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  }) : assert(
         items.length <= kDockMaxItems,
         'JedDock supports at most $kDockMaxItems items',
       );

  static Color _a(Color c, double o) => c.withAlpha((o * 255).round());

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final idle = CupertinoColors.secondaryLabel.resolveFrom(context);
    // Follows the accent color chosen in Settings.
    final active = CupertinoTheme.of(context).primaryColor;

    // Same look as the tonEMU dock: a compact frosted pill with a hairline
    // border and a soft shadow. No highlight pill behind the selected tab; it
    // is shown by the accent color and a bolder label instead.
    final frosted = dark ? const Color(0xB31C1C1E) : const Color(0xB8F9F9FB);
    final hairline = CupertinoColors.label
        .resolveFrom(context)
        .withValues(alpha: dark ? 0.12 : 0.08);

    final items = this.items.take(kDockMaxItems).toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 290),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          boxShadow: [
            BoxShadow(
              color: _a(CupertinoColors.black, dark ? 0.45 : 0.14),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: frosted,
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: hairline, width: 0.7),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < items.length; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(i),
                      child: SizedBox(
                        width: 80, // wider than tonEMU: module names are longer
                        height: 50,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              i == selectedIndex
                                  ? (items[i].activeIcon ?? items[i].icon)
                                  : items[i].icon,
                              size: 22,
                              color: i == selectedIndex ? active : idle,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              items[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: i == selectedIndex
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: i == selectedIndex ? active : idle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
