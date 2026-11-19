import 'package:flutter/cupertino.dart';
import 'hw_test.dart';

/// Full-screen color cycle. Tap anywhere to advance, then choose Pass or Fail.
class DisplayTestScreen extends StatefulWidget {
  const DisplayTestScreen({super.key});

  @override
  State<DisplayTestScreen> createState() => _DisplayTestScreenState();
}

class _DisplayTestScreenState extends State<DisplayTestScreen> {
  static const _steps = <(String, Color)>[
    ('White', CupertinoColors.white),
    ('Black', CupertinoColors.black),
    ('Red', CupertinoColors.systemRed),
    ('Green', CupertinoColors.systemGreen),
    ('Blue', CupertinoColors.systemBlue),
  ];
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final (name, color) = _steps[_step];
    final fg = color.computeLuminance() < 0.5
        ? CupertinoColors.white
        : CupertinoColors.black;

    return CupertinoPageScaffold(
      backgroundColor: color,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _step = (_step + 1) % _steps.length),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: fg)),
                    ),
                    const Spacer(),
                    Text(
                      name,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Tap anywhere to change color. Look for dead or stuck pixels, tint, and burn-in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg, fontSize: 15),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton.filled(
                        onPressed: () =>
                            Navigator.of(context).pop(HwTestState.failed),
                        child: const Text('Fail'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton.filled(
                        onPressed: () =>
                            Navigator.of(context).pop(HwTestState.passed),
                        child: const Text('Pass'),
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
}

/// Grid of 24 cells. Each cell lights up on its first touch.
/// Pass only unlocks once every cell has responded.
class TouchTestScreen extends StatefulWidget {
  const TouchTestScreen({super.key});

  @override
  State<TouchTestScreen> createState() => _TouchTestScreenState();
}

class _TouchTestScreenState extends State<TouchTestScreen> {
  static const _columns = 4;
  static const _total = 24;
  final Set<int> _hit = {};

  void _mark(int i) {
    if (!_hit.contains(i)) setState(() => _hit.add(i));
  }

  @override
  Widget build(BuildContext context) {
    final complete = _hit.length == _total;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Touchscreen'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Tap every cell. Each should light up on its first touch. '
                '${_hit.length} of $_total',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: _columns,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: List.generate(_total, (i) {
                    final touched = _hit.contains(i);
                    return Listener(
                      onPointerDown: (_) => _mark(i),
                      child: Container(
                        decoration: BoxDecoration(
                          color: touched
                              ? CupertinoColors.systemGreen
                              : CupertinoColors.tertiarySystemFill.resolveFrom(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      onPressed: () => setState(() => _hit.clear()),
                      child: const Text('Reset'),
                    ),
                  ),
                  Expanded(
                    child: CupertinoButton(
                      onPressed: () =>
                          Navigator.of(context).pop(HwTestState.failed),
                      child: const Text('Fail'),
                    ),
                  ),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: complete
                          ? () => Navigator.of(context).pop(HwTestState.passed)
                          : null,
                      child: const Text('Pass'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}