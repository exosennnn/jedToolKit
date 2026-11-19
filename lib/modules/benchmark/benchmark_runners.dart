import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'benchmark_models.dart';
import 'benchmark_workloads.dart';

typedef ProgressCallback = void Function(double progress, String stage);
typedef CancelCheck = bool Function();

const int _warmUpRounds = 1;
const int _timedRounds = 3;

/// Shared loop: one warm-up round, then timed rounds. Reports the median.
Future<BenchmarkResult?> _runRounds({
  required BenchmarkKind kind,
  required Future<double> Function() round,
  required Map<String, String> Function() details,
  required ProgressCallback onProgress,
  required CancelCheck isCancelled,
}) async {
  final total = _warmUpRounds + _timedRounds;
  final samples = <double>[];

  try {
    for (var i = 0; i < total; i++) {
      if (isCancelled()) return null;
      final warm = i < _warmUpRounds;
      onProgress(
        i / total,
        warm ? 'Warm-up' : 'Round ${i - _warmUpRounds + 1} of $_timedRounds',
      );
      final value = await round();
      if (!warm) samples.add(value);
    }
  } catch (e) {
    return BenchmarkResult.failed(
      kind,
      kind == BenchmarkKind.memory
          ? 'Not enough free memory for two 64 MiB buffers. Close other apps and try again.'
          : 'Test failed: $e',
    );
  }

  onProgress(1, 'Done');

  return BenchmarkResult(
    kind: kind,
    timestamp: DateTime.now(),
    ok: true,
    value: _median(samples),
    details: {
      ...details(),
      'Method':
          'Median of $_timedRounds timed rounds after $_warmUpRounds warm-up',
      'Rounds':
          '${_low(samples).toStringAsFixed(1)} to ${_high(samples).toStringAsFixed(1)} ${kind.unit}',
      'Thermals':
          'Sustained load heats the device and can slow later rounds. Compare runs under similar conditions.',
      if (kDebugMode)
        'Build': 'Debug build. Results are not representative. Use flutter run --release.',
    },
  );
}

class CpuRunner {
  Future<BenchmarkResult?> run({
    required bool multiThread,
    required ProgressCallback onProgress,
    required CancelCheck isCancelled,
  }) {
    final threads = multiThread ? Platform.numberOfProcessors : 1;
    final kind = multiThread ? BenchmarkKind.cpuMulti : BenchmarkKind.cpuSingle;

    return _runRounds(
      kind: kind,
      round: () => _cpuRound(threads),
      details: () => {
        'Threads used': '$threads of ${Platform.numberOfProcessors} cores',
        'Workload': 'Prime sieve to 5,000,000, $kSievePasses passes per thread',
        'Check': 'Each pass must find π(5,000,000) = 348,513 primes',
        'Unit': 'million numbers sieved per second',
      },
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}

class MemoryRunner {
  Future<BenchmarkResult?> run({
    required ProgressCallback onProgress,
    required CancelCheck isCancelled,
  }) {
    return _runRounds(
      kind: BenchmarkKind.memory,
      round: _memoryRound,
      details: () => {
        'Buffers': '${kBufferBytes ~/ 1048576} MiB each, two in total',
        'Copies per round': '$kCopiesPerRound',
        'Unit': 'mebibytes written per second',
        'Scope':
            'Shows how fast this device moves data through memory from Dart. It is not a hardware memory spec.',
      },
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}

Future<double> _cpuRound(int threads) async {
  final sw = Stopwatch()..start();
  final parts = await Future.wait([
    for (var t = 0; t < threads; t++) Isolate.run(() => cpuPasses(kSievePasses)),
  ]);
  sw.stop();

  for (final p in parts) {
    if (p[1] != 1) throw StateError('Prime count check failed');
  }

  // numbers per microsecond is the same as millions of numbers per second.
  final numbers = threads * kSievePasses * kSieveLimit;
  return numbers / sw.elapsedMicroseconds;
}

Future<double> _memoryRound() async {
  final parts = await Isolate.run(() => memoryCopyPass(kCopiesPerRound));
  if (parts[1] != 1) throw StateError('Memory check failed');

  final mib = kCopiesPerRound * kBufferBytes / 1048576;
  return mib / (parts[0] / 1e6);
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _low(List<double> xs) => xs.reduce((a, b) => a < b ? a : b);

double _high(List<double> xs) => xs.reduce((a, b) => a > b ? a : b);