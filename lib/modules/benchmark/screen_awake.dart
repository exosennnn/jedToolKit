import 'package:flutter/services.dart';

/// Keeps the screen on while a benchmark runs (see ScreenChannel.java).
class ScreenAwake {
  static const _channel = MethodChannel('jedtoolkit/screen');

  static Future<void> set(bool enabled) async {
    try {
      await _channel.invokeMethod('keepOn', {'enabled': enabled});
    } catch (_) {
      // Not on Android or channel missing: ignore.
    }
  }
}
