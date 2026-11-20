import 'package:flutter/services.dart';

import 'panic_models.dart';

/// Dart side of PanicAnalyzerChannel.java (channel: com.jedplatforms.jedtoolkit/panic).
class PanicChannel {
  static const _channel = MethodChannel('com.jedplatforms.jedtoolkit/panic');

  static Future<PanicCapabilities> capabilities() async {
    final m = await _channel.invokeMapMethod<String, dynamic>('getCapabilities') ??
        const <String, dynamic>{};
    return PanicCapabilities(
      sdkInt: (m['sdkInt'] as num?)?.toInt() ?? 0,
      exitHistory: m['exitHistory'] == true,
    );
  }

  static Future<ExitHistory> exitHistory({bool includeTraces = true}) async {
    final m = await _channel.invokeMapMethod<String, dynamic>(
          'getExitHistory',
          {'includeTraces': includeTraces},
        ) ??
        const <String, dynamic>{};
    final raw = (m['records'] as List?) ?? const [];
    return ExitHistory(
      supported: m['supported'] == true,
      records: [
        for (final e in raw) ExitRecord.fromMap(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }

  static Future<String> logcat() async =>
      await _channel.invokeMethod<String>('getLogcat') ?? '';
}