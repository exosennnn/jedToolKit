import 'dart:io';

import 'package:flutter/services.dart';

/// Real hardware names for the Benchmark header.
/// CPU: SoC model from Android (Build.SOC_MODEL / board codename), mapped to
/// the retail name when known, plus the core layout read from sysfs.
/// GPU: the OpenGL ES renderer string from a native EGL context.
class DeviceSpecs {
  final String model;
  final String cpuName;
  final String cpuLayout;
  final String gpuName;

  const DeviceSpecs({
    required this.model,
    required this.cpuName,
    required this.cpuLayout,
    required this.gpuName,
  });
}

class DeviceSpecsService {
  static const _channel = MethodChannel('jedtoolkit/device_specs');

  static Future<DeviceSpecs> load() async {
    Map<String, dynamic> native = {};
    try {
      native =
          await _channel.invokeMapMethod<String, dynamic>('getSpecs') ?? {};
    } catch (_) {
      // Channel not registered yet or not on Android: fall back to what Dart can read.
    }

    String s(String key) => (native[key] as String?)?.trim() ?? '';

    final manufacturer = s('manufacturer');
    final model = s('model');
    final deviceName = model.isEmpty
        ? 'This device'
        : (model.toLowerCase().startsWith(manufacturer.toLowerCase())
                  ? model
                  : '${_cap(manufacturer)} $model')
              .trim();

    final gpu = s('gpuRenderer');

    return DeviceSpecs(
      model: deviceName,
      cpuName: _cpuName(native),
      cpuLayout: _coreLayout(),
      gpuName: gpu.isEmpty ? 'Unavailable' : gpu,
    );
  }

  static String _cap(String v) =>
      v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

  static String _cpuName(Map<String, dynamic> native) {
    String s(String key) => (native[key] as String?)?.trim() ?? '';
    bool useful(String v) =>
        v.isNotEmpty &&
        v.toLowerCase() != 'unknown' &&
        v.toLowerCase() != 'qcom';

    final socModel = s('socModel');
    final socMaker = s('socManufacturer');

    // 1. SoC model (Android 12+), e.g. SM8550 -> Snapdragon 8 Gen 2
    final byModel =
        _socNames[socModel.toUpperCase()] ?? _socNames[socModel.toLowerCase()];
    if (byModel != null) return byModel;

    // 2. Board / hardware codename, e.g. kalama -> Snapdragon 8 Gen 2
    for (final k in [s('board'), s('hardware')]) {
      final hit = _socNames[k.toLowerCase()];
      if (hit != null) return hit;
    }

    // 3. Unmapped but real SoC model: show it as-is
    if (useful(socModel)) {
      return socMaker.isNotEmpty &&
              !socModel.toLowerCase().contains(socMaker.toLowerCase())
          ? '$socMaker $socModel'
          : socModel;
    }

    // 4. /proc/cpuinfo "Hardware" line (older devices)
    try {
      final info = File('/proc/cpuinfo').readAsStringSync();
      final m = RegExp(
        r'^Hardware\s*:\s*(.+)$',
        multiLine: true,
      ).firstMatch(info);
      final hw = m?.group(1)?.trim() ?? '';
      if (useful(hw)) return hw;
    } catch (_) {}

    // 5. Whatever Build.HARDWARE / BOARD say
    for (final k in [s('hardware'), s('board')]) {
      if (useful(k)) return k;
    }
    return 'Unknown processor';
  }

  /// "1× 3.36 GHz · 3× 2.80 GHz · 4× 2.00 GHz" from each core's max frequency.
  static String _coreLayout() {
    final n = Platform.numberOfProcessors;
    final counts = <int, int>{};
    try {
      for (var i = 0; i < n; i++) {
        final f = File('/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq')
            .readAsStringSync()
            .trim();
        final khz = int.tryParse(f);
        if (khz != null) counts[khz] = (counts[khz] ?? 0) + 1;
      }
    } catch (_) {}
    if (counts.isEmpty) return '$n cores';
    final freqs = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    final parts = [
      for (final f in freqs)
        '${counts[f]}× ${(f / 1e6).toStringAsFixed(2)} GHz',
    ];
    return '$n cores · ${parts.join(' · ')}';
  }

  // Best-effort retail names. Keys: upper-case SoC model, or lower-case board codename.
  static const _socNames = <String, String>{
    // Qualcomm (SoC model)
    'SM8750': 'Snapdragon 8 Elite',
    'SM8650': 'Snapdragon 8 Gen 3',
    'SM8550': 'Snapdragon 8 Gen 2',
    'SM8475': 'Snapdragon 8+ Gen 1',
    'SM8450': 'Snapdragon 8 Gen 1',
    'SM8350': 'Snapdragon 888',
    'SM8250': 'Snapdragon 865',
    'SM8150': 'Snapdragon 855',
    'SM7450': 'Snapdragon 7 Gen 1',
    'SM7325': 'Snapdragon 778G',
    'SM6375': 'Snapdragon 695',
    'SM6225': 'Snapdragon 680',
    'SM6115': 'Snapdragon 662',
    // Qualcomm (board codename)
    'sun': 'Snapdragon 8 Elite',
    'pineapple': 'Snapdragon 8 Gen 3',
    'kalama': 'Snapdragon 8 Gen 2',
    'taro': 'Snapdragon 8 Gen 1',
    'lahaina': 'Snapdragon 888',
    'kona': 'Snapdragon 865',
    'msmnile': 'Snapdragon 855',
    // MediaTek
    'MT6989': 'Dimensity 9300',
    'MT6985': 'Dimensity 9200',
    'MT6983': 'Dimensity 9000',
    'MT6895': 'Dimensity 8100',
    'MT6893': 'Dimensity 1200',
    // Google Tensor
    'GS101': 'Google Tensor',
    'GS201': 'Google Tensor G2',
    'zuma': 'Google Tensor G3',
    'zumapro': 'Google Tensor G4',
    'TENSOR G3': 'Google Tensor G3',
    'TENSOR G4': 'Google Tensor G4',
  };
}
