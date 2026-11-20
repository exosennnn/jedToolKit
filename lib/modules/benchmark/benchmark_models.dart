enum BenchmarkKind { cpuSingle, cpuMulti, memory, gpu }

extension BenchmarkKindInfo on BenchmarkKind {
  String get title => switch (this) {
    BenchmarkKind.cpuSingle => 'CPU · Single-core',
    BenchmarkKind.cpuMulti => 'CPU · Multi-core',
    BenchmarkKind.memory => 'Memory · Bandwidth',
    BenchmarkKind.gpu => 'GPU · Raster + GL ES + OpenCL',
  };

  /// Every test now reports a jedBenchmark score (2500 = baseline device).
  String get unit => 'pts';

  String get description => switch (this) {
    BenchmarkKind.cpuSingle => '16 real-world tasks, one at a time',
    BenchmarkKind.cpuMulti =>
      'The 8 Geekbench 7 multi-core workloads, split across all cores',
    BenchmarkKind.memory => 'Sequential write, read and random access',
    BenchmarkKind.gpu => '7 raster scenes plus OpenGL ES and OpenCL compute',
  };
}

class BenchmarkResult {
  final BenchmarkKind kind;
  final DateTime timestamp;
  final bool ok;
  final double? value;
  final Map<String, String> details;
  final String? error;

  const BenchmarkResult({
    required this.kind,
    required this.timestamp,
    required this.ok,
    this.value,
    this.details = const {},
    this.error,
  });

  factory BenchmarkResult.failed(BenchmarkKind kind, String message) =>
      BenchmarkResult(
        kind: kind,
        timestamp: DateTime.now(),
        ok: false,
        error: message,
      );

  String get valueText {
    if (!ok) return 'Failed';
    final v = value;
    if (v == null) return '—';
    return '${v.round()} ${kind.unit}';
  }

  String get detailText {
    final lines = <String>[valueText];
    details.forEach((k, v) => lines.add('$k: $v'));
    if (error != null) lines.add('Error: $error');
    return lines.join('\n');
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'timestamp': timestamp.toIso8601String(),
    'ok': ok,
    'value': value,
    'details': details,
    'error': error,
  };

  factory BenchmarkResult.fromJson(Map<String, dynamic> j) => BenchmarkResult(
    kind: BenchmarkKind.values.byName(j['kind'] as String),
    timestamp: DateTime.parse(j['timestamp'] as String),
    ok: j['ok'] as bool,
    value: (j['value'] as num?)?.toDouble(),
    details: Map<String, String>.from(j['details'] as Map),
    error: j['error'] as String?,
  );
}
