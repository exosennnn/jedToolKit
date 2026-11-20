import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'benchmark_models.dart';

/// Stores benchmark runs on this device only, newest first.
class BenchmarkHistory {
  // v3: scores are now relative to the Galaxy S20 baseline. v2 runs are not comparable and are ignored.
  static const _key = 'benchmark_history_v3';
  static const _maxRuns = 50;

  Future<List<BenchmarkResult>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => BenchmarkResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(BenchmarkResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final updated = [result, ...current].take(_maxRuns).toList();
    await prefs.setString(
      _key,
      jsonEncode(updated.map((r) => r.toJson()).toList()),
    );
  }

  /// Deletes one saved result (swipe-to-delete on the History screen).
  Future<void> remove(BenchmarkResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final i = current.indexWhere(
      (r) => r.kind == result.kind && r.timestamp == result.timestamp,
    );
    if (i < 0) return;
    current.removeAt(i);
    await prefs.setString(
      _key,
      jsonEncode(current.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}