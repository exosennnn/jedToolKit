import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show max, min;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'benchmark_config.dart';

/// Result of one GPU compute API run (OpenGL ES compute or OpenCL).
class ComputeResult {
  final String api;
  final bool ok;
  final String device;
  final double gflops; // FMA throughput
  final double gbps; // buffer copy bandwidth (read + write)
  // Speed of the last quarter of the run as % of the first quarter (100 = no drop).
  final double aluSustained, bwSustained;
  final String? error;

  const ComputeResult.ok(
    this.api,
    this.device,
    this.gflops,
    this.gbps, {
    this.aluSustained = 100,
    this.bwSustained = 100,
  }) : ok = true,
       error = null;

  const ComputeResult.failed(this.api, this.error)
    : ok = false,
      device = '',
      gflops = 0,
      gbps = 0,
      aluSustained = 0,
      bwSustained = 0;
}

/// GPU compute tests without any C/C++ code of our own:
///  * GLES:   OpenGL ES 3.1 compute shaders, run from Java (GlesComputeChannel.java).
///  * OpenCL: calls the phone's libOpenCL.so directly through dart:ffi.
class GpuCompute {
  static const _gles = MethodChannel('jedtoolkit/gles_compute');

  static Future<ComputeResult> gles({
    double seconds = kGpuComputeSeconds,
  }) async {
    try {
      final m = await _gles.invokeMapMethod<String, dynamic>('run', {
        'seconds': seconds,
        'warmUp': kGpuWarmUpSeconds,
      });
      if (m == null) {
        return const ComputeResult.failed(
          'GLES',
          'No answer from the native side',
        );
      }
      if (m['ok'] != true) {
        return ComputeResult.failed(
          'GLES',
          (m['error'] as String?) ?? 'Unknown error',
        );
      }
      return ComputeResult.ok(
        'GLES',
        (m['device'] as String?) ?? '',
        (m['gflops'] as num).toDouble(),
        (m['gbps'] as num).toDouble(),
        aluSustained: (m['aluSustained'] as num?)?.toDouble() ?? 100,
        bwSustained: (m['bwSustained'] as num?)?.toDouble() ?? 100,
      );
    } catch (e) {
      return ComputeResult.failed('GLES', '$e');
    }
  }

  static Future<ComputeResult> openCl({
    double seconds = kGpuComputeSeconds,
  }) async {
    try {
      return await Isolate.run(() => _openClRun(seconds));
    } catch (e) {
      return ComputeResult.failed('OpenCL', '$e');
    }
  }
}

// ======================================================================
// OpenCL through dart:ffi
// ======================================================================

// Same workload rules as the Java GLES test, so both stay safe for the display:
// every GPU submission is calibrated to ~8 ms and the GPU rests between runs.
const _kThreads = 1 << 20;
const _kAluProbeIters = 32;
const _kAluMaxIters = 4096;
const _kFlopsPerIter = 16.0; // 8 FMA x 2 FLOPs
const _kBwTotalBytes = 64 * 1024 * 1024;
const _kBwMaxReps = 16;
const _kTimedRuns = 7; // after 1 warm-up run
const _kSliceMs = 8.0;
const _kAbortMs = 200.0;

const _clDeviceTypeGpu = 4;
const _clMemReadWrite = 1;
const _clQueueProfiling = 2;
const _clDeviceName = 0x102B;
const _clDeviceVersion = 0x102F;
const _clDeviceMaxMemAlloc = 0x1010;
const _clProgramBuildLog = 0x1183;
const _clProfilingStart = 0x1282;
const _clProfilingEnd = 0x1283;

const _clSource = r'''
__kernel void alu(__global float* out, uint iters, float seed) {
  uint id = get_global_id(0);
  float x = (float)id * 1e-6f + seed;
  float a0 = x, a1 = x + 1.0f, a2 = x + 2.0f, a3 = x + 3.0f;
  float a4 = x + 4.0f, a5 = x + 5.0f, a6 = x + 6.0f, a7 = x + 7.0f;
  for (uint i = 0; i < iters; i++) {
    a0 = fma(a0, 0.9999f, 0.0001f); a1 = fma(a1, 0.9999f, 0.0001f);
    a2 = fma(a2, 0.9999f, 0.0001f); a3 = fma(a3, 0.9999f, 0.0001f);
    a4 = fma(a4, 0.9999f, 0.0001f); a5 = fma(a5, 0.9999f, 0.0001f);
    a6 = fma(a6, 0.9999f, 0.0001f); a7 = fma(a7, 0.9999f, 0.0001f);
  }
  out[id] = ((a0 + a1) + (a2 + a3)) + ((a4 + a5) + (a6 + a7));
}
__kernel void bw(__global float4* d, uint off) {
  uint id = get_global_id(0);
  d[id + off] = d[id] * 1.0001f;
}
''';

const _clPaths = [
  'libOpenCL.so',
  '/vendor/lib64/libOpenCL.so',
  '/system/vendor/lib64/libOpenCL.so',
  '/system/lib64/libOpenCL.so',
  '/vendor/lib/libOpenCL.so',
  '/system/vendor/lib/libOpenCL.so',
];

DynamicLibrary? _openClLib() {
  for (final p in _clPaths) {
    try {
      return DynamicLibrary.open(p);
    } catch (_) {}
  }
  return null;
}

// ---- native signatures (cl_int = Int32, cl_uint = Uint32, cl_ulong = Uint64, size_t = IntPtr)
typedef _V = Pointer<Void>;
typedef _GetPlatformIDsN = Int32 Function(Uint32, Pointer<_V>, Pointer<Uint32>);
typedef _GetPlatformIDsD = int Function(int, Pointer<_V>, Pointer<Uint32>);
typedef _GetDeviceIDsN = Int32 Function(
  _V,
  Uint64,
  Uint32,
  Pointer<_V>,
  Pointer<Uint32>,
);
typedef _GetDeviceIDsD = int Function(
  _V,
  int,
  int,
  Pointer<_V>,
  Pointer<Uint32>,
);
typedef _GetInfoN = Int32 Function(_V, Uint32, IntPtr, _V, Pointer<IntPtr>);
typedef _GetInfoD = int Function(_V, int, int, _V, Pointer<IntPtr>);
typedef _CreateContextN = _V Function(
  Pointer<IntPtr>,
  Uint32,
  Pointer<_V>,
  _V,
  _V,
  Pointer<Int32>,
);
typedef _CreateContextD = _V Function(
  Pointer<IntPtr>,
  int,
  Pointer<_V>,
  _V,
  _V,
  Pointer<Int32>,
);
typedef _CreateQueueN = _V Function(_V, _V, Uint64, Pointer<Int32>);
typedef _CreateQueueD = _V Function(_V, _V, int, Pointer<Int32>);
typedef _CreateProgramN = _V Function(
  _V,
  Uint32,
  Pointer<Pointer<Utf8>>,
  Pointer<IntPtr>,
  Pointer<Int32>,
);
typedef _CreateProgramD = _V Function(
  _V,
  int,
  Pointer<Pointer<Utf8>>,
  Pointer<IntPtr>,
  Pointer<Int32>,
);
typedef _BuildProgramN = Int32 Function(
  _V,
  Uint32,
  Pointer<_V>,
  Pointer<Utf8>,
  _V,
  _V,
);
typedef _BuildProgramD = int Function(
  _V,
  int,
  Pointer<_V>,
  Pointer<Utf8>,
  _V,
  _V,
);
typedef _BuildInfoN = Int32 Function(
  _V,
  _V,
  Uint32,
  IntPtr,
  _V,
  Pointer<IntPtr>,
);
typedef _BuildInfoD = int Function(_V, _V, int, int, _V, Pointer<IntPtr>);
typedef _CreateKernelN = _V Function(_V, Pointer<Utf8>, Pointer<Int32>);
typedef _CreateKernelD = _V Function(_V, Pointer<Utf8>, Pointer<Int32>);
typedef _CreateBufferN = _V Function(_V, Uint64, IntPtr, _V, Pointer<Int32>);
typedef _CreateBufferD = _V Function(_V, int, int, _V, Pointer<Int32>);
typedef _SetArgN = Int32 Function(_V, Uint32, IntPtr, _V);
typedef _SetArgD = int Function(_V, int, int, _V);
typedef _EnqueueN = Int32 Function(
  _V,
  _V,
  Uint32,
  Pointer<IntPtr>,
  Pointer<IntPtr>,
  Pointer<IntPtr>,
  Uint32,
  Pointer<_V>,
  Pointer<_V>,
);
typedef _EnqueueD = int Function(
  _V,
  _V,
  int,
  Pointer<IntPtr>,
  Pointer<IntPtr>,
  Pointer<IntPtr>,
  int,
  Pointer<_V>,
  Pointer<_V>,
);
typedef _HandleN = Int32 Function(_V);
typedef _HandleD = int Function(_V);

class _Cl {
  final _GetPlatformIDsD getPlatformIDs;
  final _GetDeviceIDsD getDeviceIDs;
  final _GetInfoD getDeviceInfo;
  final _GetInfoD getEventInfo;
  final _CreateContextD createContext;
  final _CreateQueueD createQueue;
  final _CreateProgramD createProgram;
  final _BuildProgramD buildProgram;
  final _BuildInfoD getBuildInfo;
  final _CreateKernelD createKernel;
  final _CreateBufferD createBuffer;
  final _SetArgD setArg;
  final _EnqueueD enqueue;
  final _HandleD finish;
  final _HandleD releaseEvent;
  final _HandleD releaseMem;
  final _HandleD releaseKernel;
  final _HandleD releaseProgram;
  final _HandleD releaseQueue;
  final _HandleD releaseContext;

  _Cl(DynamicLibrary l)
    : getPlatformIDs = l.lookupFunction<_GetPlatformIDsN, _GetPlatformIDsD>(
        'clGetPlatformIDs',
      ),
      getDeviceIDs = l.lookupFunction<_GetDeviceIDsN, _GetDeviceIDsD>(
        'clGetDeviceIDs',
      ),
      getDeviceInfo = l.lookupFunction<_GetInfoN, _GetInfoD>('clGetDeviceInfo'),
      getEventInfo = l.lookupFunction<_GetInfoN, _GetInfoD>(
        'clGetEventProfilingInfo',
      ),
      createContext = l.lookupFunction<_CreateContextN, _CreateContextD>(
        'clCreateContext',
      ),
      createQueue = l.lookupFunction<_CreateQueueN, _CreateQueueD>(
        'clCreateCommandQueue',
      ),
      createProgram = l.lookupFunction<_CreateProgramN, _CreateProgramD>(
        'clCreateProgramWithSource',
      ),
      buildProgram = l.lookupFunction<_BuildProgramN, _BuildProgramD>(
        'clBuildProgram',
      ),
      getBuildInfo = l.lookupFunction<_BuildInfoN, _BuildInfoD>(
        'clGetProgramBuildInfo',
      ),
      createKernel = l.lookupFunction<_CreateKernelN, _CreateKernelD>(
        'clCreateKernel',
      ),
      createBuffer = l.lookupFunction<_CreateBufferN, _CreateBufferD>(
        'clCreateBuffer',
      ),
      setArg = l.lookupFunction<_SetArgN, _SetArgD>('clSetKernelArg'),
      enqueue = l.lookupFunction<_EnqueueN, _EnqueueD>(
        'clEnqueueNDRangeKernel',
      ),
      finish = l.lookupFunction<_HandleN, _HandleD>('clFinish'),
      releaseEvent = l.lookupFunction<_HandleN, _HandleD>('clReleaseEvent'),
      releaseMem = l.lookupFunction<_HandleN, _HandleD>('clReleaseMemObject'),
      releaseKernel = l.lookupFunction<_HandleN, _HandleD>('clReleaseKernel'),
      releaseProgram = l.lookupFunction<_HandleN, _HandleD>('clReleaseProgram'),
      releaseQueue = l.lookupFunction<_HandleN, _HandleD>(
        'clReleaseCommandQueue',
      ),
      releaseContext = l.lookupFunction<_HandleN, _HandleD>('clReleaseContext');
}

double _median(List<double> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

void _breathe() => sleep(const Duration(milliseconds: 2));

/// Speed of the last quarter of the runs as a percentage of the first quarter.
double _sustained(List<double> ms) {
  if (ms.length < 8) return 100;
  final q = ms.length ~/ 4;
  return _median(ms.sublist(0, q)) / _median(ms.sublist(ms.length - q)) * 100;
}

/// Runs inside an isolate (Isolate.run), so the UI never waits for the GPU.
ComputeResult _openClRun(double seconds) {
  const api = 'OpenCL';
  final lib = _openClLib();
  if (lib == null) {
    return const ComputeResult.failed(
      api,
      'libOpenCL.so could not be loaded. Some devices do not ship OpenCL, and on '
      'Android 12+ the manifest needs <uses-native-library android:name="libOpenCL.so" '
      'android:required="false"/>.',
    );
  }
  final _Cl cl;
  try {
    cl = _Cl(lib);
  } catch (e) {
    return ComputeResult.failed(api, 'OpenCL function missing: $e');
  }

  final arena = Arena();
  final cleanups = <void Function()>[];
  try {
    return _openClBench(cl, arena, cleanups, seconds);
  } catch (e) {
    return ComputeResult.failed(api, '$e');
  } finally {
    for (final f in cleanups.reversed) {
      try {
        f();
      } catch (_) {}
    }
    arena.releaseAll();
  }
}

ComputeResult _openClBench(
  _Cl cl,
  Arena arena,
  List<void Function()> cleanups,
  double seconds,
) {
  const api = 'OpenCL';
  ComputeResult fail(String m) => ComputeResult.failed(api, m);
  final err = arena<Int32>();

  // ---- platform + GPU device
  final np = arena<Uint32>();
  cl.getPlatformIDs(0, nullptr, np);
  if (np.value == 0) return fail('No OpenCL platform found');
  final plats = arena<_V>(np.value);
  cl.getPlatformIDs(np.value, plats, nullptr);

  final devOut = arena<_V>();
  final nd = arena<Uint32>();
  _V device = nullptr;
  for (var i = 0; i < np.value; i++) {
    if (cl.getDeviceIDs(plats[i], _clDeviceTypeGpu, 1, devOut, nd) == 0 &&
        nd.value > 0) {
      device = devOut.value;
      break;
    }
  }
  if (device.address == 0) return fail('No OpenCL GPU device found');

  String info(int param) {
    final b = arena<Uint8>(256); // zero-filled, so always terminated
    cl.getDeviceInfo(device, param, 255, b.cast(), nullptr);
    return b.cast<Utf8>().toDartString();
  }

  final maxAllocP = arena<Uint64>();
  cl.getDeviceInfo(device, _clDeviceMaxMemAlloc, 8, maxAllocP.cast(), nullptr);
  final maxAlloc = maxAllocP.value;
  final label = '${info(_clDeviceName)} (${info(_clDeviceVersion)})';

  // ---- context, queue, program, kernels
  final devList = arena<_V>()..value = device;
  final ctx = cl.createContext(nullptr, 1, devList, nullptr, nullptr, err);
  if (ctx.address == 0 || err.value != 0) {
    return fail('clCreateContext failed (${err.value})');
  }
  cleanups.add(() => cl.releaseContext(ctx));

  final q = cl.createQueue(ctx, device, _clQueueProfiling, err);
  if (q.address == 0 || err.value != 0) {
    return fail('clCreateCommandQueue failed (${err.value})');
  }
  cleanups.add(() => cl.releaseQueue(q));

  final srcP = _clSource.toNativeUtf8(allocator: arena);
  final srcArr = arena<Pointer<Utf8>>()..value = srcP;
  final prog = cl.createProgram(ctx, 1, srcArr, nullptr, err);
  if (prog.address == 0 || err.value != 0) {
    return fail('clCreateProgramWithSource failed (${err.value})');
  }
  cleanups.add(() => cl.releaseProgram(prog));
  final opts = ''.toNativeUtf8(allocator: arena);
  if (cl.buildProgram(prog, 1, devList, opts, nullptr, nullptr) != 0) {
    final log = arena<Uint8>(1024);
    cl.getBuildInfo(
      prog,
      device,
      _clProgramBuildLog,
      1023,
      log.cast(),
      nullptr,
    );
    return fail(
      'OpenCL kernel build failed: ${log.cast<Utf8>().toDartString()}',
    );
  }

  final kAlu = cl.createKernel(prog, 'alu'.toNativeUtf8(allocator: arena), err);
  if (kAlu.address == 0 || err.value != 0)
    return fail('clCreateKernel(alu) failed');
  cleanups.add(() => cl.releaseKernel(kAlu));
  final kBw = cl.createKernel(prog, 'bw'.toNativeUtf8(allocator: arena), err);
  if (kBw.address == 0 || err.value != 0)
    return fail('clCreateKernel(bw) failed');
  cleanups.add(() => cl.releaseKernel(kBw));

  // ---- helpers
  int argHandle(_V k, int i, _V h) {
    final p = arena<_V>()..value = h;
    return cl.setArg(k, i, sizeOf<_V>(), p.cast());
  }

  int argU32(_V k, int i, int v) {
    final p = arena<Uint32>()..value = v;
    return cl.setArg(k, i, 4, p.cast());
  }

  int argF32(_V k, int i, double v) {
    final p = arena<Float>()..value = v;
    return cl.setArg(k, i, 4, p.cast());
  }

  /// `reps` back-to-back launches; returns GPU time from the profiling events, or null on failure.
  double? timeKernel(_V k, int gws, int reps) {
    final g = arena<IntPtr>()..value = gws;
    final evs = <Pointer<_V>>[];
    var ok = true;
    for (var r = 0; r < reps && ok; r++) {
      final ev = arena<_V>();
      evs.add(ev);
      ok = cl.enqueue(q, k, 1, nullptr, g, nullptr, 0, nullptr, ev) == 0;
    }
    cl.finish(q);
    final s = arena<Uint64>();
    final e = arena<Uint64>();
    if (ok) {
      ok =
          cl.getEventInfo(
                evs.first.value,
                _clProfilingStart,
                8,
                s.cast(),
                nullptr,
              ) ==
              0 &&
          cl.getEventInfo(
                evs.last.value,
                _clProfilingEnd,
                8,
                e.cast(),
                nullptr,
              ) ==
              0;
    }
    for (final ev in evs) {
      if (ev.value.address != 0) cl.releaseEvent(ev.value);
    }
    return ok ? (e.value - s.value) / 1e6 : null;
  }

  // ---- ALU (FMA) throughput
  var aluSustained = 100.0;
  var bwSustained = 100.0;
  var aluIters = _kAluProbeIters;
  late final double aluMs;
  {
    final buf = cl.createBuffer(
      ctx,
      _clMemReadWrite,
      _kThreads * 4,
      nullptr,
      err,
    );
    if (buf.address == 0 || err.value != 0) {
      return fail('Could not allocate the ALU output buffer');
    }
    cleanups.add(() => cl.releaseMem(buf));
    argHandle(kAlu, 0, buf);
    argF32(kAlu, 2, 0.5);

    double? run(int iters) {
      argU32(kAlu, 1, iters);
      return timeKernel(kAlu, _kThreads, 1);
    }

    double probe = 0;
    for (var i = 0; i < 2; i++) {
      final ms = run(_kAluProbeIters);
      if (ms == null) return fail('ALU kernel launch failed');
      probe = ms;
      _breathe();
    }
    if (probe > _kAbortMs) {
      return fail(
        'GPU is too slow or busy for the compute test (skipped to avoid a hang)',
      );
    }
    aluIters = min(
      _kAluMaxIters,
      max(
        _kAluProbeIters,
        (_kSliceMs / (max(probe, 0.001) / _kAluProbeIters)).floor(),
      ),
    );
    // Warm-up: keep the GPU busy so its clock ramps up before timing starts.
    final warm = Stopwatch()..start();
    while (warm.elapsedMilliseconds < kGpuWarmUpSeconds * 1000) {
      if (run(aluIters) == null) return fail('ALU kernel launch failed');
      _breathe();
    }
    final t = <double>[];
    final clock = Stopwatch()..start();
    for (
      var i = 0;
      i < _kTimedRuns || clock.elapsedMilliseconds < seconds * 1000;
      i++
    ) {
      final ms = run(aluIters);
      if (ms == null) return fail('ALU kernel launch failed');
      _breathe();
      t.add(ms);
    }
    aluMs = _median(t);
    aluSustained = _sustained(t);
  }

  // ---- memory bandwidth (copy first half of the buffer into the second half)
  final bwCap = maxAlloc > 0 ? min(_kBwTotalBytes, maxAlloc) : _kBwTotalBytes;
  final half = ((bwCap ~/ 2 ~/ 16) ~/ 256) * 256;
  var bwReps = 1;
  late final double bwMs;
  {
    final buf = cl.createBuffer(
      ctx,
      _clMemReadWrite,
      half * 16 * 2,
      nullptr,
      err,
    );
    if (buf.address == 0 || err.value != 0) {
      return fail('Could not allocate the bandwidth buffer');
    }
    cleanups.add(() => cl.releaseMem(buf));
    argHandle(kBw, 0, buf);
    argU32(kBw, 1, half);

    double probe = 0;
    for (var i = 0; i < 2; i++) {
      final ms = timeKernel(kBw, half, 1);
      if (ms == null) return fail('Bandwidth kernel launch failed');
      probe = ms;
      _breathe();
    }
    if (probe > _kAbortMs) {
      return fail(
        'GPU memory is too slow or busy for the bandwidth test (skipped)',
      );
    }
    bwReps = min(_kBwMaxReps, max(1, (_kSliceMs / max(probe, 0.001)).floor()));
    final warm = Stopwatch()..start();
    while (warm.elapsedMilliseconds < kGpuWarmUpSeconds * 1000) {
      if (timeKernel(kBw, half, bwReps) == null) {
        return fail('Bandwidth kernel launch failed');
      }
      _breathe();
    }
    final t = <double>[];
    final clock = Stopwatch()..start();
    for (
      var i = 0;
      i < _kTimedRuns || clock.elapsedMilliseconds < seconds * 1000;
      i++
    ) {
      final ms = timeKernel(kBw, half, bwReps);
      if (ms == null) return fail('Bandwidth kernel launch failed');
      _breathe();
      t.add(ms);
    }
    bwMs = _median(t);
    bwSustained = _sustained(t);
  }

  final gflops = _kThreads * aluIters * _kFlopsPerIter / (aluMs * 1e6);
  final gbps = half * 16.0 * 2.0 * bwReps / (bwMs * 1e6);
  return ComputeResult.ok(
    api,
    label,
    gflops,
    gbps,
    aluSustained: aluSustained,
    bwSustained: bwSustained,
  );
}
