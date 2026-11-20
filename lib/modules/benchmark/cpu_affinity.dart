import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'benchmark_config.dart';
import 'benchmark_workloads.dart';

/// Android phones are big.LITTLE (Snapdragon 865: 1 prime + 3 gold + 4 silver).
/// An unpinned "single-core" task can land on a little core and score 3x lower
/// from run to run. Single-core tasks are therefore pinned to the fastest core.

/// Index of the fastest core, or -1 when frequencies can't be read or all
/// cores are identical (nothing to pin).
int primeCoreIndex() {
  final n = Platform.numberOfProcessors;
  final freqs = <int>[];
  try {
    for (var i = 0; i < n; i++) {
      final f = File('/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq')
          .readAsStringSync()
          .trim();
      freqs.add(int.tryParse(f) ?? 0);
    }
  } catch (_) {
    return -1;
  }
  if (freqs.length != n) return -1;
  final top = freqs.reduce((a, b) => a > b ? a : b);
  if (top == 0 || freqs.every((f) => f == top)) return -1;
  return freqs.lastIndexOf(top); // prime cores sit at the highest indices
}

typedef _SetAffinityC = Int32 Function(
  Int32 pid,
  IntPtr size,
  Pointer<Uint8> mask,
);
typedef _SetAffinityDart = int Function(int pid, int size, Pointer<Uint8> mask);

/// Sets the CPU mask of the CALLING thread (pid 0 = this thread).
bool _setAffinity(Iterable<int> cpus) {
  final lib = DynamicLibrary.open('libc.so');
  final fn = lib.lookupFunction<_SetAffinityC, _SetAffinityDart>(
    'sched_setaffinity',
  );
  const bytes = 128; // cpu_set_t, 1024 bits
  final mask = calloc<Uint8>(bytes);
  try {
    for (final c in cpus) {
      if (c >= 0 && c < bytes * 8) mask[c ~/ 8] |= 1 << (c % 8);
    }
    return fn(0, bytes, mask) == 0;
  } finally {
    calloc.free(mask);
  }
}

/// Runs one CPU task on [core] (-1 = no pinning). Call inside an isolate.
/// Returns (seconds, whether pinning worked).
(double, bool) runCpuTaskPinned(int id, int tier, int core) {
  var pinned = false;
  if (core >= 0) {
    try {
      pinned = _setAffinity([core]);
    } catch (_) {}
  }
  try {
    return (runCpuTaskSustained(id, tier, kSingleTaskSeconds), pinned);
  } finally {
    if (pinned) {
      // Isolate threads are pooled: give the thread back all cores.
      try {
        _setAffinity([for (var i = 0; i < Platform.numberOfProcessors; i++) i]);
      } catch (_) {}
    }
  }
}
