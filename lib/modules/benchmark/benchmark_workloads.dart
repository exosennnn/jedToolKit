import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Same scale as the iOS version: a device that matches the baseline scores 2500.
const double kBaselineScore = 2500;

// ------------------------------------------------------------ reference
// Every Android phone runs the SAME workload, sized for the Galaxy S20 (12 GB).
// 2500 pts therefore always means "as fast as the S20" and scores compare
// directly between phones. Baselines live in s20_baseline.dart.
// The workload tables below are indexed by this value; entries 0 and 1 are
// the old low/mid sizes and are no longer used.
int deviceTier() => 2;

/// Weighted geometric mean, same as the Swift `calculateGeometricMean`.
double weightedGeoMean(List<(double score, double weight)> items) {
  var totalWeight = 0.0;
  var logSum = 0.0;
  for (final (score, weight) in items) {
    totalWeight += weight;
    logSum += log(max(1.0, score)) * weight;
  }
  if (totalWeight <= 0) return 0;
  return exp(logSum / totalWeight);
}

// ------------------------------------------------------------------ CPU

class CpuTier {
  final int fileCompressionSize,
      assetCompressionSize,
      htmlParsingCount,
      pdfParsingCount,
      photoLibraryCount,
      clangSimCount,
      textProcessingCount,
      imageConvolutionSize,
      imagePixelSize,
      imageBlendingSize,
      imageAnalysisSize,
      objectDetectionSize,
      matrixMultiplySize,
      navigationGridSize,
      rayTracerSize;

  const CpuTier({
    required this.fileCompressionSize,
    required this.assetCompressionSize,
    required this.htmlParsingCount,
    required this.pdfParsingCount,
    required this.photoLibraryCount,
    required this.clangSimCount,
    required this.textProcessingCount,
    required this.imageConvolutionSize,
    required this.imagePixelSize,
    required this.imageBlendingSize,
    required this.imageAnalysisSize,
    required this.objectDetectionSize,
    required this.matrixMultiplySize,
    required this.navigationGridSize,
    required this.rayTracerSize,
  });
}

const _cpuTiers = <CpuTier>[
  CpuTier(
    fileCompressionSize: 36,
    assetCompressionSize: 8186572,
    htmlParsingCount: 36385,
    pdfParsingCount: 181923,
    photoLibraryCount: 113702,
    clangSimCount: 682214,
    textProcessingCount: 36385,
    imageConvolutionSize: 1378,
    imagePixelSize: 11844000,
    imageBlendingSize: 11844000,
    imageAnalysisSize: 3242,
    objectDetectionSize: 1075,
    matrixMultiplySize: 206,
    navigationGridSize: 162,
    rayTracerSize: 689,
  ),
  CpuTier(
    fileCompressionSize: 52,
    assetCompressionSize: 11695104,
    htmlParsingCount: 51979,
    pdfParsingCount: 259891,
    photoLibraryCount: 162432,
    clangSimCount: 974592,
    textProcessingCount: 51979,
    imageConvolutionSize: 1646,
    imagePixelSize: 16920000,
    imageBlendingSize: 16920000,
    imageAnalysisSize: 3870,
    objectDetectionSize: 1283,
    matrixMultiplySize: 232,
    navigationGridSize: 193,
    rayTracerSize: 823,
  ),
  CpuTier(
    fileCompressionSize: 65,
    assetCompressionSize: 14618880,
    htmlParsingCount: 64973,
    pdfParsingCount: 324863,
    photoLibraryCount: 203040,
    clangSimCount: 1218240,
    textProcessingCount: 64973,
    imageConvolutionSize: 1840,
    imagePixelSize: 21150000,
    imageBlendingSize: 21150000,
    imageAnalysisSize: 4326,
    objectDetectionSize: 1434,
    matrixMultiplySize: 255,
    navigationGridSize: 216,
    rayTracerSize: 920,
  ),
];

class CpuTask {
  final String name;
  final double baselineSec;
  final double weight;
  const CpuTask(this.name, this.baselineSec, this.weight);
}

/// Same order, baselines and weights as `createBenchmarkTasks()` in CPUBenchmark.swift.
const cpuTasks = <CpuTask>[
  CpuTask('Zipping Files', 1.2, 1.2), // 0
  CpuTask('Calculating Routes', 0.8, 0.9), // 1
  CpuTask('Web Browse Simulation', 0.5, 0.8), // 2
  CpuTask('Rendering Documents', 0.3, 0.7), // 3
  CpuTask('Sorting Photos', 0.4, 0.8), // 4
  CpuTask('Complex Data Handling', 1.2, 1.0), // 5
  CpuTask('Editing Text', 0.6, 0.8), // 6
  CpuTask('Loading Game Assets', 2.5, 1.1), // 7
  CpuTask('Recognizing Objects in Photos', 1.8, 1.0), // 8
  CpuTask('Applying Photo Effects', 1.5, 1.0), // 9
  CpuTask('Analyzing Image Content', 1.2, 0.9), // 10
  CpuTask(
    'Advanced Photo Editing',
    1.2,
    0.9,
  ), // 11 (same workload as 10, like iOS)
  CpuTask('Processing HDR Photos', 1.0, 1.0), // 12
  CpuTask('Applying Photo Filters', 0.9, 1.0), // 13
  CpuTask('3D Graphics Rendering', 2.8, 1.2), // 14
  CpuTask('Building 3D Models', 1.4, 1.1), // 15
];

/// Only workloads that real apps run multi-threaded count toward the multi-core
/// score: File Compression, Photo Library, Clang, Text Processing, Asset
/// Compression, HDR, Photo Editor and Ray Tracer, mapped to ids in [cpuTasks].
/// Order matters: it matches kS20CpuMultiBaselineSec.
const multiCoreTasks = <int>[0, 4, 5, 6, 7, 11, 12, 14];

/// Start and end of slice [slice] of [slices] over [total] items.
(int, int) _range(int total, int slice, int slices) =>
    (total * slice ~/ slices, total * (slice + 1) ~/ slices);

int _sink = 0; // keeps results "used" so nothing is optimised away

/// Runs task [id] over and over for at least [minSeconds] (and at least once)
/// and returns the MEAN seconds per run. Repeating keeps the core busy long
/// enough for clocks to ramp up and for heat to build, so a throttling phone
/// scores lower than a phone that holds its speed. Call inside an isolate.
double runCpuTaskSustained(int id, int tier, double minSeconds) {
  final clock = Stopwatch()..start();
  var runs = 0;
  var busy = 0.0;
  do {
    busy += runCpuTaskTimed(id, tier);
    runs++;
  } while (clock.elapsedMicroseconds / 1e6 < minSeconds);
  return busy / runs;
}

/// Runs one slice of a multi-threaded workload and returns seconds. The slices
/// of one workload add up to the same total work as the single-core run.
/// Meant to be called inside an isolate.
double runCpuTaskSlice(int id, int tier, int slice, int slices) {
  final c = _cpuTiers[tier];
  final sw = Stopwatch()..start();
  switch (id) {
    case 0:
      _fileCompression(c, slice, slices);
    case 4:
      _photoLibrary(c, slice, slices);
    case 5:
      _clangSimulation(c, slice, slices);
    case 6:
      _textProcessing(c, slice, slices);
    case 7:
      _assetCompression(c, slice, slices);
    case 11:
      _imageAnalysis(c, slice, slices);
    case 12:
      _imageBlending(c, slice, slices);
    case 14:
      _rayTracer(c, slice, slices);
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1e6;
}

/// Runs one CPU task and returns seconds. Meant to be called inside an isolate.
double runCpuTaskTimed(int id, int tier) {
  final c = _cpuTiers[tier];
  final sw = Stopwatch()..start();
  switch (id) {
    case 0:
      _fileCompression(c);
    case 1:
      _navigation(c);
    case 2:
      _htmlParsing(c);
    case 3:
      _pdfParsing(c);
    case 4:
      _photoLibrary(c);
    case 5:
      _clangSimulation(c);
    case 6:
      _textProcessing(c);
    case 7:
      _assetCompression(c);
    case 8:
      _objectDetection(c);
    case 9:
      _imageConvolution(c);
    case 10 || 11:
      _imageAnalysis(c);
    case 12:
      _imageBlending(c);
    case 13:
      _imagePixel(c);
    case 14:
      _rayTracer(c);
    case 15:
      _matrixMultiply(c);
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1e6;
}

void _fileCompression(CpuTier c, [int slice = 0, int slices = 1]) {
  final (s, e) = _range(1048576 * c.fileCompressionSize, slice, slices);
  final data = Uint8List(e - s)..fillRange(0, e - s, 0xAB);
  _sink += ZLibEncoder().convert(data).length;
}

// iOS uses LZMA here; dart:io only has zlib, so this uses zlib level 9.
void _assetCompression(CpuTier c, [int slice = 0, int slices = 1]) {
  final (s, e) = _range(c.assetCompressionSize, slice, slices);
  final f = Float32List(e - s);
  for (var i = 0; i < f.length; i++) {
    f[i] = (s + i).toDouble();
  }
  _sink += ZLibEncoder(level: 9).convert(f.buffer.asUint8List()).length;
}

void _htmlParsing(CpuTier c) {
  final b = StringBuffer('<html><body>');
  for (var i = 0; i < c.htmlParsingCount; i++) {
    b.write(
      "<div><p>This is a paragraph with a <a href='test.html'>link</a>.</p></div>",
    );
  }
  b.write('</body></html>');
  final html = b.toString();
  for (var i = 0; i < 20; i++) {
    _sink += html.split('</p>').length;
    _sink += html.replaceAll('is a', 'was a').length;
  }
}

void _pdfParsing(CpuTier c) {
  final text =
      'jedToolKit Benchmark Suite. Report results. Analyze data. ' *
      c.pdfParsingCount;
  for (var i = 0; i < 20; i++) {
    _sink += text.indexOf('Analyze data');
  }
}

class _Photo {
  final int id;
  final DateTime timestamp;
  final List<String> tags;
  _Photo(this.id, this.timestamp, this.tags);
}

void _photoLibrary(CpuTier c, [int slice = 0, int slices = 1]) {
  final (s, e) = _range(c.photoLibraryCount, slice, slices);
  final now = DateTime.now();
  final photos = List.generate(
    e - s,
    (i) => _Photo(s + i, now.subtract(Duration(seconds: s + i)), const [
      'test',
      'image',
    ]),
  );
  photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  _sink += photos.first.id;
}

void _clangSimulation(CpuTier c, [int slice = 0, int slices = 1]) {
  final (s, e) = _range(c.clangSimCount, slice, slices);
  final table = <String, int>{};
  for (var i = s; i < e; i++) {
    table['symbol_$i'] = i;
  }
  for (var i = s; i < e; i++) {
    _sink += table['symbol_${e - 1 - (i - s)}'] ?? 0;
  }
}

void _textProcessing(CpuTier c, [int slice = 0, int slices = 1]) {
  final (s, e) = _range(c.textProcessingCount, slice, slices);
  var text = 'The quick brown fox jumps over the lazy dog. ' * (e - s);
  for (var i = 0; i < 24; i++) {
    text = text.toUpperCase();
    text = text.toLowerCase();
  }
  _sink += text.length;
}

void _imageConvolution(CpuTier c) {
  final size = c.imageConvolutionSize;
  final image = Float32List(size * size);
  final output = Float32List(size * size);
  const kernel = [-1.0, -1.0, -1.0, -1.0, 8.0, -1.0, -1.0, -1.0, -1.0];
  for (var y = 1; y < size - 1; y++) {
    for (var x = 1; x < size - 1; x++) {
      var sum = 0.0;
      for (var ky = -1; ky <= 1; ky++) {
        for (var kx = -1; kx <= 1; kx++) {
          sum +=
              image[(y + ky) * size + (x + kx)] *
              kernel[(ky + 1) * 3 + (kx + 1)];
        }
      }
      output[y * size + x] = sum;
    }
  }
  _sink += output.length;
}

void _imagePixel(CpuTier c) {
  final size = c.imagePixelSize;
  final pixels = Float32List(size);
  for (var i = 0; i < size; i++) {
    pixels[i] = (i % 255) / 255.0;
  }
  for (var i = 0; i < size; i++) {
    pixels[i] = pow(pixels[i], 1.5).toDouble();
  }
  _sink += pixels.length;
}

void _imageBlending(CpuTier c, [int slice = 0, int slices = 1]) {
  final (s, e) = _range(c.imageBlendingSize, slice, slices);
  final size = e - s;
  final a = Float32List(size);
  final b = Float32List(size);
  final out = Float32List(size);
  for (var i = 0; i < size; i++) {
    a[i] = ((s + i) % 255) / 255.0;
    b[i] = (255 - ((s + i) % 255)) / 255.0;
  }
  for (var i = 0; i < size; i++) {
    out[i] = (a[i] + b[i]) / 2.0;
  }
  _sink += out.length;
}

void _imageAnalysis(CpuTier c, [int slice = 0, int slices = 1]) {
  final size = c.imageAnalysisSize;
  final (y0, y1) = _range(size, slice, slices);
  final rows = y1 - y0;
  final image = Float32List(rows * size);
  for (var i = 0; i < image.length; i++) {
    image[i] = ((y0 * size + i) % 255).toDouble();
  }
  final rowSums = Float32List(rows);
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < size; x++) {
      rowSums[y] += image[y * size + x];
    }
  }
  _sink += rowSums.length;
}

void _objectDetection(CpuTier c) {
  final size = c.objectDetectionSize;
  const window = 16;
  final image = Float32List(size * size);
  for (var i = 0; i < image.length; i++) {
    image[i] = (i % 255).toDouble();
  }
  var best = 0.0;
  for (var y = 0; y < size - window; y++) {
    for (var x = 0; x < size - window; x++) {
      var sum = 0.0;
      for (var wy = 0; wy < window; wy++) {
        for (var wx = 0; wx < window; wx++) {
          sum += image[(y + wy) * size + (x + wx)];
        }
      }
      if (sum > best) best = sum;
    }
  }
  _sink += best.toInt();
}

void _matrixMultiply(CpuTier c) {
  final n = c.matrixMultiplySize;
  final a = List.generate(
    n,
    (i) => Int64List.fromList(List.generate(n, (j) => i + j)),
  );
  final b = List.generate(
    n,
    (i) => Int64List.fromList(List.generate(n, (j) => i - j)),
  );
  final m = List.generate(n, (_) => Int64List(n));
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      for (var k = 0; k < n; k++) {
        m[i][j] += a[i][k] * b[k][j];
      }
    }
  }
  _sink += m[n - 1][n - 1];
}

void _navigation(CpuTier c) {
  final n = c.navigationGridSize;
  final gScore = List.generate(n, (_) => List<int>.filled(n, 1 << 60));
  gScore[0][0] = 0;
  final open = <(int, int)>[(0, 0)];
  final cameFrom = <String, (int, int)>{};
  const dirs = [(0, 1), (0, -1), (1, 0), (-1, 0)];
  while (open.isNotEmpty) {
    final cur = open.removeAt(0);
    if (cur.$1 == n - 1 && cur.$2 == n - 1) break;
    for (final d in dirs) {
      final nx = cur.$1 + d.$1;
      final ny = cur.$2 + d.$2;
      if (nx >= 0 && nx < n && ny >= 0 && ny < n) {
        final t = gScore[cur.$2][cur.$1] + 1;
        if (t < gScore[ny][nx]) {
          cameFrom['$nx,$ny'] = cur;
          gScore[ny][nx] = t;
          if (!open.any((o) => o.$1 == nx && o.$2 == ny)) open.add((nx, ny));
        }
      }
    }
  }
  _sink += cameFrom.length;
}

void _rayTracer(CpuTier c, [int slice = 0, int slices = 1]) {
  const radii = [1.0, 0.5];
  final size = c.rayTracerSize;
  final (y0, y1) = _range(size, slice, slices);
  final tanHalf = tan(pi / 4);
  var hits = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = 0; x < size; x++) {
      final px = (2 * (x + 0.5) / size - 1) * tanHalf;
      final py = -(2 * (y + 0.5) / size - 1) * tanHalf;
      final a = px * px + py * py + 1;
      for (final r in radii) {
        final cc = -r * r;
        if (-4 * a * cc >= 0) {
          hits++;
          break;
        }
      }
    }
  }
  _sink += hits;
}

// --------------------------------------------------------------- memory

class MemoryTier {
  final int sizeMB;
  final double writeBandwidth, readBandwidth, randomBandwidth; // MB/s baselines
  const MemoryTier(
    this.sizeMB,
    this.writeBandwidth,
    this.readBandwidth,
    this.randomBandwidth,
  );
}

const memoryTiers = <MemoryTier>[
  MemoryTier(50, 600, 500, 90),
  MemoryTier(100, 1000, 900, 150),
  MemoryTier(200, 2800, 2500, 400),
];

const memWriteWeight = 0.3, memReadWeight = 0.3, memRandomWeight = 0.4;

/// One iteration. Returns [writeSec, readSec, randomSec]. Run inside an isolate.
List<double> memoryIteration(int sizeMB) {
  final elements = (sizeMB * 1024 * 1024) ~/ 8; // 8 bytes per Int, like Swift
  final rng = Random(42);

  // Sequential write
  var arr = Int64List(elements);
  var sw = Stopwatch()..start();
  for (var i = 0; i < elements; i++) {
    arr[i] = i;
  }
  sw.stop();
  final writeSec = sw.elapsedMicroseconds / 1e6;

  // Sequential read (array already filled by the write pass)
  var sum = 0;
  sw = Stopwatch()..start();
  for (var i = 0; i < elements; i++) {
    sum += arr[i];
  }
  sw.stop();
  final readSec = sw.elapsedMicroseconds / 1e6;

  // Random access: elements / 10 reads
  final loops = elements ~/ 10;
  sw = Stopwatch()..start();
  for (var i = 0; i < loops; i++) {
    sum += arr[rng.nextInt(elements)];
  }
  sw.stop();
  final randomSec = sw.elapsedMicroseconds / 1e6;

  _sink += sum;
  return [writeSec, readSec, randomSec];
}
