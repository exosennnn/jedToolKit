/// How hard and how long the benchmark pushes the phone.
///
/// The old test finished in about a minute and only kept ONE core busy for most
/// of it, so the phone never warmed up. Every test below now repeats its work
/// until it has run for a minimum time, so clocks ramp up, the SoC heats up and
/// the score reflects speed under sustained load, like a real stress test.
///
/// Rough total time with the defaults: about 6 minutes
///   single-core 16 x 4 s = 64 s
///   multi-core   8 x 6 s = 48 s
///   sustained all-core load = 180 s
///   memory >= 10 s, GPU compute ~25 s, GPU raster scenes ~35 s
/// For a 12 to 15 minute run set [kSustainedSeconds] to 600.
///
/// Changing these changes the scores (a longer test includes more throttling).
/// Recalibrate the S20 baselines in s20_baseline.dart after changing them.

/// Each single-core task repeats for at least this long (mean time per run).
const kSingleTaskSeconds = 4.0;

/// Each multi-core workload repeats for at least this long.
const kMultiTaskSeconds = 6.0;

/// All cores loaded back to back after the multi-core test. 0 turns it off.
/// Reports how much speed the phone keeps once it is hot.
const kSustainedSeconds = 180;

/// Memory test keeps iterating until at least this long (and 3 iterations).
const kMemoryMinSeconds = 10.0;

/// Each GPU compute kernel is measured for this long, after a warm-up.
const kGpuComputeSeconds = 4.0;
const kGpuWarmUpSeconds = 1.0;

/// Safety: the test stops by itself when Android reports severe throttling or
/// the battery sensor reaches this temperature.
const kThermalStopBatteryC = 46.0;
const kThermalStopStatus = 3; // PowerManager.THERMAL_STATUS_SEVERE
