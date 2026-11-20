import 'package:flutter/cupertino.dart';

import '../core/jedui/jedui_dock.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/tab_modules.dart';
import '../modules/benchmark/benchmark_screen.dart';
import '../modules/diskchecker/disk_checker_screen.dart';
import '../modules/home/home_screen.dart';
import '../modules/hwchecker/hw_checker_screen.dart';
import '../modules/phoneinfo/phone_info_screen.dart';
import '../modules/ramchecker/ram_checker_screen.dart';

class JedShell extends StatefulWidget {
  const JedShell({super.key});

  @override
  State<JedShell> createState() => _JedShellState();
}

class _JedShellState extends State<JedShell> {
  /// Which module is showing. Tracked by id so reordering the dock doesn't
  /// jump to a different tab. The app opens on the default tab chosen in
  /// Settings > Customize Tab Bar.
  late String _selectedId = AppSettings.instance.defaultTabId;

  /// Dock tab -> its page. Home gets the tab-switch callback.
  Widget _page(String id) {
    switch (id) {
      case kHomeModuleId:
        return HomeScreen(onOpenModule: _select);
      case 'phoneinfo':
        return const PhoneInfoScreen();
      case 'hwchecker':
        return const HwCheckerScreen();
      case 'benchmark':
        return const BenchmarkScreen();
      case 'ram':
        return const RamCheckerScreen();
      case 'disk':
        return const DiskCheckerScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  JedDockItem _dockItem(String id) {
    if (id == kHomeModuleId) {
      return const JedDockItem(
        label: 'Home',
        icon: CupertinoIcons.house,
        activeIcon: CupertinoIcons.house_fill,
      );
    }
    final m = tabModuleById(id)!;
    return JedDockItem(label: m.title, icon: m.icon);
  }

  /// [i] is a position in the current dock.
  void _select(int i) {
    final ids = AppSettings.instance.tabIds;
    if (i < 0 || i >= ids.length) return;
    setState(() => _selectedId = ids[i]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final ids = AppSettings.instance.tabIds;
        // If the selected tab was removed, fall back to Home.
        var index = ids.indexOf(_selectedId);
        if (index < 0) index = 0;

        // System back / swipe from any tab other than Home returns to Home;
        // only on Home does it fall through to the OS (leave the app).
        return PopScope(
          canPop: index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _select(0);
          },
          child: CupertinoPageScaffold(
          backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
            context,
          ),
          child: Stack(
            children: [
              IndexedStack(
                index: index,
                sizing: StackFit.expand,
                children: [
                  // Keyed by module id so each tab keeps its state when the
                  // dock is reordered or tabs are added / removed.
                  for (final id in ids)
                    KeyedSubtree(key: ValueKey(id), child: _page(id)),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    // 3 items don't need the full width; keep the dock compact.
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: JedDock(
                          items: [for (final id in ids) _dockItem(id)],
                          selectedIndex: index,
                          onSelected: _select,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
