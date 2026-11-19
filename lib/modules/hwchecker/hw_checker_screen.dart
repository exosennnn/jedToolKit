import 'package:flutter/cupertino.dart';
import '../../core/jedui/jedui_dock.dart';
import 'hw_test.dart';
import 'hw_test_screens.dart';

class HwCheckerScreen extends StatefulWidget {
  const HwCheckerScreen({super.key});

  @override
  State<HwCheckerScreen> createState() => _HwCheckerScreenState();
}

class _HwCheckerScreenState extends State<HwCheckerScreen> {
  final List<HwTest> _tests = buildHwTests();

  Future<void> _open(HwTest test) async {
    final Widget? page = switch (test.id) {
      'display' => const DisplayTestScreen(),
      'touch' => const TouchTestScreen(),
      _ => null,
    };
    if (page == null) return;

    final result = await Navigator.of(context).push<HwTestState>(
      CupertinoPageRoute(builder: (_) => page),
    );
    if (result != null && mounted) {
      setState(() => test.state = result);
    }
  }

  String _stateLabel(HwTest t) {
    if (!t.implemented) return 'Planned';
    return switch (t.state) {
      HwTestState.notTested => 'Not tested',
      HwTestState.passed => 'Passed',
      HwTestState.failed => 'Failed',
    };
  }

  Color _stateColor(BuildContext context, HwTest t) {
    return switch (t.state) {
      HwTestState.passed => CupertinoColors.systemGreen.resolveFrom(context),
      HwTestState.failed => CupertinoColors.systemRed.resolveFrom(context),
      HwTestState.notTested =>
        CupertinoColors.secondaryLabel.resolveFrom(context),
    };
  }

  Widget _row(BuildContext context, HwTest t) {
    return CupertinoListTile(
      title: Text(
        t.title,
        style: TextStyle(
          color: t.implemented
              ? null
              : CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      subtitle: Text(t.description),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _stateLabel(t),
            style: TextStyle(
              color: t.implemented
                  ? _stateColor(context, t)
                  : CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ),
          if (t.implemented) const CupertinoListTileChevron(),
        ],
      ),
      onTap: t.implemented ? () => _open(t) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final guided = _tests.where((t) => t.implemented).toList();
    final planned = _tests.where((t) => !t.implemented).toList();

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(largeTitle: Text('HW Checker')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                'These tests need you to look, touch, and confirm. '
                'Results last until you close the app.',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              CupertinoListSection.insetGrouped(
                header: const Text('Guided tests'),
                children: [for (final t in guided) _row(context, t)],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('Planned'),
                children: [for (final t in planned) _row(context, t)],
              ),
              const SizedBox(height: kDockClearance),
            ]),
          ),
        ],
      ),
    );
  }
}