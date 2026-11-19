import 'dart:ui';
import 'package:flutter/cupertino.dart';

/// Space reserved at the bottom of each screen so content scrolls above the dock.
const double kDockClearance = 110;

class JedDockItem {
  final String label;
  final IconData icon;
  const JedDockItem({required this.label, required this.icon});
}

/// Floating, blurred, iOS-style tab dock.
class JedDock extends StatelessWidget {
  final List<JedDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const JedDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final idle = CupertinoColors.secondaryLabel.resolveFrom(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground.resolveFrom(context).withOpacity(0.78),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelected(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[i].icon,
                          size: 24,
                          color: i == selectedIndex ? CupertinoColors.activeBlue : idle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                i == selectedIndex ? FontWeight.w600 : FontWeight.w400,
                            color: i == selectedIndex ? CupertinoColors.activeBlue : idle,
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
    );
  }
}