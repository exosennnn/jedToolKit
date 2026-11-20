import 'package:flutter/cupertino.dart';

import 'hw_test.dart';

Color hwLabel(BuildContext c, double opacity) =>
    CupertinoColors.label.resolveFrom(c).withOpacity(opacity);

/// iOS card: secondaryGroupedBackground, radius 20, 4% stroke, soft shadow.
BoxDecoration hwCardDecoration(BuildContext c) => BoxDecoration(
  color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(c),
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: hwLabel(c, 0.04)),
  boxShadow: [
    BoxShadow(
      color: CupertinoColors.black.withOpacity(0.03),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ],
);

/// Card with 24pt horizontal margin, as used on every iOS test page.
class HwCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const HwCard({super.key, required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: hwCardDecoration(context),
      child: child,
    ),
  );
}

/// Capsule status pill. Tinted when [active], neutral grey otherwise.
class HwStatusPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool active;
  const HwStatusPill({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? color : CupertinoColors.secondaryLabel.resolveFrom(context);
    final bg = active ? color.withOpacity(0.08) : hwLabel(context, 0.04);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pass / Fail bar pinned to the bottom, with the divider on top.
class HwBottomBar extends StatelessWidget {
  final bool canPass;
  final bool canFail;
  final VoidCallback onPass;
  final VoidCallback onFail;
  const HwBottomBar({
    super.key,
    required this.canPass,
    required this.canFail,
    required this.onPass,
    required this.onFail,
  });

  Widget _button(
    BuildContext context, {
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final off = CupertinoColors.systemGrey4.resolveFrom(context);
    return Expanded(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        onPressed: enabled ? onTap : null,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? color : off,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: enabled
                  ? CupertinoColors.white
                  : CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
            child: Row(
              children: [
                _button(
                  context,
                  label: 'Pass Test',
                  color: CupertinoColors.systemGreen.resolveFrom(context),
                  enabled: canPass,
                  onTap: onPass,
                ),
                const SizedBox(width: 12),
                _button(
                  context,
                  label: 'Fail Test',
                  color: CupertinoColors.systemRed.resolveFrom(context),
                  enabled: canFail,
                  onTap: onFail,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard test page: nav bar, instruction banner, [content], Pass/Fail bar.
/// Pass/Fail pops the route with a [HwTestState] unless [onComplete] is given.
class HwTestPage extends StatelessWidget {
  final String title;
  final String instruction;
  final Widget content;
  final bool canPass;
  final bool canFail;
  final ValueChanged<bool>? onComplete;

  const HwTestPage({
    super.key,
    required this.title,
    required this.instruction,
    required this.content,
    this.canPass = true,
    this.canFail = true,
    this.onComplete,
  });

  void _finish(BuildContext context, bool ok) {
    if (onComplete != null) {
      onComplete!(ok);
    } else {
      Navigator.of(context).pop(ok ? HwTestState.passed : HwTestState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        instruction,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    content,
                  ],
                ),
              ),
            ),
            HwBottomBar(
              canPass: canPass,
              canFail: canFail,
              onPass: () => _finish(context, true),
              onFail: () => _finish(context, false),
            ),
          ],
        ),
      ),
    );
  }
}