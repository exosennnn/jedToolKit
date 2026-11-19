import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'benchmark_models.dart';

/// Draws a fixed animated load and times Flutter's raster work per frame.
/// Raster work runs on the GPU through the device's graphics API. This is a
/// measure of this workload, not a raw GPU benchmark.
class GpuBenchmarkScreen extends StatefulWidget {
  const GpuBenchmarkScreen({super.key});

  @override
  State<GpuBenchmarkScreen> createState() => _GpuBenchmarkScreenState();
}

class _GpuBenchmarkScreenState extends State<GpuBenchmarkScreen>
    with SingleTickerProviderStateMixin {
  static const _warmUpFrames = 30;
  static const _measureFrames = 300;
  static const _timeLimit = Duration(seconds: 12);
  static const _budgetMs = 1000 / 60;
  static const _shapeCount = 250;

  late final AnimationController _controller;
  final List<double> _rasterMs = [];
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  int _framesSeen = 0;
  bool _running = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _stopTimers();
    _controller.dispose();
    super.dispose();
  }

  void _stopTimers() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _controller.stop();
    _clock.stop();
  }

  void _start() {
    _rasterMs.clear();
    _framesSeen = 0;
    _clock.reset();
    setState(() => _running = true);
    _controller.repeat();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _timer = Timer(_timeLimit, _finish);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_running) return;
    for (final t in timings) {
      _framesSeen++;
      if (_framesSeen <= _warmUpFrames) continue;
      if (_framesSeen == _warmUpFrames + 1) _clock.start();
      _rasterMs.add(t.rasterDuration.inMicroseconds / 1000.0);
    }
    if (_rasterMs.length >= _measureFrames) _finish();
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _running = false;
    final result = _buildResult();
    _stopTimers();
    Navigator.of(context).pop(result);
  }

  void _cancel() {
    if (_finished) return;
    _finished = true;
    _running = false;
    _stopTimers();
    Navigator.of(context).pop();
  }

  BenchmarkResult _buildResult() {
    final n = _rasterMs.length;
    if (n < 30) {
      return BenchmarkResult.failed(
        BenchmarkKind.gpu,
        'Too few frames were drawn to measure. Keep this screen visible and try again.',
      );
    }

    final sorted = [..._rasterMs]..sort();
    final avg = _rasterMs.reduce((a, b) => a + b) / n;
    final p95 = sorted[((n - 1) * 0.95).round()];
    final over = sorted.where((ms) => ms > _budgetMs).length;
    final timedOut = n < _measureFrames;
    final capacity = 1000 / avg;

    return BenchmarkResult(
      kind: BenchmarkKind.gpu,
      timestamp: DateTime.now(),
      ok: true,
      value: capacity,
      details: {
        'Headline':
            'Frames per second the raster work could sustain. Not capped by the display refresh rate.',
        'Workload': '$_shapeCount blurred circles animated each frame',
        'Frames measured':
            '$n${timedOut ? ' (stopped at ${_timeLimit.inSeconds} s limit)' : ''}',
        'Raster time (avg)': '${avg.toStringAsFixed(1)} ms',
        'Raster time (p95)': '${p95.toStringAsFixed(1)} ms',
        'Frames over 16.7 ms': '$over of $n',
        'Scope':
            'Flutter raster work on the GPU for this workload. Not a raw GPU benchmark, and it varies with the Flutter renderer.',
        'Thermals': 'Long GPU load heats the device. Later runs may be slower.',
        if (kDebugMode)
          'Build': 'Debug build. Results are not representative. Use flutter run --release.',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('GPU Raster'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _cancel,
          child: const Text('Cancel'),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _running
                    ? 'Running. Keep this screen visible.'
                    : 'Draws a fixed animated load for up to ${_timeLimit.inSeconds} seconds. '
                        'Keep the screen on and the phone uncovered.',
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
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) => CustomPaint(
                      painter: _LoadPainter(
                        _running ? _controller.value : 0,
                        _shapeCount,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: _running ? null : _start,
                  child: Text(_running ? 'Running…' : 'Start'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadPainter extends CustomPainter {
  final double t;
  final int count;

  const _LoadPainter(this.t, this.count);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final phase = t * 2 * pi;

    for (var i = 0; i < count; i++) {
      final x = size.width / 2 +
          cos(phase * (1 + i % 5) * 0.5 + i * 0.37) * size.width * 0.42;
      final y = size.height / 2 +
          sin(phase * (1 + i % 7) * 0.3 + i * 0.21) * size.height * 0.42;
      paint.color =
          HSVColor.fromAHSV(0.35, ((i * 23) % 360).toDouble(), 0.8, 1).toColor();
      canvas.drawCircle(Offset(x, y), 18 + (i % 4) * 6.0, paint);
    }
  }

  @override
  bool shouldRepaint(_LoadPainter old) => old.t != t || old.count != count;
}