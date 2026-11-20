import 'dart:io';
import 'dart:isolate';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';

import 'benchmark_config.dart';
import 'benchmark_models.dart';
import 'benchmark_workloads.dart';
import 'cpu_affinity.dart';
import 's20_baseline.dart';
import 'thermal_monitor.dart';

typedef ProgressCallback = void Function(double progress, String stage);
typedef CancelCheck = bool Function();

// Top-level so the isolate closure captures only two ints.
Future<double> _cpuSliceInIsolate(int id, int tier, int slice, int slices) =>
    Isolate.run(() => runCpuTaskSlice(id, tier, slice, slices));

/// One multi-threaded workload: its work is cut into [slices] pieces and one
/// worker per core keeps taking the next piece, so fast cores take more of them
/// (like a thread pool). The whole workload is repeated until [minSeconds] have
/// passed (at least one pass). Returns the mean wall time of one pass.
Future<double> _cpuTaskParallel(
  int id,
  int tier,
  int workers,
  int slices,
  double minSeconds,
  CancelCheck isCancelled,
) async {
  final total = Stopwatch()..start();
  var passes = 0;
  var busy = 0.0;
  do {
    final pass = Stopwatch()..start();
    var next = 0;
    Future<void> worker() async {
      while (!isCancelled()) {
        final k = next++;
        if (k >= slices) return;
        await _cpuSliceInIsolate(id, tier, k, slices);
      }
    }

    await Future.wait([for (var w = 0; w < workers; w++) worker()]);
    pass.stop();
    busy += pass.elapsedMicroseconds / 1e6;
    passes++;
  } while (!isCancelled() && total.elapsedMicroseconds / 1e6 < minSeconds);
  return busy / passes;
}

Future<(double, bool)> _cpuTaskPinned(int id, int tier, int core) =>
    Isolate.run(() => runCpuTaskPinned(id, tier, core));

Future<List<double>> _memoryInIsolate(int sizeMB) =>
    Isolate.run(() => memoryIteration(sizeMB));

Map<String, String> _commonNotes() => {
  'Thermals': 'Sustained load heats the device and can slow later tests. Compare runs under similar conditions.',
  if (kDebugMode) 'Build': 'Debug build. Results are not representative. Use flutter run --release.',
};

String _cpuSnippet(List<double> secs) =>
    'const kS20CpuBaselineSec = <double>[${secs.map((s) => s.toStringAsFixed(3)).join(', ')}];';

/// Port of CPUBenchmark.swift. One run produces BOTH results: single-core runs
/// all 16 tasks one at a time; multi-core runs only the 8 workloads that real
/// apps run multi-threaded, each split across all cores and scored against its
/// own S20 multi-core time. Every task repeats for a minimum time (see
/// benchmark_config.dart), then an optional sustained all-core phase measures
/// how much speed the phone keeps once it is hot.
class CpuRunner {
  Future<List<BenchmarkResult>?> run({
    required ProgressCallback onProgress,
    required CancelCheck isCancelled,
  }) async {
    final tier = deviceTier();
    final n = cpuTasks.length;
    final m = multiCoreTasks.length;
    final cores = Platform.numberOfProcessors;
    final prime = primeCoreIndex();
    var pinnedAll = true;

    // Rough total time, only used to draw the progress bar.
    final estimate =
        n * kSingleTaskSeconds + m * kMultiTaskSeconds + kSustainedSeconds + 5;
    final overall = Stopwatch()..start();
    double prog() => min(0.99, overall.elapsedMilliseconds / 1000 / estimate);

    List<BenchmarkResult> stopped(String why) {
      final msg =
          'Stopped to protect the phone: $why. Let it cool down and run again.';
      return [
        BenchmarkResult.failed(BenchmarkKind.cpuSingle, msg),
        BenchmarkResult.failed(BenchmarkKind.cpuMulti, msg),
      ];
    }

    Future<String?> tooHot() async =>
        ThermalMonitor.unsafeReason(await ThermalMonitor.read());

    try {
      final tempStart = await ThermalMonitor.read();

      // ---- single-core: one task at a time, each repeated for a while
      final secs = <double>[];
      final scores = <double>[];
      final weighted = <(double, double)>[];
      onProgress(0, 'Starting single-core tests');
      final singleClock = Stopwatch()..start();

      for (var i = 0; i < n; i++) {
        if (isCancelled()) return null;
        final hot = await tooHot();
        if (hot != null) return stopped(hot);
        onProgress(prog(), 'Single-core: ${cpuTasks[i].name}');
        final (s, pinned) = await _cpuTaskPinned(i, tier, prime);
        if (!pinned) pinnedAll = false;
        final score =
            kS20CpuBaselineSec[i] / (s > 0 ? s : 1e-6) * kCpuSingleAnchor;
        secs.add(s);
        scores.add(score);
        weighted.add((score, cpuTasks[i].weight));
      }
      singleClock.stop();
      final singleScore = weightedGeoMean(weighted).roundToDouble();

      // ---- multi-core: 8 parallel workloads, each split across all cores
      final slices = cores * 4;
      final multiSecs = <double>[];
      final multiScores = <double>[];
      final multiWeighted = <(double, double)>[];
      var singleSecsOfThose = 0.0;
      final multiClock = Stopwatch()..start();
      for (var j = 0; j < m; j++) {
        if (isCancelled()) return null;
        final hot = await tooHot();
        if (hot != null) return stopped(hot);
        final id = multiCoreTasks[j];
        onProgress(prog(), 'Multi-core: ${cpuTasks[id].name}');
        final s = await _cpuTaskParallel(
          id,
          tier,
          cores,
          slices,
          kMultiTaskSeconds,
          isCancelled,
        );
        final score =
            kS20CpuMultiBaselineSec[j] / (s > 0 ? s : 1e-6) * kCpuMultiAnchor;
        multiSecs.add(s);
        multiScores.add(score);
        multiWeighted.add((score, cpuTasks[id].weight));
        singleSecsOfThose += secs[id];
      }
      multiClock.stop();
      if (isCancelled()) return null;
      final multiScore = weightedGeoMean(multiWeighted).roundToDouble();
      final multiTotal = multiSecs.fold<double>(0, (a, b) => a + b);
      final speedup = singleSecsOfThose / (multiTotal > 0 ? multiTotal : 1);

      // ---- sustained: every core busy back to back, one score per cycle
      final cycles = <(double, double)>[]; // (seconds since start, cycle score)
      String? sustainedStop;
      if (kSustainedSeconds > 0) {
        final clock = Stopwatch()..start();
        while (clock.elapsedMilliseconds < kSustainedSeconds * 1000) {
          if (isCancelled()) return null;
          final hot = await tooHot();
          if (hot != null) {
            sustainedStop = hot;
            break;
          }
          final items = <(double, double)>[];
          for (var j = 0; j < m; j++) {
            final id = multiCoreTasks[j];
            onProgress(
              prog(),
              'Sustained load ${clock.elapsed.inSeconds} s of $kSustainedSeconds s: ${cpuTasks[id].name}',
            );
            final s = await _cpuTaskParallel(
              id,
              tier,
              cores,
              slices,
              0,
              isCancelled,
            );
            items.add((
              kS20CpuMultiBaselineSec[j] / (s > 0 ? s : 1e-6) * kCpuMultiAnchor,
              cpuTasks[id].weight,
            ));
          }
          if (isCancelled()) return null;
          cycles.add((
            clock.elapsedMilliseconds / 1000,
            weightedGeoMean(items),
          ));
        }
      }
      final tempEnd = await ThermalMonitor.read();

      String sustainedLine = 'Off';
      String? sustainedCurve;
      if (kSustainedSeconds > 0) {
        if (cycles.length >= 2) {
          final q = (cycles.length ~/ 4) < 1 ? 1 : cycles.length ~/ 4;
          double avg(Iterable<double> xs) =>
              xs.reduce((a, b) => a + b) / xs.length;
          final first = avg(cycles.take(q).map((c) => c.$2));
          final last = avg(cycles.skip(cycles.length - q).map((c) => c.$2));
          sustainedLine =
              '${(last / first * 100).round()}% of early speed kept '
              '(${first.round()} pts at the start, ${last.round()} pts at the end, ${cycles.length} cycles)';
          final len = cycles.length;
          sustainedCurve =
              {0, (len - 1) ~/ 4, (len - 1) ~/ 2, 3 * (len - 1) ~/ 4, len - 1}
                  .map(
                    (i) => '${cycles[i].$1.round()} s: ${cycles[i].$2.round()}',
                  )
                  .join(' · ');
        } else {
          sustainedLine = 'Too short to measure';
        }
        if (sustainedStop != null) {
          sustainedLine += ' · stopped early: $sustainedStop';
        }
      }

      onProgress(1, 'All CPU tests completed');

      final taskLines = {
        for (var i = 0; i < n; i++)
          cpuTasks[i].name:
              '${secs[i].toStringAsFixed(2)} s · ${scores[i].round()} pts',
      };
      final multiTaskLines = {
        for (var j = 0; j < m; j++)
          cpuTasks[multiCoreTasks[j]].name:
              '${multiSecs[j].toStringAsFixed(2)} s · ${multiScores[j].round()} pts',
      };

      return [
        BenchmarkResult(
          kind: BenchmarkKind.cpuSingle,
          timestamp: DateTime.now(),
          ok: true,
          value: singleScore,
          details: {
            'Method':
                'Weighted geometric mean of 16 tasks. Each task repeats for at least ${kSingleTaskSeconds.toStringAsFixed(0)} s and its mean time per run is scored against its S20 time. Scaled so the S20 scores kCpuSingleAnchor',
            'Baseline device': kReferenceDevice,
            'Single-core time':
                '${(singleClock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s',
            'Core pinning': prime < 0
                ? 'Not needed (no big/little split found)'
                : pinnedAll
                ? 'Pinned to the fastest core (cpu$prime)'
                : 'Not available. Tasks may run on any core.',
            ...taskLines,
            if (kCalibrationMode) 'Baseline snippet': _cpuSnippet(secs),
            ..._commonNotes(),
          },
        ),
        BenchmarkResult(
          kind: BenchmarkKind.cpuMulti,
          timestamp: DateTime.now(),
          ok: true,
          value: multiScore,
          details: {
            'Method':
                'Only the 8 workloads that real apps run multi-threaded (File Compression, Photo Library, Clang, Text Processing, Asset Compression, HDR, Photo Editor, Ray Tracer), each split across all cores, repeated for at least ${kMultiTaskSeconds.toStringAsFixed(0)} s and scored against its S20 multi-core time. Weighted geometric mean, scaled so the S20 scores kCpuMultiAnchor',
            'Cores used': '$cores',
            'Multi-core time':
                '${(multiClock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s',
            'Speedup': 'x${speedup.toStringAsFixed(2)} on those 8 workloads',
            'Sustained load': sustainedLine,
            if (sustainedCurve != null) 'Sustained curve': sustainedCurve,
            'Battery temperature': ThermalMonitor.describe(tempStart, tempEnd),
            'Baseline device': kReferenceDevice,
            ...multiTaskLines,
            if (kCalibrationMode)
              'Baseline snippet':
                  'const kS20CpuMultiBaselineSec = <double>[${multiSecs.map((s) => s.toStringAsFixed(3)).join(', ')}];',
            ..._commonNotes(),
          },
        ),
      ];
    } catch (e) {
      final msg = 'Test failed: $e';
      return [
        BenchmarkResult.failed(BenchmarkKind.cpuSingle, msg),
        BenchmarkResult.failed(BenchmarkKind.cpuMulti, msg),
      ];
    }
  }
}

/// Port of MemoryBenchmark.swift: write, read and random-access bandwidth,
/// at least 3 iterations and kMemoryMinSeconds, weighted geometric mean (0.3 / 0.3 / 0.4).
class MemoryRunner {
  static const _minIterations = 3;

  Future<BenchmarkResult?> run({
    required ProgressCallback onProgress,
    required CancelCheck isCancelled,
  }) async {
    final tier = deviceTier();
    final t = memoryTiers[tier];
    final elements = (t.sizeMB * 1024 * 1024) ~/ 8;
    final ops = (elements ~/ 10).toDouble();

    final writeScores = <double>[];
    final readScores = <double>[];
    final randomScores = <double>[];
    var lastW = 0.0, lastR = 0.0, lastRand = 0.0;
    final rawW = <double>[], rawR = <double>[], rawRand = <double>[];

    try {
      final clock = Stopwatch()..start();
      for (
        var i = 0;
        i < _minIterations ||
            clock.elapsedMilliseconds < kMemoryMinSeconds * 1000;
        i++
      ) {
        if (isCancelled()) return null;
        onProgress(
          min(0.99, clock.elapsedMilliseconds / 1000 / kMemoryMinSeconds),
          'Iteration ${i + 1}',
        );
        final times = await _memoryInIsolate(t.sizeMB);

        final w = times[0] > 0 ? t.sizeMB / times[0] : 0.0;
        final r = times[1] > 0 ? t.sizeMB / times[1] : 0.0;
        final rand = times[2] > 0 ? (ops * 8) / (times[2] * 1024 * 1024) : 0.0;
        lastW = w;
        lastR = r;
        lastRand = rand;
        rawW.add(w);
        rawR.add(r);
        rawRand.add(rand);

        writeScores.add(_max50(w / kS20MemWriteMBs * kBaselineScore));
        readScores.add(_max50(r / kS20MemReadMBs * kBaselineScore));
        randomScores.add(_max50(rand / kS20MemRandomMBs * kBaselineScore));
      }
    } catch (e) {
      return BenchmarkResult.failed(
        BenchmarkKind.memory,
        'Not enough free memory for a ${t.sizeMB} MB test array. Close other apps and try again. ($e)',
      );
    }

    double avg(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    final avgW = avg(writeScores),
        avgR = avg(readScores),
        avgRand = avg(randomScores);
    final score = weightedGeoMean([
      (avgW, memWriteWeight),
      (avgR, memReadWeight),
      (avgRand, memRandomWeight),
    ]).roundToDouble();

    onProgress(1, 'Done');

    return BenchmarkResult(
      kind: BenchmarkKind.memory,
      timestamp: DateTime.now(),
      ok: true,
      value: score,
      details: {
        'Method':
            'Weighted geometric mean of write (30%), read (30%) and random access (40%) scores, averaged over ${writeScores.length} iterations',
        'Baseline device': kReferenceDevice,
        'Test array': '${t.sizeMB} MB',
        'Write score':
            '${avgW.round()} pts (last: ${lastW.toStringAsFixed(0)} MB/s)',
        'Read score':
            '${avgR.round()} pts (last: ${lastR.toStringAsFixed(0)} MB/s)',
        'Random access score':
            '${avgRand.round()} pts (last: ${lastRand.toStringAsFixed(0)} MB/s)',
        'Scope': 'Measured from Dart. Not a hardware memory spec.',
        if (kCalibrationMode)
          'Baseline snippet':
              'const kS20MemWriteMBs = ${avg(rawW).toStringAsFixed(0)}.0; const kS20MemReadMBs = ${avg(rawR).toStringAsFixed(0)}.0; const kS20MemRandomMBs = ${avg(rawRand).toStringAsFixed(0)}.0;',
        ..._commonNotes(),
      },
    );
  }

  double _max50(double v) => v < 50 ? 50 : v;
}
