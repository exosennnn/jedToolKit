import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/jedui/jedui_components.dart';
import '../../core/jedui/jedui_dock.dart';
import '../../core/settings/app_settings.dart';
import '../benchmark/benchmark_screen.dart';
import '../diskchecker/disk_checker_screen.dart';
import '../hwchecker/hw_checker_screen.dart';
import '../phoneinfo/phone_info_screen.dart';
import '../ramchecker/ram_checker_screen.dart';
import '../settings/settings_screen.dart';
import '../../core/jedui/jedui_route.dart';

Widget _buildPhoneInfo(BuildContext _) => const PhoneInfoScreen();
Widget _buildHwChecker(BuildContext _) => const HwCheckerScreen();
Widget _buildRamChecker(BuildContext _) => const RamCheckerScreen();
Widget _buildDiskChecker(BuildContext _) => const DiskCheckerScreen();
Widget _buildBenchmark(BuildContext _) => const BenchmarkScreen();

class _Module {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int? tabIndex; // switches dock tab when non-null
  final WidgetBuilder?
  screenBuilder; // pushes a standalone screen when non-null
  final bool general; // true = "Others" section

  const _Module(
    this.id,
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.tabIndex, {
    this.screenBuilder,
    this.general = false,
  });

  bool get enabled => screenBuilder != null;
}

class HomeScreen extends StatefulWidget {
  final ValueChanged<int> onOpenModule;
  final VoidCallback? onSettingsTapped;
  final VoidCallback? onUpdateTapped;

  const HomeScreen({
    super.key,
    required this.onOpenModule,
    this.onSettingsTapped,
    this.onUpdateTapped,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _prefsKey = 'pinned_modules_v1';
  static const _categories = ['All', 'jedModules', 'Others'];

  // iOS: AccentColorManager. Driven by Settings > Accent Color.
  CupertinoDynamicColor get _accent => AppSettings.instance.accent;

  // iOS ToolKitViewModel hides modules that live in the tab bar from the lists
  // (unless pinned). Set to false to list the dock modules again.
  static const bool _hideDockModulesFromLists = true;

  static const _modules = [
    _Module(
      'phoneinfo',
      'jedPhoneInfo',
      'Device, CPU, memory, display, battery',
      CupertinoIcons.device_phone_portrait,
      CupertinoColors.systemBlue,
      null,
      screenBuilder: _buildPhoneInfo,
    ),
    _Module(
      'hwchecker',
      'jedHWChecker',
      'Guided hardware tests you confirm yourself',
      CupertinoIcons.wrench_fill,
      CupertinoColors.systemOrange,
      null,
      screenBuilder: _buildHwChecker,
    ),
    _Module(
      'benchmark',
      'jedBenchmark 2',
      'CPU, memory and GPU tests',
      CupertinoIcons.speedometer,
      CupertinoColors.systemPurple,
      null,
      screenBuilder: _buildBenchmark,
    ),
    _Module(
      'ram',
      'jedRAMChecker',
      'Live footprint, pressure & device memory',
      CupertinoIcons.memories,
      CupertinoColors.systemIndigo,
      null,
      screenBuilder: _buildRamChecker,
    ),
    _Module(
      'disk',
      'jedDiskChecker',
      'Sequential read & write speed test',
      CupertinoIcons.folder_fill,
      CupertinoColors.systemGreen,
      null,
      screenBuilder: _buildDiskChecker,
    ),
    _Module(
      'panic',
      'Panic Analyzer',
      'Coming soon',
      CupertinoIcons.doc_text_fill,
      CupertinoColors.systemRed,
      null,
    ),
    _Module(
      'security',
      'OS Security',
      'Coming soon',
      CupertinoIcons.lock_fill,
      CupertinoColors.systemTeal,
      null,
    ),
    _Module(
      'terminal',
      'Terminal Lite',
      'Coming soon',
      CupertinoIcons.command,
      CupertinoColors.systemBlue,
      null,
      general: true,
    ),
  ];

  final _searchController = TextEditingController();
  Set<String> _pinned = {};
  String _category = 'All';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadPinned();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_prefsKey) ?? const <String>[];
    if (mounted) setState(() => _pinned = ids.toSet());
  }

  Future<void> _togglePin(String id) async {
    setState(() {
      if (!_pinned.remove(id)) _pinned.add(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _pinned.toList());
  }

  void _showPinMenu(_Module m) {
    if (!m.enabled) return;
    final pinned = _pinned.contains(m.id);
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(m.title),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: pinned,
            onPressed: () {
              Navigator.pop(ctx);
              _togglePin(m.id);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  pinned
                      ? CupertinoIcons.pin_slash_fill
                      : CupertinoIcons.pin_fill,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(pinned ? 'Unpin from Pinned' : 'Pin to Pinned'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _notBuilt(String what) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(what),
        content: const Text(
          'This screen is not built in the Android version yet.',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _open(_Module m) {
    // Modules in the dock switch tabs; everything else opens as a screen.
    final dockIndex = AppSettings.instance.tabIds.indexOf(m.id);
    if (dockIndex > 0) {
      widget.onOpenModule(dockIndex);
    } else if (m.screenBuilder != null) {
      Navigator.of(context)
          .push(JedPageRoute<void>(builder: m.screenBuilder!));
    }
  }

  String get _dateText {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final n = DateTime.now();
    return '${days[n.weekday - 1]}, ${months[n.month - 1]} ${n.day}'
        .toUpperCase();
  }

  static int _byTitle(_Module a, _Module b) => a.title.compareTo(b.title);

  Color _tint(BuildContext context, int index) {
    return CupertinoDynamicColor.resolve(
      AppSettings.instance.tintFor(index),
      context,
    );
  }

  // ToolKitViewModel.favoriteTools
  List<_Module> get _pinnedModules =>
      _modules.where((m) => m.enabled && _pinned.contains(m.id)).toList()
        ..sort(_byTitle);

  // allAvailableModules minus favorites minus tab-bar modules
  List<_Module> get _unpinned => _modules
      .where(
        (m) =>
            !(m.enabled && _pinned.contains(m.id)) &&
            !(_hideDockModulesFromLists &&
                AppSettings.instance.tabIds.contains(m.id)),
      )
      .toList();

  // ToolKitViewModel.searchResults: jedTools + generalTools + favoriteTools
  List<_Module> get _searchResults {
    final q = _query.toLowerCase();
    return [..._unpinned, ..._pinnedModules]
        .where(
          (m) =>
              m.title.toLowerCase().contains(q) ||
              m.subtitle.toLowerCase().contains(q),
        )
        .toList()
      ..sort(_byTitle);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when accent, multicolor or the dock tabs change.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final searching = _query.isNotEmpty;
    final pinned = _pinnedModules;
    final jed = _unpinned.where((m) => !m.general).toList()..sort(_byTitle);
    final general = _unpinned.where((m) => m.general).toList()
      ..sort(_byTitle);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 20, bottom: kDockClearance),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _searchBar(context),
                    const SizedBox(height: 32),
                    if (searching)
                      _searchSection(context)
                    else ...[
                      _pills(context),
                      const SizedBox(height: 32),
                      if (_category == 'All' && pinned.isNotEmpty) ...[
                        _featured(context, pinned),
                        const SizedBox(height: 32),
                      ],
                      if ((_category == 'All' || _category == 'jedModules') &&
                          jed.isNotEmpty) ...[
                        _section(context, 'jedModules', jed),
                        const SizedBox(height: 36),
                      ],
                      if ((_category == 'All' || _category == 'Others') &&
                          general.isNotEmpty)
                        _section(context, 'General Tools', general),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: Header

  Widget _header(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'jedToolKit',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          _circleButton(
            context,
            CupertinoIcons.cube_box,
            CupertinoDynamicColor.resolve(_accent, context),
            widget.onUpdateTapped ?? () => _notBuilt('Updates'),
          ),
          const SizedBox(width: 14),
          _circleButton(
            context,
            CupertinoIcons.gear,
            secondary,
            widget.onSettingsTapped ??
                () => Navigator.of(context).push(
                  JedPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(
    BuildContext context,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return JedPressable(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          shape: BoxShape.circle,
          border: Border.all(
            color: CupertinoColors.label
                .resolveFrom(context)
                .withValues(alpha: 0.04),
          ),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  // MARK: Search + pills

  Widget _searchBar(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CupertinoColors.label
                .resolveFrom(context)
                .withValues(alpha: 0.04),
          ),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.search, size: 17, color: secondary),
            const SizedBox(width: 12),
            Expanded(
              child: CupertinoTextField(
                controller: _searchController,
                placeholder: 'Search',
                padding: EdgeInsets.zero,
                decoration: null,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                child: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: 18,
                  color: secondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pills(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          for (final c in _categories)
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
                        ? CupertinoDynamicColor.resolve(_accent, context)
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
                    c,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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

  // MARK: Pinned carousel

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
  );

  Widget _featured(BuildContext context, List<_Module> modules) {
    final sorted = [...modules]..sort(_byTitle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Pinned Modules'),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          // SwiftUI HStack: cards keep their natural height, centered,
          // with spacing only *between* cards.
          child: Row(
            children: [
              for (var i = 0; i < sorted.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == sorted.length - 1 ? 0 : 16,
                  ),
                  child: _featuredCard(context, sorted[i], i),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _featuredCard(BuildContext context, _Module m, int index) {
    final color = _tint(context, index);
    final fg = jedOnColor(color); // readable on the accent (Monochrome-safe)

    return GestureDetector(
      onLongPress: () => _showPinMenu(m),
      child: JedPressable(
        onTap: () => _open(m),
        child: Container(
          width: 210,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: CupertinoColors.label
                  .resolveFrom(context)
                  .withValues(alpha: 0.04),
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 100,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color.withValues(alpha: 0.8), color],
                          ),
                        ),
                      ),
                    ),
                    // iOS: .position(x: width * 0.85, y: height * 0.5), 70pt glyph
                    Positioned(
                      left: 210 * 0.85 - 35,
                      top: 50 - 35,
                      child: Icon(
                        m.icon,
                        size: 70,
                        color: fg.withValues(alpha: 0.12),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: fg.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          m.icon,
                          size: 20,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: Row sections

  Widget _searchSection(BuildContext context) {
    final results = _searchResults;
    if (results.isEmpty) {
      final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Column(
            children: [
              Icon(CupertinoIcons.search, size: 48, color: secondary),
              const SizedBox(height: 12),
              const Text(
                'No Results',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Check the spelling or try a new search.',
                style: TextStyle(fontSize: 15, color: secondary),
              ),
            ],
          ),
        ),
      );
    }
    return _section(context, 'Search Results', results);
  }

  Widget _section(BuildContext context, String title, List<_Module> modules) {
    final sep = CupertinoColors.separator.resolveFrom(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
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
                for (var i = 0; i < modules.length; i++) ...[
                  _row(context, modules[i], i),
                  if (i != modules.length - 1)
                    Container(
                      height: 0.5,
                      margin: const EdgeInsets.only(left: 80),
                      color: sep,
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, _Module m, int index) {
    final color = m.enabled
        ? _tint(context, index)
        : CupertinoDynamicColor.resolve(CupertinoColors.systemGrey, context);

    return _PressRow(
      onTap: m.enabled ? () => _open(m) : null,
      onLongPress: m.enabled ? () => _showPinMenu(m) : null,
      child: Opacity(
        opacity: m.enabled ? 1 : 0.6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(m.icon, size: 22, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!m.enabled)
                const JedPill(label: 'Soon', color: CupertinoColors.systemGrey)
              else
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 14,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width row with an iOS-style gray highlight while pressed.
class _PressRow extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _PressRow({required this.child, this.onTap, this.onLongPress});

  @override
  State<_PressRow> createState() => _PressRowState();
}

class _PressRowState extends State<_PressRow> {
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
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: _down
            ? CupertinoColors.systemGrey5.resolveFrom(context)
            : const Color(0x00000000),
        child: widget.child,
      ),
    );
  }
}