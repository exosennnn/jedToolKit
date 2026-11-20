import 'package:flutter/services.dart';

class HwMediaBridge {
  static const _method = MethodChannel('jedtoolkit/hwchecker_media');
  static const _micStream = EventChannel('jedtoolkit/hwchecker_mic_level');

  static Future<void> startSpeakerTone() => _method.invokeMethod<void>('startSpeakerTone');
  static Future<void> stopSpeakerTone() => _method.invokeMethod<void>('stopSpeakerTone');

  static Future<bool> startMicRecord() async {
    final res = await _method.invokeMethod<bool>('startMicRecord');
    return res ?? false;
  }

  static Future<void> stopMicRecord() => _method.invokeMethod<void>('stopMicRecord');

  static Future<bool> playMicRecording() async {
    final res = await _method.invokeMethod<bool>('playMicRecording');
    return res ?? false;
  }

  static Future<void> stopMicPlayback() => _method.invokeMethod<void>('stopMicPlayback');

  static Future<bool> authenticateBiometric() async {
    final res = await _method.invokeMethod<bool>('authenticateBiometric');
    return res ?? false;
  }

  static Future<bool> requestCameraPermission() async {
    final res = await _method.invokeMethod<bool>('requestCameraPermission');
    return res ?? false;
  }

  static Stream<Map<String, dynamic>> micEvents() {
    return _micStream
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
  }
}