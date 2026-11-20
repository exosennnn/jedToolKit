import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
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

/// Full-screen touch test. The whole display (edge to edge) is covered by a grid
/// of cells; swipe a finger across them to light each one up.
/// Pass unlocks once every cell has been touched.
class TouchTestScreen extends StatefulWidget {
  const TouchTestScreen({super.key});

  @override
  State<TouchTestScreen> createState() => _TouchTestScreenState();
}

class _TouchTestScreenState extends State<TouchTestScreen> {
  static const double _targetCell = 52; // logical px, approximate cell size

  final Map<int, Offset> _last = {}; // last position per finger
  Set<int> _hit = {};
  Size _size = Size.zero;
  int _cols = 1;
  int _rows = 1;
  bool _dialogOpen = false;

  int get _total => _cols * _rows;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _layout(Size size) {
    if (size == _size) return;
    _size = size;
    _cols = (size.width / _targetCell).round().clamp(3, 40);
    _rows = (size.height / _targetCell).round().clamp(3, 80);
    _hit = {};
  }

  void _markAt(Offset p) {
    if (_size.isEmpty) return;
    final c = (p.dx / _size.width * _cols).floor().clamp(0, _cols - 1);
    final r = (p.dy / _size.height * _rows).floor().clamp(0, _rows - 1);
    final i = r * _cols + c;
    if (_hit.add(i)) setState(() {});
  }

  /// Marks every cell along the finger's path so fast swipes skip nothing.
  void _markLine(Offset a, Offset b) {
    final cellW = _size.width / _cols;
    final cellH = _size.height / _rows;
    final step = (cellW < cellH ? cellW : cellH) / 3;
    final dist = (b - a).distance;
    final n = step <= 0 ? 1 : (dist / step).ceil().clamp(1, 400);
    var changed = false;
    for (var k = 0; k <= n; k++) {
      final p = Offset.lerp(a, b, k / n)!;
      final c = (p.dx / _size.width * _cols).floor().clamp(0, _cols - 1);
      final r = (p.dy / _size.height * _rows).floor().clamp(0, _rows - 1);
      if (_hit.add(r * _cols + c)) changed = true;
    }
    if (changed) setState(() {});
  }

  void _checkComplete() {
    if (_hit.length == _total && !_dialogOpen) _showResult(complete: true);
  }

  Future<void> _showResult({required bool complete}) async {
    _dialogOpen = true;
    final action = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(complete ? 'All cells touched' : 'Touch test'),
        content: Text(complete
            ? 'Every part of the screen responded.'
            : '${_hit.length} of $_total cells touched so far.'),
        actions: [
          if (!complete)
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop('continue'),
              child: const Text('Keep testing'),
            ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop('reset'),
            child: const Text('Reset'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop('fail'),
            child: const Text('Fail'),
          ),
          if (complete)
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(ctx).pop('pass'),
              child: const Text('Pass'),
            ),
          if (!complete)
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop('exit'),
              child: const Text('Exit'),
            ),
        ],
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;
    switch (action) {
      case 'pass':
        Navigator.of(context).pop(HwTestState.passed);
      case 'fail':
        Navigator.of(context).pop(HwTestState.failed);
      case 'exit':
        Navigator.of(context).pop();
      case 'reset':
        setState(() => _hit = {});
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_dialogOpen) _showResult(complete: _hit.length == _total);
      },
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.black,
        child: LayoutBuilder(builder: (context, box) {
          _layout(Size(box.maxWidth, box.maxHeight));
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              _last[e.pointer] = e.localPosition;
              _markAt(e.localPosition);
            },
            onPointerMove: (e) {
              final prev = _last[e.pointer] ?? e.localPosition;
              _markLine(prev, e.localPosition);
              _last[e.pointer] = e.localPosition;
            },
            onPointerUp: (e) {
              _last.remove(e.pointer);
              _checkComplete();
            },
            onPointerCancel: (e) => _last.remove(e.pointer),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _TouchGridPainter(
                    cols: _cols,
                    rows: _rows,
                    hit: _hit,
                    base: CupertinoColors.systemGrey.darkColor,
                    lit: CupertinoColors.systemGreen,
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Swipe across the whole screen\n'
                        '${_hit.length} of $_total\n'
                        'Press back to Fail / Reset / Exit',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          color: CupertinoColors.white,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _TouchGridPainter extends CustomPainter {
  _TouchGridPainter({
    required this.cols,
    required this.rows,
    required this.hit,
    required this.base,
    required this.lit,
  });

  final int cols;
  final int rows;
  final Set<int> hit;
  final Color base;
  final Color lit;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / cols;
    final ch = size.height / rows;
    final basePaint = Paint()..color = base.withAlpha(90);
    final litPaint = Paint()..color = lit;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final rect = Rect.fromLTWH(c * cw, r * ch, cw, ch).deflate(0.75);
        canvas.drawRect(rect, hit.contains(r * cols + c) ? litPaint : basePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_TouchGridPainter old) => true;
}
