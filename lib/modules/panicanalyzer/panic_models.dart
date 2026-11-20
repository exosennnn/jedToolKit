enum PanicKind { javaCrash, anr, nativeCrash, unknown }

extension PanicKindInfo on PanicKind {
  String get title => switch (this) {
        PanicKind.javaCrash => 'Java / Kotlin crash',
        PanicKind.anr => 'ANR (app not responding)',
        PanicKind.nativeCrash => 'Native crash (tombstone)',
        PanicKind.unknown => 'Format not recognized',
      };
}

enum FindingLevel { info, warning, critical }

class Finding {
  final FindingLevel level;
  final String title;
  final String detail;

  const Finding(this.level, this.title, this.detail);
}

class PanicReport {
  final PanicKind kind;
  final int lineCount;
  final String? process;
  final String? pid;
  final String? headline; // exception, ANR reason, or signal
  final String? load;
  final String? mainThreadState;
  final List<String> frames; // first few frames only
  final int frameCount; // total frames found
  final List<Finding> findings;

  const PanicReport({
    required this.kind,
    required this.lineCount,
    this.process,
    this.pid,
    this.headline,
    this.load,
    this.mainThreadState,
    required this.frames,
    required this.frameCount,
    required this.findings,
  });
}

/// What the device lets this app read about its own exits.
class PanicCapabilities {
  final int sdkInt;
  final bool exitHistory;

  const PanicCapabilities({required this.sdkInt, required this.exitHistory});
}

class ExitHistory {
  final bool supported;
  final List<ExitRecord> records;

  const ExitHistory({required this.supported, required this.records});
}

/// One ApplicationExitInfo entry: why Android ended this app's process.
class ExitRecord {
  final DateTime time;
  final int pid;
  final String process;
  final int reason;
  final String reasonName;
  final int status;
  final int importance;
  final int rssKb;
  final String? description;
  final String? trace; // only ANR and native crash exits keep one

  const ExitRecord({
    required this.time,
    required this.pid,
    required this.process,
    required this.reason,
    required this.reasonName,
    required this.status,
    required this.importance,
    required this.rssKb,
    this.description,
    this.trace,
  });

  bool get hasTrace => trace != null && trace!.trim().isNotEmpty;

  factory ExitRecord.fromMap(Map<String, dynamic> m) {
    return ExitRecord(
      time: DateTime.fromMillisecondsSinceEpoch(_int(m['timestampMs'])),
      pid: _int(m['pid']),
      process: (m['process'] as String?) ?? 'unknown',
      reason: _int(m['reason']),
      reasonName: (m['reasonName'] as String?) ?? 'Unknown',
      status: _int(m['status']),
      importance: _int(m['importance']),
      rssKb: _int(m['rssKb']),
      description: _text(m['description']),
      trace: _text(m['trace']),
    );
  }
}

int _int(Object? v) => v is num ? v.toInt() : 0;

String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;