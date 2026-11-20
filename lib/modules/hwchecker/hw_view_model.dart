import 'package:flutter/foundation.dart';

import 'hw_test.dart';

/// Single source of truth for the checker UI. Port of HardwareCheckViewModel.swift.
class HwViewModel extends ChangeNotifier {
  static const _batteryInfo = 'Battery Health Info';

  final List<HwSection> sections = buildHwSections();

  Iterable<HwTest> get _scored => sections
      .expand((s) => s.tests)
      .where((t) => t.title != _batteryInfo);

  int get totalTestCount => _scored.length;

  int get completedTestCount =>
      _scored.where((t) => t.state != HwTestState.notTested).length;

  /// Passed = 1, partial (Physical Buttons) = 0.5, everything else 0.
  double get scorePercentage {
    final total = totalTestCount;
    if (total == 0) return 0;
    var score = 0.0;
    for (final t in _scored) {
      if (t.state == HwTestState.passed) score += 1;
      if (t.state == HwTestState.partial) score += 0.5;
    }
    return score / total;
  }

  void updateTestResult(String title, HwTestState state) {
    for (final s in sections) {
      for (final t in s.tests) {
        if (t.title == title) {
          t.state = state;
          notifyListeners();
          return;
        }
      }
    }
  }

  String generateShareText() {
    final b = StringBuffer('jedHWChecker Device Test Results:\n\n');
    for (final s in sections) {
      if (s.tests.isEmpty || s.title == 'Overall Status' || s.title == 'Tools') {
        continue;
      }
      b.writeln('--- ${s.title} ---');
      for (final t in s.tests) {
        final symbol = switch (t.state) {
          HwTestState.passed => '✅ Passed',
          HwTestState.failed => '❌ Failed',
          HwTestState.partial => '⚠️ Partial',
          HwTestState.notTested => '⚪️ Not Tested',
        };
        b.writeln('$symbol - ${t.title}');
      }
      b.writeln();
    }
    b.writeln('Overall Score: ${(scorePercentage * 100).toStringAsFixed(0)}%');
    return b.toString();
  }
}