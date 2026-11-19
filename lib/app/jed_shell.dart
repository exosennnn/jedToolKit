import 'package:flutter/cupertino.dart';
import '../core/jedui/jedui_dock.dart';
import '../modules/benchmark/benchmark_screen.dart';
import '../modules/home/home_screen.dart';
import '../modules/hwchecker/hw_checker_screen.dart';
import '../modules/phoneinfo/phone_info_screen.dart';

class JedShell extends StatefulWidget {
  const JedShell({super.key});

  @override
  State<JedShell> createState() => _JedShellState();
}

class _JedShellState extends State<JedShell> {
  int _index = 0;

  static const _items = [
    JedDockItem(label: 'Home', icon: CupertinoIcons.home),
    JedDockItem(label: 'Phone', icon: CupertinoIcons.device_phone_portrait),
    JedDockItem(label: 'HW Check', icon: CupertinoIcons.wrench),
    JedDockItem(label: 'Benchmark', icon: CupertinoIcons.speedometer),
  ];

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: Stack(
        children: [
          IndexedStack(
            index: _index,
            sizing: StackFit.expand,
            children: [
              HomeScreen(onOpenModule: _select),
              const PhoneInfoScreen(),
              const HwCheckerScreen(),
              const BenchmarkScreen(),
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
                child: JedDock(
                  items: _items,
                  selectedIndex: _index,
                  onSelected: _select,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}