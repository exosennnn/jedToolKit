enum BenchmarkKind { cpuSingle, cpuMulti, memory, gpu }

extension BenchmarkKindInfo on BenchmarkKind {
  String get title => switch (this) {
        BenchmarkKind.cpuSingle => 'CPU · Single-thread',
        BenchmarkKind.cpuMulti => 'CPU · Multi-thread',
        BenchmarkKind.memory => 'Memory · Copy bandwidth',
        BenchmarkKind.gpu => 'GPU · Raster workload',
      };

  String get unit => switch (this) {
        BenchmarkKind.cpuSingle || BenchmarkKind.cpuMulti => 'Mnum/s',
        BenchmarkKind.memory => 'MiB/s',
        BenchmarkKind.gpu => 'fps',
      };

  String get description => switch (this) {
        BenchmarkKind.cpuSingle => 'Prime sieve on one thread, answer verified',
        BenchmarkKind.cpuMulti => 'Same sieve on every core at once',
        BenchmarkKind.memory => 'Repeated copies of a 64 MiB buffer',
        BenchmarkKind.gpu => 'Animated blurred shapes, Flutter raster time',
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
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${kind.unit}';
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