import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'benchmark_config.dart';
import 'benchmark_models.dart';
import 'benchmark_workloads.dart';
import 'gpu_compute.dart';
import 's20_baseline.dart';
import 'thermal_monitor.dart';

/// Android replacement for MetalBenchmark.swift.
/// Metal compute shaders and Vision don't exist here, so this runs the same
/// idea through Flutter's renderer: a list of scenes (blur, filter, particles,
/// overdraw) is drawn one after another, the raster time per frame is measured
/// for each, and each scene is scored against a baseline time:
///   score = min(8, baselineMs / medianRasterMs) x 2500
/// then combined with a weighted geometric mean, like the Swift version.
class GpuBenchmarkScreen extends StatefulWidget {
  const GpuBenchmarkScreen({super.key});

  @override
  State<GpuBenchmarkScreen> createState() => _GpuBenchmarkScreenState();
}

enum _Scene { blur, filter, particles, overdraw }

class _Phase {
  final String name;
  final _Scene scene;
  final double weight; // same weights as the Metal task list
  const _Phase(this.name, this.scene, this.weight);
}

const _phases = <_Phase>[
  _Phase('Gaussian Blur', _Scene.blur, 1.0),
  _Phase('Edge Filter', _Scene.filter, 0.8),
  _Phase('Particle Physics', _Scene.particles, 2.0),
  _Phase('Overdraw Blend', _Scene.overdraw, 1.5),
  _Phase('Particle Physics (2)', _Scene.particles, 2.0),
  _Phase('Gaussian Blur (2)', _Scene.blur, 1.0),
  _Phase('Overdraw Blend (2)', _Scene.overdraw, 1.5),
];

// Baseline raster ms per scene, measured on the Galaxy S20 (see s20_baseline.dart).
double _baselineMs(_Scene s) => switch (s) {
  _Scene.blur => kS20BlurMs,
  _Scene.filter => kS20FilterMs,
  _Scene.particles => kS20ParticlesMs,
  _Scene.overdraw => kS20OverdrawMs,
};

/// Compute kernels: value (GFLOPS or GB/s) against the S20 baseline.
/// Highest ratio vs the S20 that still counts. Real phones are rarely beyond ~4x,
/// so a bigger number usually means the measurement is off, not that the GPU is
/// that fast.
const _maxRatio = 8.0;

/// Raster times below this are timer noise (or an async renderer that only
/// reports CPU encode time), so they are not allowed to inflate the score.
const _minRasterMs = 1.5;

double _computeScore(double value, double baseline) =>
    value <= 0 ? 0 : min(_maxRatio, value / max(baseline, 1e-6)) * kGpuAnchor;

const _blurShapes = [60, 100, 150];
const _overdrawShapes = [120, 250, 400];
const _particleCounts = [40000, 100000, 250000];

class _PhaseResult {
  final _Phase phase;
  final double medMs, p95Ms, baselineMs, score;
  final int frames;
  const _PhaseResult(
    this.phase,
    this.medMs,
    this.p95Ms,
    this.baselineMs,
    this.score,
    this.frames,
  );
}

class _GpuBenchmarkScreenState extends State<GpuBenchmarkScreen>
    with SingleTickerProviderStateMixin {
  // Warm-up is time based: the engine reports frame timings in batches about
  // a second late, so counting frames would mix in the previous scene.
  static const _warmUp = Duration(milliseconds: 600);
  static const _fallbackWarmUpFrames =
      60; // only if timestamps use another clock
  static const _measureFrames = 240; // about 4 s per scene at 60 fps
  static const _minFrames = 8;
  static const _phaseTimeLimit = Duration(seconds: 25);
  static const _slowFrameMs = 400.0;
  static const _slowFramesToAbort = 5; // in a row, after warm-up

  late final AnimationController _controller;
  final int _tier = deviceTier();
  final List<double> _rasterMs = [];
  final List<_PhaseResult> _done = [];
  Timer? _phaseTimer;
  Float32List? _points;
  int _phase = 0;
  int _framesSeen = 0;
  int _phaseStartUs = 0;
  int _slowStreak = 0;
  bool _running = false;
  bool _finished = false;
  String? _computeStage;
  String? _rasterNote;
  ThermalReading? _tempStart;
  ThermalReading? _tempNow;
  final List<ComputeResult> _compute = [];

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
    _phaseTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _controller.stop();
  }

  Future<void> _start() async {
    _done.clear();
    _compute.clear();
    _tempStart = await ThermalMonitor.read();
    _tempNow = _tempStart;
    setState(() {
      _running = true;
      _computeStage = 'OpenGL ES compute';
    });
    final gl = await GpuCompute.gles(seconds: kGpuComputeSeconds);
    if (!mounted || _finished) return;
    setState(() => _computeStage = 'OpenCL compute');
    final cl = await GpuCompute.openCl(seconds: kGpuComputeSeconds);
    if (!mounted || _finished) return;
    _compute.addAll([gl, cl]);
    setState(() => _computeStage = null);
    _beginPhase(0);
    _controller.repeat();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  void _beginPhase(int i) {
    // Safety: stop the scenes if the phone is already too hot.
    final reading = _tempNow;
    final hot = reading == null ? null : ThermalMonitor.unsafeReason(reading);
    ThermalMonitor.read().then((r) => _tempNow = r);
    if (hot != null) {
      _rasterFailed('Stopped to protect the phone: $hot');
      return;
    }
    _phaseTimer?.cancel();
    _rasterMs.clear();
    _framesSeen = 0;
    _slowStreak = 0;
    _phaseStartUs = Timeline.now;
    if (_phases[i].scene == _Scene.particles) {
      final rng = Random(42);
      final n = _particleCounts[_tier];
      final pts = Float32List(n * 2);
      for (var k = 0; k < pts.length; k++) {
        pts[k] = (rng.nextDouble() - 0.5) * 1.4;
      }
      _points = pts;
    }
    setState(() => _phase = i);
    _phaseTimer = Timer(_phaseTimeLimit, _endPhase);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_running || _finished) return;
    final nowUs = Timeline.now;
    for (final t in timings) {
      final startUs = t.timestampInMicroseconds(ui.FramePhase.buildStart);
      final sameClock = (nowUs - startUs).abs() < 60 * 1000000;
      if (sameClock) {
        // Frames of the previous scene and the first frames of this one
        // (shader compile, layer allocation) are not measured.
        if (startUs < _phaseStartUs + _warmUp.inMicroseconds) continue;
      } else if (++_framesSeen <= _fallbackWarmUpFrames) {
        continue;
      }

      final ms = t.rasterDuration.inMicroseconds / 1000.0;

      // Safety: several very slow frames in a row means the GPU can't cope.
      // One spike alone (a GC, a layer rebuild) must not fail the whole run.
      if (ms > _slowFrameMs) {
        if (++_slowStreak >= _slowFramesToAbort) {
          _rasterFailed(
            'This GPU is too slow for the raster scenes ($_slowFramesToAbort frames in a row took over ${_slowFrameMs.round()} ms in "${_phases[_phase].name}"). Test stopped.',
          );
          return;
        }
      } else {
        _slowStreak = 0;
      }

      _rasterMs.add(ms);
      if (_rasterMs.length >= _measureFrames) {
        _endPhase();
        return;
      }
    }
  }

  void _endPhase() {
    if (_finished || !mounted) return;
    _phaseTimer?.cancel();
    final p = _phases[_phase];
    final n = _rasterMs.length;

    if (n < _minFrames) {
      _rasterFailed(
        'Only $n frames could be measured during "${p.name}" (need $_minFrames). Keep this screen visible and in release mode, then try again.',
      );
      return;
    }

    // Median, not mean: one GC pause or compositor hiccup should not move the score.
    final sorted = [..._rasterMs]..sort();
    final med = sorted[n ~/ 2];
    final p95 = sorted[((n - 1) * 0.95).round()];
    final base = _baselineMs(p.scene);
    final ratio = min(_maxRatio, base / max(med, _minRasterMs));
    _done.add(_PhaseResult(p, med, p95, base, ratio * kGpuAnchor, n));

    if (_phase + 1 >= _phases.length) {
      _finishWith(_buildResult());
    } else {
      _beginPhase(_phase + 1);
    }
  }

  /// A raster failure only fails the test when raster counts toward the score
  /// (or when compute didn't work either). Otherwise the compute result stands.
  void _rasterFailed(String msg) {
    if (!kRasterInScore && _compute.any((c) => c.ok)) {
      _rasterNote = msg;
      _finishWith(_buildResult());
    } else {
      _finishWith(BenchmarkResult.failed(BenchmarkKind.gpu, msg));
    }
  }

  void _finishWith(BenchmarkResult result) {
    if (_finished) return;
    _finished = true;
    _running = false;
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

  String _gpuSnippet() {
    String ms(_Scene s) {
      final xs = [
        for (final r in _done)
          if (r.phase.scene == s) r.medMs,
      ];
      return xs.isEmpty
          ? '0'
          : (xs.reduce((a, b) => a + b) / xs.length).toStringAsFixed(2);
    }

    String cv(String api, bool alu) {
      for (final c in _compute) {
        if (c.api == api && c.ok) {
          return (alu ? c.gflops : c.gbps).toStringAsFixed(1);
        }
      }
      return '0';
    }

    return 'const kS20BlurMs = ${ms(_Scene.blur)}; const kS20FilterMs = ${ms(_Scene.filter)}; '
        'const kS20ParticlesMs = ${ms(_Scene.particles)}; const kS20OverdrawMs = ${ms(_Scene.overdraw)}; '
        'const kS20GlesGflops = ${cv('GLES', true)}; const kS20GlesGBps = ${cv('GLES', false)}; '
        'const kS20ClGflops = ${cv('OpenCL', true)}; const kS20ClGBps = ${cv('OpenCL', false)};';
  }

  BenchmarkResult _buildResult() {
    final computeLines = <String, String>{};
    final apiScores = <String, double>{};
    for (final c in _compute) {
      if (!c.ok) {
        computeLines[c.api] = 'Unavailable: ${c.error}';
        continue;
      }
      final gles = c.api == 'GLES';
      final aluScore = _computeScore(
        c.gflops,
        gles ? kS20GlesGflops : kS20ClGflops,
      );
      final bwScore = _computeScore(c.gbps, gles ? kS20GlesGBps : kS20ClGBps);
      // One score per API, a geometric mean of its workloads.
      apiScores[c.api] = weightedGeoMean([
        (aluScore, kComputeAluWeight),
        (bwScore, kComputeBandwidthWeight),
      ]);
      computeLines['${c.api} device'] = c.device;
      computeLines['${c.api} compute (FMA)'] =
          '${c.gflops.toStringAsFixed(0)} GFLOPS · ${aluScore.round()} pts';
      computeLines['${c.api} memory (copy)'] =
          '${c.gbps.toStringAsFixed(1)} GB/s · ${bwScore.round()} pts';
      computeLines['${c.api} score'] = '${apiScores[c.api]!.round()} pts';
      computeLines['${c.api} sustained'] =
          'compute ${c.aluSustained.round()}% · memory ${c.bwSustained.round()}% of early speed';
    }

    // OpenCL is the primary API; OpenGL ES is the fallback when the phone has
    // no OpenCL.
    final primary = apiScores.containsKey('OpenCL')
        ? 'OpenCL'
        : apiScores.containsKey('GLES')
        ? 'GLES'
        : null;
    final rasterScore = _done.isEmpty
        ? null
        : weightedGeoMean([for (final r in _done) (r.score, r.phase.weight)]);

    final double score;
    final String basis;
    if (primary != null && !kRasterInScore) {
      score = apiScores[primary]!;
      basis =
          '$primary compute score only (Flutter raster scenes are shown but not counted)';
    } else if (primary != null && rasterScore != null) {
      score = weightedGeoMean([(apiScores[primary]!, 1), (rasterScore, 1)]);
      basis = '$primary compute score and raster scenes, equal weight';
    } else if (rasterScore != null) {
      score = rasterScore;
      basis = 'Raster scenes only (no compute API worked on this phone)';
    } else {
      score = 0;
      basis = 'Nothing could be measured';
    }
    final finalScore = score.roundToDouble();

    return BenchmarkResult(
      kind: BenchmarkKind.gpu,
      timestamp: DateTime.now(),
      ok: true,
      value: finalScore,
      details: {
        'Method':
            'Score = $basis. Each metric is min(8, speed ratio vs the S20) x kGpuAnchor, combined with a weighted geometric mean',
        'Baseline device': kReferenceDevice,
        for (final r in _done)
          r.phase.name:
              '${r.medMs.toStringAsFixed(1)} ms median · ${r.p95Ms.toStringAsFixed(1)} ms p95 · ${r.score.round()} pts',
        'Scope': 'Flutter raster scenes plus OpenGL ES 3.1 and OpenCL compute kernels (FMA throughput and buffer copy bandwidth). Raster results depend on the Flutter renderer (Impeller / Skia).',
        ...computeLines,
        if (_tempStart != null)
          'Battery temperature': ThermalMonitor.describe(_tempStart, _tempNow),
        if (_rasterNote != null) 'Raster scenes': 'Skipped: $_rasterNote',
        if (kCalibrationMode) 'Baseline snippet': _gpuSnippet(),
        'Thermals': 'Long GPU load heats the device. Later runs may be slower.',
        if (kDebugMode) 'Build': 'Debug build. Results are not representative. Use flutter run --release.',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _phases[_phase];
    final progress = _running
        ? ((_phase + (_rasterMs.length / _measureFrames).clamp(0.0, 1.0)) /
                  _phases.length)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;

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
              child: Column(
                children: [
                  Text(
                    _computeStage != null
                        ? 'Running $_computeStage test…'
                        : _running
                        ? 'Scene ${_phase + 1} of ${_phases.length}: ${p.name}'
                        : 'Runs OpenGL ES and OpenCL compute tests, then draws ${_phases.length} animated scenes and times the raster work. '
                              'Keep the screen on and the phone uncovered.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                  if (_running) ...[
                    const SizedBox(height: 10),
                    Container(
                      height: 4,
                      width: double.infinity,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemFill.resolveFrom(
                          context,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: CupertinoColors.activeBlue,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRect(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, __) => CustomPaint(
                        painter: _ScenePainter(
                          scene: p.scene,
                          t: _running ? _controller.value : 0,
                          tier: _tier,
                          points: _points,
                        ),
                        size: Size.infinite,
                      ),
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

class _ScenePainter extends CustomPainter {
  final _Scene scene;
  final double t;
  final int tier;
  final Float32List? points;

  const _ScenePainter({
    required this.scene,
    required this.t,
    required this.tier,
    required this.points,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    switch (scene) {
      case _Scene.blur:
        canvas.saveLayer(
          bounds,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        );
        _circles(canvas, size, _blurShapes[tier], alpha: 0.6, radius: 40);
        canvas.restore();
      case _Scene.filter:
        canvas.saveLayer(
          bounds,
          Paint()
            ..colorFilter = const ColorFilter.matrix(<double>[
              -1.5,
              0,
              0,
              0,
              300,
              0,
              -1.5,
              0,
              0,
              300,
              0,
              0,
              -1.5,
              0,
              300,
              0,
              0,
              0,
              1,
              0,
            ])
            ..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        );
        _circles(canvas, size, _blurShapes[tier], alpha: 0.8, radius: 30);
        canvas.restore();
      case _Scene.particles:
        final pts = points;
        if (pts == null) return;
        final scale = min(size.width, size.height);
        canvas.save();
        canvas.translate(size.width / 2, size.height / 2);
        canvas.rotate(t * 2 * pi);
        canvas.scale(scale);
        canvas.drawRawPoints(
          ui.PointMode.points,
          pts,
          Paint()
            ..color = const Color(0xFF5AC8FA)
            ..strokeWidth = 2 / scale
            ..strokeCap = StrokeCap.round,
        );
        canvas.restore();
      case _Scene.overdraw:
        _circles(
          canvas,
          size,
          _overdrawShapes[tier],
          alpha: 0.18,
          radius: 90,
          blend: BlendMode.screen,
        );
    }
  }

  void _circles(
    Canvas canvas,
    Size size,
    int count, {
    required double alpha,
    required double radius,
    BlendMode blend = BlendMode.srcOver,
  }) {
    final phase = t * 2 * pi;
    final paint = Paint()..blendMode = blend;
    for (var i = 0; i < count; i++) {
      final x =
          size.width / 2 +
          cos(phase * (1 + i % 5) * 0.5 + i * 0.37) * size.width * 0.42;
      final y =
          size.height / 2 +
          sin(phase * (1 + i % 7) * 0.3 + i * 0.21) * size.height * 0.42;
      paint.color = HSVColor.fromAHSV(
        alpha,
        ((i * 23) % 360).toDouble(),
        0.8,
        1,
      ).toColor();
      canvas.drawCircle(Offset(x, y), radius + (i % 4) * 14.0, paint);
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.t != t || old.scene != scene || old.points != points;
}
