import 'package:flutter/cupertino.dart';

/// Large-title page used by Settings and its sub-screens.
class SettingsPage extends StatelessWidget {
  final String title;
  final List<Widget> slivers;
  final Widget? trailing;

  const SettingsPage({
    super.key,
    required this.title,
    required this.slivers,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    return CupertinoPageScaffold(
      backgroundColor: bg,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(title),
            trailing: trailing,
            backgroundColor: bg,
            border: null,
          ),
          ...slivers,
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 32),
          ),
        ],
      ),
    );
  }
}

/// iOS: SettingsCardModifier.
class SettingsCard extends StatelessWidget {
  final Widget child;
  const SettingsCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: CupertinoColors.label.resolveFrom(context).withAlpha(10),
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  final String text;
  const SettingsSectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

class SettingsFootnote extends StatelessWidget {
  final String text;
  const SettingsFootnote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  final double indent;
  const SettingsDivider({super.key, this.indent = 80});

  @override
  Widget build(BuildContext context) => Container(
        height: 0.5,
        margin: EdgeInsets.only(left: indent),
        color: CupertinoColors.separator.resolveFrom(context),
      );
}

/// Full-width row with an iOS-style gray highlight while pressed.
class SettingsPressRow extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const SettingsPressRow({super.key, required this.child, this.onTap});

  @override
  State<SettingsPressRow> createState() => _SettingsPressRowState();
}

class _SettingsPressRowState extends State<SettingsPressRow> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _down
            ? CupertinoColors.systemGrey5.resolveFrom(context)
            : const Color(0x00000000),
        child: widget.child,
      ),
    );
  }
}

/// iOS: SettingsRowView — tinted icon box, title, optional detail, chevron.
class SettingsNavRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? detail;
  final VoidCallback? onTap;
  final bool chevron;

  /// Replaces the chevron, e.g. a switch.
  final Widget? trailing;

  const SettingsNavRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.detail,
    this.onTap,
    this.chevron = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsPressRow(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (chevron && onTap != null)
              Icon(
                CupertinoIcons.chevron_forward,
                size: 14,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
          ],
        ),
      ),
    );
  }
}
