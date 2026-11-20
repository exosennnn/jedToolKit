/// Every Android score is relative to ONE reference phone:
/// 2500 pts = a Samsung Galaxy S20 (Snapdragon 865, Adreno 650) doing the
/// same work. All phones run the same workload, so scores compare directly.
///
/// The numbers below are STARTING VALUES, not measurements. Calibrate them:
///   1. Set [kCalibrationMode] = true, build a release APK, run on the S20.
///   2. Let it cool, run each test ~5 times, copy the "Baseline snippet" line
///      from each result's details, and keep the median value of each constant.
///   3. Paste them here and set [kCalibrationMode] back to false.
/// After that the S20 lands on ~2500 in every test.
const kReferenceDevice = 'Galaxy S20 · Snapdragon 865 · Adreno 650';

const kCalibrationMode = false;

/// NOTE: tests now repeat for a minimum time (benchmark_config.dart), so the
/// baselines below must be measured with that same configuration. Calibrate
/// again on the S20 after changing any duration.

/// ---- Score anchors ----------------------------------------------------------
/// What the S20 itself scores in each test. Every other phone scores in
/// proportion to how much faster (or slower) it is than the S20, so a phone
/// twice as fast gets twice these numbers. Leave them at 2500 for the classic
/// "2500 = S20" scale, or set them to any other reference score you prefer.
const kCpuSingleAnchor = 2500.0; // S20 single-core score
const kCpuMultiAnchor = 2500.0; // S20 multi-core score
const kGpuAnchor = 2500.0; // S20 GPU score

/// false = Flutter raster scenes are measured and shown but don't change the
/// GPU score, which then comes from compute only (raster time depends on the
/// Flutter renderer, not just the GPU).
const kRasterInScore = false;

/// Seconds per CPU task on the S20, same order as `cpuTasks`.
/// (Placeholders: the old iOS baselines.)
const kS20CpuBaselineSec = <double>[
  1.2, 0.8, 0.5, 0.3, 0.4, 1.2, 0.6, 2.5, //
  1.8, 1.5, 1.2, 1.2, 1.0, 0.9, 2.8, 1.4,
];

/// Seconds per workload on the S20 when split across all cores, in the order of
/// `multiCoreTasks`. (Placeholders: single-core baseline / 4. Calibrate.)
const kS20CpuMultiBaselineSec = <double>[
  0.30,
  0.10,
  0.30,
  0.15,
  0.62,
  0.30,
  0.25,
  0.70,
];

/// Memory bandwidth measured from Dart, MB/s. (Placeholders.)
const kS20MemWriteMBs = 2800.0;
const kS20MemReadMBs = 2500.0;
const kS20MemRandomMBs = 400.0;

/// Flutter raster time per frame, ms. (Placeholders.)
const kS20BlurMs = 9.0;
const kS20FilterMs = 5.0;
const kS20ParticlesMs = 6.0;
const kS20OverdrawMs = 8.0;

/// GPU compute kernels (OpenGL ES 3.1 compute and OpenCL). Rough guesses from Adreno 650 public specs
/// (~1.2 TFLOPS FP32 peak, LPDDR5): replace by calibration.
const kS20GlesGflops = 900.0;
const kS20GlesGBps = 25.0;
const kS20ClGflops = 900.0;
const kS20ClGBps = 25.0;

/// Weight of each compute kernel inside the GPU score (raster scenes weigh 11.8 in total).
const kComputeAluWeight = 2.0;
const kComputeBandwidthWeight = 1.5;
