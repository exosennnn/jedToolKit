import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One saved disk test (port of JedPulseHistoryEntry).
class DiskHistoryEntry {
  final DateTime date;
  final double writeSpeedMBps;
  final double readSpeedMBps;

  const DiskHistoryEntry({
    required this.date,
    required this.writeSpeedMBps,
    required this.readSpeedMBps,
  });

  String get detailedDescription =>
      'Disk Speed Test Result:\n'
      '---------------------------------\n'
      'Write Speed: ${writeSpeedMBps.toStringAsFixed(2)} MB/s\n'
      'Read Speed:  ${readSpeedMBps.toStringAsFixed(2)} MB/s\n'
      '---------------------------------';

  Map<String, dynamic> toJson() => {
    'date': date.millisecondsSinceEpoch,
    'write': writeSpeedMBps,
    'read': readSpeedMBps,
  };

  factory DiskHistoryEntry.fromJson(Map<String, dynamic> j) => DiskHistoryEntry(
    date: DateTime.fromMillisecondsSinceEpoch((j['date'] as num).toInt()),
    writeSpeedMBps: (j['write'] as num).toDouble(),
    readSpeedMBps: (j['read'] as num).toDouble(),
  );
}

/// Saves / loads test history with SharedPreferences (UserDefaults on iOS).
class DiskHistoryManager {
  DiskHistoryManager._();

  static const _key = 'jedPulseTestHistory';

  /// Newest first.
  static Future<List<DiskHistoryEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => DiskHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<DiskHistoryEntry> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> add(double writeMBps, double readMBps) async {
    final list = await load();
    list.insert(
      0,
      DiskHistoryEntry(
        date: DateTime.now(),
        writeSpeedMBps: writeMBps,
        readSpeedMBps: readMBps,
      ),
    );
    await _write(list);
  }

  static Future<void> deleteAt(int index) async {
    final list = await load();
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _write(list);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
