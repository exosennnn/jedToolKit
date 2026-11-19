import 'package:flutter/cupertino.dart';
import '../../core/jedui/jedui_dock.dart';

class _Module {
  final String title;
  final String subtitle;
  final IconData icon;
  final int? tabIndex; // null = not built yet
  const _Module(this.title, this.subtitle, this.icon, this.tabIndex);
}

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onOpenModule;

  const HomeScreen({super.key, required this.onOpenModule});

  static const _modules = [
    _Module('Phone Info', 'Device, CPU, memory, display, battery',
        CupertinoIcons.device_phone_portrait, 1),
    _Module('HW Checker', 'Guided hardware tests you confirm yourself',
        CupertinoIcons.wrench, 2),
    _Module('RAM Checker', 'Coming soon', CupertinoIcons.memories, null),
    _Module('Disk Checker', 'Coming soon', CupertinoIcons.folder, null),
    _Module('Benchmark', 'CPU, memory and GPU tests', CupertinoIcons.speedometer, 3),
    _Module('Panic Analyzer', 'Coming soon', CupertinoIcons.doc_text, null),
    _Module('OS Security', 'Coming soon', CupertinoIcons.lock, null),
    _Module('Terminal Lite', 'Coming soon', CupertinoIcons.command, null),
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(largeTitle: Text('jedToolKit')),
          SliverList(
            delegate: SliverChildListDelegate([
              CupertinoListSection.insetGrouped(
                header: const Text('Modules'),
                children: [for (final m in _modules) _tile(context, m)],
              ),
              const SizedBox(height: kDockClearance),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, _Module m) {
    final enabled = m.tabIndex != null;
    return CupertinoListTile(
      leading: Icon(
        m.icon,
        color: enabled
            ? CupertinoColors.activeBlue
            : CupertinoColors.tertiaryLabel.resolveFrom(context),
      ),
      title: Text(
        m.title,
        style: TextStyle(
          color: enabled ? null : CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      subtitle: Text(m.subtitle),
      trailing: enabled ? const CupertinoListTileChevron() : null,
      onTap: enabled ? () => onOpenModule(m.tabIndex!) : null,
    );
  }
}