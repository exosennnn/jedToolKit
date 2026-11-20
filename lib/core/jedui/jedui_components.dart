import 'package:flutter/cupertino.dart';

import '../../modules/phoneinfo/phone_info.dart';
import 'jedui_theme.dart';

/// Rounded iOS-style card on the grouped background.
class JedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const JedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    return onTap == null ? card : JedPressable(onTap: onTap, child: card);
  }
}

Color jedOnColor(Color bg) =>
    bg.computeLuminance() > 0.9 ? CupertinoColors.black : CupertinoColors.white;

/// Subtle press feedback (scale + fade), like iOS widgets.
class JedPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const JedPressable({super.key, required this.child, this.onTap});

  @override
  State<JedPressable> createState() => _JedPressableState();
}

class _JedPressableState extends State<JedPressable> {
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
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Colored rounded-square glyph badge, like the icons in iOS Settings.
class JedIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const JedIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final base = CupertinoDynamicColor.resolve(color, context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [base.withOpacity(0.85), base],
        ),
      ),
      child: Icon(icon, size: size * 0.56, color: jedOnColor(base)),
    );
  }
}

/// Small tinted capsule, e.g. "Passed" or "Soon".
class JedPill extends StatelessWidget {
  final String label;
  final Color color;

  const JedPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = CupertinoDynamicColor.resolve(color, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

/// Uppercase-style label above a group of cards.
class JedSectionLabel extends StatelessWidget {
  final String text;

  const JedSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

/// Small explanatory text under a card.
class JedFootnote extends StatelessWidget {
  final String text;

  const JedFootnote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

/// One card holding several rows separated by hairline dividers.
class JedGroupCard extends StatelessWidget {
  final List<Widget> children;

  const JedGroupCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final sep = CupertinoColors.separator.resolveFrom(context);
    return JedCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 16),
                  color: sep,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Glyph + tint for a Phone Info row, guessed from its label
/// (the Android collector doesn't send icons).
(IconData, Color) jedFieldStyle(String label) {
  final l = label.toLowerCase();
  bool has(List<String> keys) => keys.any(l.contains);

  if (has(['battery', 'charg'])) {
    return (CupertinoIcons.battery_full, CupertinoColors.systemGreen);
  }
  if (has(['temperature', 'thermal'])) {
    return (CupertinoIcons.thermometer, CupertinoColors.systemOrange);
  }
  if (has(['ram', 'memory'])) {
    return (CupertinoIcons.memories, CupertinoColors.systemPurple);
  }
  if (has(['storage', 'disk', 'space'])) {
    return (CupertinoIcons.folder_fill, CupertinoColors.systemTeal);
  }
  if (has(['gpu', 'graphics', 'renderer', 'opengl', 'vulkan'])) {
    return (CupertinoIcons.sparkles, CupertinoColors.systemPink);
  }
  if (has(['display', 'screen', 'resolution', 'density', 'refresh', 'dpi'])) {
    return (CupertinoIcons.tv_fill, CupertinoColors.systemCyan);
  }
  if (has(['cpu', 'processor', 'core', 'abi', 'frequency', 'speed'])) {
    return (CupertinoIcons.bolt_fill, CupertinoColors.systemOrange);
  }
  if (has(['soc', 'chip', 'board', 'hardware'])) {
    return (CupertinoIcons.square_grid_2x2_fill, CupertinoColors.systemIndigo);
  }
  if (has(['wi-fi', 'wifi'])) {
    return (CupertinoIcons.wifi, CupertinoColors.systemGreen);
  }
  if (has(['bluetooth'])) {
    return (CupertinoIcons.bluetooth, CupertinoColors.systemBlue);
  }
  if (has(['camera'])) {
    return (CupertinoIcons.camera_fill, CupertinoColors.systemGrey);
  }
  if (has(['security', 'update'])) {
    return (CupertinoIcons.shield_fill, CupertinoColors.systemGreen);
  }
  if (has(['android', 'version', 'sdk', 'patch', 'build', 'release'])) {
    return (
      CupertinoIcons.chevron_left_slash_chevron_right,
      CupertinoColors.systemGreen,
    );
  }
  if (has([
    'device',
    'model',
    'manufacturer',
    'brand',
    'product',
    'name',
    'made by',
    'phone',
  ])) {
    return (CupertinoIcons.device_phone_portrait, CupertinoColors.systemBlue);
  }
  if (has(['uptime', 'time'])) {
    return (CupertinoIcons.clock, CupertinoColors.systemYellow);
  }
  if (has(['serial', 'uuid', 'imei', 'fingerprint'])) {
    return (CupertinoIcons.barcode, CupertinoColors.systemGrey);
  }
  return (CupertinoIcons.info_circle, CupertinoColors.systemGrey);
}

/// Phone Info section: uppercase header above one rounded card of rows.
class JedSection extends StatelessWidget {
  final InfoSection section;

  /// When set, every row glyph uses this color (e.g. the Settings accent)
  /// instead of the per-label colors from [jedFieldStyle].
  final Color? tint;

  const JedSection({super.key, required this.section, this.tint});

  @override
  Widget build(BuildContext context) {
    final sep = CupertinoColors.separator.resolveFrom(context);
    final fields = section.fields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            section.title.toUpperCase(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: CupertinoColors.label
                  .resolveFrom(context)
                  .withOpacity(0.04),
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                JedInfoRow(field: fields[i], tint: tint),
                if (i != fields.length - 1)
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 64),
                    color: sep,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One row: tinted glyph, title, trailing value. Long values wrap.
/// Percent values on level/usage rows also get a progress bar.
class JedInfoRow extends StatelessWidget {
  final InfoField field;

  /// Overrides the glyph color from [jedFieldStyle] when non-null.
  final Color? tint;

  const JedInfoRow({super.key, required this.field, this.tint});

  double? get _progress {
    final value = field.value;
    if (field.status != DataStatus.available || value == null) return null;
    final l = field.label.toLowerCase();
    if (!(l.contains('level') || l.contains('usage') || l.contains('used'))) {
      return null;
    }
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(value);
    if (m == null) return null;
    return (double.parse(m.group(1)!) / 100).clamp(0.0, 1.0).toDouble();
  }

  Color _barColor(double p) {
    final isUsage = field.label.toLowerCase().contains('us');
    if (isUsage) {
      return p > 0.9
          ? CupertinoColors.systemRed
          : (p > 0.75
                ? CupertinoColors.systemYellow
                : CupertinoColors.systemGreen);
    }
    return p < 0.2
        ? CupertinoColors.systemRed
        : (p < 0.5
              ? CupertinoColors.systemYellow
              : CupertinoColors.systemGreen);
  }

  @override
  Widget build(BuildContext context) {
    final available = field.status == DataStatus.available;
    final (icon, styleTint) = jedFieldStyle(field.label);
    final glyphTint = tint ?? styleTint;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final progress = _progress;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Icon(
                  icon,
                  size: 18,
                  color: CupertinoDynamicColor.resolve(glyphTint, context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                      if (field.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            field.note!,
                            style: TextStyle(fontSize: 12, color: secondary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    field.displayValue,
                    textAlign: TextAlign.end,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 14,
                      color: available
                          ? secondary
                          : JedTheme.statusColor(context, field.status),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 10),
              child: Container(
                height: 7,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemFill.resolveFrom(
                    context,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(
                        _barColor(progress),
                        context,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}