import 'package:flutter/services.dart';

typedef JsonMap = Map<String, dynamic>;

class HwNativeBridge {
  static const _method = MethodChannel('jedtoolkit/hwchecker');
  static const _sensors = EventChannel('jedtoolkit/hwchecker_sensors');
  static const _keys = EventChannel('jedtoolkit/hwchecker_keys');

  static Future<bool> setTorch(bool enabled) async {
    final res = await _method.invokeMethod<bool>('setTorch', {'enabled': enabled});
    return res ?? false;
  }

  static Future<bool> vibrate({int durationMs = 100, int amplitude = -1}) async {
    final res = await _method.invokeMethod<bool>('vibrate', {
      'durationMs': durationMs,
      'amplitude': amplitude,
    });
    return res ?? false;
  }

  static Future<double> getBrightness() async {
    final res = await _method.invokeMethod<double>('getBrightness');
    return res ?? 0.5;
  }

  static Future<void> setBrightness(double value) async {
    await _method.invokeMethod<void>('setBrightness', {'value': value});
  }

  static Future<JsonMap> getConnectivityStatus() async {
    final res = await _method.invokeMapMethod<String, dynamic>('getConnectivityStatus');
    return res ?? <String, dynamic>{};
  }

  static Future<JsonMap> getBatteryAndAccessories() async {
    final res = await _method.invokeMapMethod<String, dynamic>('getBatteryAndAccessories');
    return res ?? <String, dynamic>{};
  }

  static Future<void> setKeyIntercept(bool enabled) async {
    await _method.invokeMethod<void>('setKeyIntercept', {'enabled': enabled});
  }

  static Future<void> shareText(String text) async {
    await _method.invokeMethod<void>('shareText', {'text': text});
  }

  static Stream<JsonMap> sensorStream(String type) {
    return _sensors
        .receiveBroadcastStream(type)
        .map((e) => Map<String, dynamic>.from(e as Map));
  }

  static Stream<int> keyPressStream() {
    return _keys
        .receiveBroadcastStream()
        .map((e) => (e as Map)['keyCode'] as int);
  }
}