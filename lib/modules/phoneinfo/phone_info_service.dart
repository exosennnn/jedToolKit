import 'package:flutter/services.dart';
import 'phone_info.dart';

class PhoneInfoService {
  static const _channel = MethodChannel('com.jedplatforms.jedtoolkit/phoneinfo');

  Future<List<InfoSection>> load() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('getDeviceInfo');
      if (raw == null || raw.isEmpty) {
        return _error('No data returned from Android.');
      }
      return raw
          .map((s) => _section(Map<String, dynamic>.from(s as Map)))
          .toList();
    } on MissingPluginException {
      return _error('Native bridge not registered. Check MainActivity.java.');
    } on PlatformException catch (e) {
      return _error(e.message ?? 'Platform error while reading device info.');
    }
  }

  InfoSection _section(Map<String, dynamic> s) => InfoSection(
        title: s['title'] as String,
        fields: (s['fields'] as List)
            .map((f) => _field(Map<String, dynamic>.from(f as Map)))
            .toList(),
      );

  InfoField _field(Map<String, dynamic> f) => InfoField(
        label: f['label'] as String,
        value: f['value'] as String?,
        status: _status(f['status'] as String?),
        note: f['note'] as String?,
      );

  DataStatus _status(String? s) => switch (s) {
        'AVAILABLE' => DataStatus.available,
        'RESTRICTED' => DataStatus.restricted,
        'ERROR' => DataStatus.error,
        _ => DataStatus.unsupported,
      };

  List<InfoSection> _error(String message) => [
        InfoSection(title: 'Device', fields: [
          InfoField(label: 'Status', value: message, status: DataStatus.error),
        ]),
      ];
}