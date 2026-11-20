import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/jedui/jedui_components.dart';
import '../../core/jedui/jedui_dock.dart';
import '../../core/jedui/jedui_theme.dart';
import '../../core/settings/app_settings.dart';
import 'phone_info.dart';
import 'phone_info_service.dart';

/// Mirrors the iOS jedPhoneInfo screen (PhoneInfoView.swift):
/// titled sections, each a rounded card of icon / title / value rows, with
/// progress bars on level and usage rows. The category pills (Device / CPU /
/// GPU / System / Battery / Thermal / Sensors) filter which sections show.
/// Copy button in the nav bar copies every section.
class PhoneInfoScreen extends StatefulWidget {
  const PhoneInfoScreen({super.key});

  @override
  State<PhoneInfoScreen> createState() => _PhoneInfoScreenState();
}

class _PhoneInfoScreenState extends State<PhoneInfoScreen> {
  // iOS: AccentColorManager. Icons use the accent chosen in Settings > Accent
  // Color (or a rainbow in multicolor mode, advancing one color per row across
  // all sections).

  /// Plain-language explanation shown under each category.
  static const _footnotes = <InfoCategory, String>{
    InfoCategory.cpu:
        'The processor that runs your phone. The name is matched from the chip code Android reports.',
    InfoCategory.gpu:
        'The graphics chip that draws games, video and animations. The name comes from the graphics driver.',
    InfoCategory.system:
        'Android version, build details, screen, cameras and built-in features.',
    InfoCategory.battery: 'Live readings from the battery controller.',
    InfoCategory.thermal:
        'How warm the phone is running. Many phones hide detailed temperature sensors from apps.',
    InfoCategory.sensors:
        'Sensors let your phone sense motion, light and position.',
  };

  final _service = PhoneInfoService();
  List<InfoSection>? _sections;
  InfoCategory _category = InfoCategory.device;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sections = await _service.load();
    if (mounted) setState(() => _sections = sections);
  }

  // MARK: Data helpers

  Color _tint(BuildContext context, int index) {
    return CupertinoDynamicColor.resolve(
      AppSettings.instance.tintFor(index),
      context,
    );
  }

  /// "7.4 GB" / "512 MB" -> bytes (no unit = GB).
  double? _bytes(String? v) {
    if (v == null) return null;
    final m = RegExp(
      r'(\d+(?:\.\d+)?)\s*([kmgt])?i?b?',
      caseSensitive: false,
    ).firstMatch(v);
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!);
    if (n == null) return null;
    const pow = {'k': 1e3, 'm': 1e6, 'g': 1e9, 't': 1e12};
    return n * (pow[(m.group(2) ?? 'g').toLowerCase()] ?? 1e9);
  }

  List<InfoSection> _sectionsFor(List<InfoSection> all, InfoCategory c) =>
      all.where((s) => s.category == c).toList();

  /// Available value of the first field whose label matches [label] exactly.
  String? _find(List<InfoSection> all, InfoCategory c, String label) {
    for (final s in _sectionsFor(all, c)) {
      for (final f in s.fields) {
        if (f.status == DataStatus.available &&
            f.value != null &&
            f.label == label) {
          return f.value;
        }
      }
    }
    return null;
  }

  // MARK: Copy (generateClipboardText)

  String _clipboardText(List<InfoSection> sections) {
    return sections
        .map((s) {
          final rows = s.fields
              .map((f) => '  ${f.label}: ${f.displayValue}')
              .join('\n');
          return '${s.title}:\n$rows';
        })
        .join('\n\n');
  }

  Future<void> _copy(List<InfoSection> sections) async {
    if (sections.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _clipboardText(sections)));
    HapticFeedback.mediumImpact();
    if (!mounted) return;

    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (ctx.mounted) Navigator.of(ctx).pop();
        });
        return const CupertinoAlertDialog(title: Text('Copied to Clipboard'));
      },
    );
  }

  // MARK: Build

  @override
  Widget build(BuildContext context) {
    // Rebuild when the accent color or multicolor mode changes.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final all = _sections;
    final sections = all == null
        ? const <InfoSection>[]
        : _sectionsFor(all, _category);

    // Running row index across sections, like iOS' multicolor colorIndex.
    final starts = <int>[];
    var running = 0;
    for (final s in sections) {
      starts.add(running);
      running += s.fields.length;
    }

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            // jedPhoneInfoViewController: large title 22 bold
            largeTitle: const Text(
              'jedPhoneInfo',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            // doc.on.doc
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: all == null || all.isEmpty ? null : () => _copy(all),
              child: const Icon(CupertinoIcons.doc_on_doc, size: 22),
            ),
          ),
          CupertinoSliverRefreshControl(onRefresh: _load),
          SliverToBoxAdapter(child: _pills(context)),
          if (all == null)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (_category == InfoCategory.device)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + kDockClearance,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(_deviceGlance(context, all)),
              ),
            )
          else if (sections.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _empty(context))
          else
            // VStack(spacing: 32) .padding(.horizontal, 24) .padding(.vertical, 24)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + kDockClearance,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  for (var i = 0; i < sections.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == sections.length - 1 ? 0 : 32,
                      ),
                      child: _PhoneInfoSection(
                        section: sections[i],
                        tintFor: (row) => _tint(context, starts[i] + row),
                      ),
                    ),
                  if (_footnotes[_category] != null) ...[
                    const SizedBox(height: 16),
                    _footnote(context, _footnotes[_category]!),
                  ],
                ]),
              ),
            ),
        ],
      ),
    );
  }

  // MARK: Category pills

  Widget _pills(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          for (final c in InfoCategory.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _category = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _category == c
                        ? CupertinoDynamicColor.resolve(
                            AppSettings.instance.accent,
                            context,
                          )
                        : CupertinoColors.secondarySystemGroupedBackground
                              .resolveFrom(context),
                    borderRadius: BorderRadius.circular(100), // Capsule
                    border: Border.all(
                      color: _category == c
                          ? const Color(0x00000000)
                          : CupertinoColors.label
                                .resolveFrom(context)
                                .withValues(alpha: 0.04),
                    ),
                  ),
                  child: Text(
                    c.title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: _category == c
                          ? AppSettings.instance.contrastingForeground(context)
                          : CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // MARK: Device quick glance

  List<Widget> _deviceGlance(BuildContext context, List<InfoSection> all) {
    final name = _find(all, InfoCategory.device, 'Model name');
    final number = _find(all, InfoCategory.device, 'Model number');
    final maker = _find(all, InfoCategory.device, 'Manufacturer');

    final totalMem = _find(all, InfoCategory.device, 'Total memory');
    final availMem = _find(all, InfoCategory.device, 'Available memory');
    final totalSto = _find(all, InfoCategory.device, 'Total storage');
    final availSto = _find(all, InfoCategory.device, 'Available storage');

    // Collector failed entirely: show its error rows instead of a blank screen.
    if (name == null && totalMem == null && totalSto == null) {
      final failed = _sectionsFor(all, InfoCategory.device);
      return [
        for (final s in failed)
          _PhoneInfoSection(section: s, tintFor: (r) => _tint(context, r)),
      ];
    }

    return [
      JedCard(
        child: Row(
          children: [
            JedIconBadge(
              icon: CupertinoIcons.device_phone_portrait,
              color: AppSettings.instance.tintFor(0),
              size: 56,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _caption(context, 'MODEL NAME'),
                  const SizedBox(height: 2),
                  Text(
                    name ?? number ?? 'Unknown',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (maker != null) ...[
                    const SizedBox(height: 8),
                    _caption(context, 'MANUFACTURER'),
                    const SizedBox(height: 2),
                    Text(
                      maker,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (number != null && number != name) ...[
                    const SizedBox(height: 4),
                    Text(
                      number,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (totalMem != null)
        _usageCard(
          context,
          icon: CupertinoIcons.memories,
          color: AppSettings.instance.tintFor(1),
          title: 'Memory',
          total: totalMem,
          available: availMem,
        ),
      if (totalMem != null) const SizedBox(height: 16),
      if (totalSto != null)
        _usageCard(
          context,
          icon: CupertinoIcons.folder_fill,
          color: AppSettings.instance.tintFor(2),
          title: 'Storage',
          total: totalSto,
          available: availSto,
        ),
    ];
  }

  Widget _caption(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    ),
  );

  /// Total and available figures with a used-space bar.
  Widget _usageCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String total,
    required String? available,
  }) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final t = _bytes(total);
    final a = _bytes(available);
    final usedFraction = (t != null && a != null && t > 0)
        ? ((t - a) / t).clamp(0.0, 1.0).toDouble()
        : null;
    final barColor = CupertinoDynamicColor.resolve(color, context);

    Widget stat(String label, String? value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value ?? '—',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 13, color: secondary)),
        ],
      ),
    );

    return JedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              JedIconBadge(icon: icon, color: color, size: 32),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [stat('Total', total), stat('Available', available)]),
          if (usedFraction != null) ...[
            const SizedBox(height: 14),
            Container(
              height: 7,
              width: double.infinity,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                widthFactor: usedFraction,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(usedFraction * 100).round()}% in use',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
        ],
      ),
    );
  }

  // MARK: Misc widgets

  Widget _footnote(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, kDockClearance),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.info_circle, size: 40, color: secondary),
          const SizedBox(height: 12),
          Text(
            'No ${_category.title} Data',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'The device info collector did not return this section.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: secondary),
          ),
        ],
      ),
    );
  }
}


// MARK: - Section card

class _PhoneInfoSection extends StatelessWidget {
  final InfoSection section;
  final Color Function(int row) tintFor;

  const _PhoneInfoSection({required this.section, required this.tintFor});

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
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: CupertinoColors.label
                  .resolveFrom(context)
                  .withValues(alpha: 0.04),
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                _PhoneInfoRow(field: fields[i], tint: tintFor(i)),
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

// MARK: - Row (TextRow / ProgressBarRow)

class _PhoneInfoRow extends StatelessWidget {
  final InfoField field;
  final Color tint;

  const _PhoneInfoRow({required this.field, required this.tint});

  /// Percent values on level/usage rows get a progress bar.
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
                : AppSettings.instance.accent);
    }
    return p < 0.2
        ? CupertinoColors.systemRed
        : (p < 0.5
              ? CupertinoColors.systemYellow
              : AppSettings.instance.accent);
  }

  @override
  Widget build(BuildContext context) {
    final available = field.status == DataStatus.available;
    final (icon, _) = jedFieldStyle(field.label);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final progress = _progress;

    final iconBox = SizedBox(
      width: 28,
      height: 28,
      child: Icon(icon, size: 17, color: tint),
    );

    final titleColumn = Column(
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
    );

    final valueColor = available
        ? secondary
        : JedTheme.statusColor(context, field.status);

    // ProgressBarRow: header, then a full-width capsule bar 10pt below.
    if (progress != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                iconBox,
                const SizedBox(width: 16),
                Expanded(child: titleColumn),
                const SizedBox(width: 12),
                Text(
                  field.displayValue,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: Container(
                height: 4.8, // ProgressView 4pt scaled 1.2 on y
                width: double.infinity,
                alignment: Alignment.centerLeft,
                color: CupertinoColors.systemGrey5.resolveFrom(context),
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    color: CupertinoDynamicColor.resolve(
                      _barColor(progress),
                      context,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // TextRow: icon, title, spacer, trailing-aligned value (wraps if long).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          iconBox,
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(flex: 4, child: titleColumn),
                Flexible(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      field.displayValue,
                      textAlign: TextAlign.end,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: valueColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}