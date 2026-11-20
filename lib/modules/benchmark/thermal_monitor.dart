import 'package:flutter/services.dart';

import 'benchmark_config.dart';

/// Battery temperature and Android's own thermal status, read through
/// ThermalChannel.java. Used to show how hot the test made the phone and to
/// stop the test before the phone gets dangerously hot.
class ThermalReading {
  final double? batteryC;
  final int status; // 0 none ... 6 shutdown, -1 unknown
  final double? headroom; // Android 11+, 1.0 = at the throttling limit

  const ThermalReading(this.batteryC, this.status, this.headroom);

  String get statusName => switch (status) {
    0 => 'None',
    1 => 'Light',
    2 => 'Moderate',
    3 => 'Severe',
    4 => 'Critical',
    5 => 'Emergency',
    6 => 'Shutdown',
    _ => 'Unknown',
  };
}

class ThermalMonitor {
  static const _channel = MethodChannel('jedtoolkit/thermal');

  static Future<ThermalReading> read() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('read');
      if (m == null) return const ThermalReading(null, -1, null);
      return ThermalReading(
        (m['batteryC'] as num?)?.toDouble(),
        (m['status'] as num?)?.toInt() ?? -1,
        (m['headroom'] as num?)?.toDouble(),
      );
    } catch (_) {
      return const ThermalReading(null, -1, null);
    }
  }

  /// Why the test must stop now, or null when it is fine to continue.
  static String? unsafeReason(ThermalReading r) {
    if (r.status >= kThermalStopStatus) {
      return 'Android reports ${r.statusName.toLowerCase()} thermal throttling';
    }
    final t = r.batteryC;
    if (t != null && t >= kThermalStopBatteryC) {
      return 'battery temperature reached ${t.toStringAsFixed(1)} \u00B0C';
    }
    return null;
  }

  static String describe(ThermalReading? a, ThermalReading? b) {
    final t0 = a?.batteryC, t1 = b?.batteryC;
    if (t0 == null || t1 == null) return 'Unavailable on this phone';
    final d = t1 - t0;
    final status = b!.status >= 0
        ? ' \u00B7 thermal status: ${b.statusName}'
        : '';
    return '${t0.toStringAsFixed(1)} \u00B0C \u2192 ${t1.toStringAsFixed(1)} \u00B0C '
        '(${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)})$status';
  }
}
