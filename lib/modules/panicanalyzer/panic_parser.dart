import 'panic_models.dart';

/// Pattern-based parser for crash logs, ANR traces and native tombstones.
/// Pure Dart with no Flutter imports, so it can be unit tested directly.
class PanicParser {
  static const _maxFrames = 12;

  static final _logcatPrefix = RegExp(r'^[VDIWEF]/[^(]+\(\s*\d+\):\s?');
  static final _javaMarker = RegExp(
      r'FATAL EXCEPTION|Exception in thread|^\s*Caused by: |^\s*at [\w$.<>/]+\(',
      multiLine: true);
  static final _anrMarker = RegExp(r'ANR in |am_anr|Application Not Responding');
  static final _nativeMarker =
      RegExp(r'signal \d+ \(SIG\w+\)|\*\*\* \*\*\* \*\*\*|backtrace:');
  static final _processHeader = RegExp(r'Process: ([\w.]+)(?:, PID: (\d+))?');
  static final _exceptionName = RegExp(
      r'([a-zA-Z_$][\w$]*(?:\.[\w$]+)+(?:Exception|Error|Throwable))(?::\s*(.*))?$');
  static final _javaFrame = RegExp(r'^at [\w$.<>/]+\(');
  static final _anrProcess = RegExp(r'ANR in ([\w.]+)');
  static final _anrReason = RegExp(r'Reason:\s*(.+)');
  static final _anrLoad = RegExp(r'Load:\s*(.+)');
  static final _threadState = RegExp(r'Thread\.State: (\w+)');
  static final _tombstoneProcess = RegExp(r'>>> (.+?) <<<');
  static final _tombstonePid = RegExp(r'pid: (\d+)');
  static final _signal = RegExp(r'signal \d+ \((SIG\w+)\)');
  static final _abortMessage = RegExp(r'Abort message: (.+)');
  static final _nativeFrame = RegExp(r'#\d{2} pc ');
  static final _processKill = RegExp(r'Killing \d+:');

  PanicReport parse(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.replaceFirst(_logcatPrefix, ''))
        .toList();
    final text = lines.join('\n');
    final extra = _generalFindings(text);
    final n = lines.length;

    if (_anrMarker.hasMatch(text)) return _parseAnr(lines, n, extra);
    if (_nativeMarker.hasMatch(text)) return _parseNative(lines, n, extra);
    if (_javaMarker.hasMatch(text)) return _parseJava(lines, n, extra);

    return PanicReport(
      kind: PanicKind.unknown,
      lineCount: n,
      frames: const [],
      frameCount: 0,
      findings: [
        const Finding(
          FindingLevel.info,
          'No known crash or ANR format found',
          'This file does not match a Java crash, ANR trace or native tombstone. '
              'Try a logcat export filtered to your app, or a bug report.',
        ),
        ...extra,
      ],
    );
  }

  // ---------- Java / Kotlin crash ----------

  PanicReport _parseJava(List<String> lines, int n, List<Finding> extra) {
    String? process;
    String? pid;
    String? exception;
    String? rootCause;
    final frames = <String>[];
    var frameCount = 0;

    for (final line in lines) {
      final t = line.trim();

      final header = _processHeader.firstMatch(t);
      if (header != null) {
        process ??= header.group(1);
        pid ??= header.group(2);
        continue;
      }
      if (t.startsWith('Caused by:')) {
        rootCause = t.substring('Caused by:'.length).trim();
        continue;
      }
      if (_javaFrame.hasMatch(t)) {
        frameCount++;
        if (frames.length < _maxFrames) frames.add(t);
        continue;
      }
      exception ??= _exceptionText(t);
    }

    final findings = <Finding>[];
    if (exception != null) findings.addAll(_javaFindings(exception));
    if (rootCause != null && rootCause != exception) {
      findings.add(Finding(FindingLevel.info, 'Root cause', rootCause));
    }
    if (frames.isNotEmpty &&
        (frames.first.startsWith('at android.') ||
            frames.first.startsWith('at com.android.'))) {
      findings.add(const Finding(
        FindingLevel.info,
        'Crash inside Android system code',
        'The top frame is inside Android framework code. Look further down the trace '
            'for the first call from your own app.',
      ));
    }
    if (findings.isEmpty) {
      findings.add(const Finding(
        FindingLevel.info,
        'Exception not recognized',
        'Look at the top app frame in the trace to find where it was thrown.',
      ));
    }
    findings.addAll(extra);

    return PanicReport(
      kind: PanicKind.javaCrash,
      lineCount: n,
      process: process,
      pid: pid,
      headline: rootCause ?? exception,
      frames: frames,
      frameCount: frameCount,
      findings: findings,
    );
  }

  String? _exceptionText(String t) {
    final m = _exceptionName.firstMatch(t);
    if (m == null) return null;
    final name = m.group(1)!;
    final msg = m.group(2);
    return (msg == null || msg.isEmpty) ? name : '$name: $msg';
  }

  List<Finding> _javaFindings(String ex) {
    if (ex.contains('OutOfMemoryError')) {
      return const [
        Finding(
          FindingLevel.critical,
          'Out of memory',
          'The app used more heap memory than it is allowed. Look for large bitmaps, '
              'growing lists or caches, and objects kept after they are needed.',
        ),
      ];
    }
    if (ex.contains('NullPointerException')) {
      return const [
        Finding(
          FindingLevel.warning,
          'Null value used as an object',
          'Code used a variable that was null. Check the top app frame and where that value is set.',
        ),
      ];
    }
    if (ex.contains('ClassCastException')) {
      return const [
        Finding(
          FindingLevel.warning,
          'Wrong type at runtime',
          'An object was used as a type it is not. Check casts and generic collections.',
        ),
      ];
    }
    if (ex.contains('NetworkOnMainThreadException')) {
      return const [
        Finding(
          FindingLevel.warning,
          'Network call on the main thread',
          'Android blocks network work on the UI thread. Move it to a background thread or coroutine.',
        ),
      ];
    }
    if (ex.contains('SecurityException')) {
      return const [
        Finding(
          FindingLevel.warning,
          'Permission or access denied',
          'A system call needed a permission or access the app does not have. '
              'Check the manifest and the runtime permission flow.',
        ),
      ];
    }
    if (ex.contains('IllegalStateException')) {
      return const [
        Finding(
          FindingLevel.info,
          'Object used in the wrong state',
          'Code called something when it was not ready, such as after a screen was closed.',
        ),
      ];
    }
    if (ex.contains('DeadObjectException') || ex.contains('RemoteException')) {
      return const [
        Finding(
          FindingLevel.info,
          'Connection to another process ended',
          'A service or another app stopped while this app was talking to it.',
        ),
      ];
    }
    return const [];
  }

  // ---------- ANR ----------

  PanicReport _parseAnr(List<String> lines, int n, List<Finding> extra) {
    String? process;
    String? reason;
    String? load;
    String? mainState;
    final mainFrames = <String>[];
    var mainFrameCount = 0;
    var inMain = false;

    for (final line in lines) {
      final t = line.trim();
      process ??= _anrProcess.firstMatch(t)?.group(1);
      reason ??= _anrReason.firstMatch(t)?.group(1);
      load ??= _anrLoad.firstMatch(t)?.group(1);

      if (line.startsWith('"main"')) {
        inMain = true;
        continue;
      }
      if (!inMain) continue;
      if (t.isEmpty || line.startsWith('"')) {
        inMain = false;
        continue;
      }
      mainState ??= _threadState.firstMatch(t)?.group(1);
      if (_javaFrame.hasMatch(t)) {
        mainFrameCount++;
        if (mainFrames.length < _maxFrames) mainFrames.add(t);
      }
    }

    final findings = <Finding>[];
    final r = reason ?? '';
    if (r.contains('Input dispatching timed out')) {
      findings.add(const Finding(
        FindingLevel.warning,
        'Main thread did not handle input in time',
        'The UI thread was busy for several seconds. The main thread state and frames show what it was doing.',
      ));
    } else if (r.isNotEmpty) {
      findings.add(Finding(FindingLevel.info, 'ANR reason', r));
    }

    if (mainState == 'BLOCKED' ||
        mainState == 'WAITING' ||
        mainState == 'TIMED_WAITING') {
      findings.add(Finding(
        FindingLevel.warning,
        'Main thread was $mainState',
        'It was waiting on a lock or another thread. Find the thread holding that lock in the full trace.',
      ));
    } else if (mainState == 'RUNNABLE') {
      findings.add(const Finding(
        FindingLevel.info,
        'Main thread was running work',
        'It was doing work when the timeout hit, not only waiting. The top frames show that work.',
      ));
    }

    if (mainState == null && mainFrames.isEmpty) {
      findings.add(const Finding(
        FindingLevel.info,
        'Main thread not found',
        'The trace has no main thread block. The file may be incomplete.',
      ));
    }
    findings.addAll(extra);

    return PanicReport(
      kind: PanicKind.anr,
      lineCount: n,
      process: process,
      headline: reason,
      load: load,
      mainThreadState: mainState,
      frames: mainFrames,
      frameCount: mainFrameCount,
      findings: findings,
    );
  }

  // ---------- Native tombstone ----------

  PanicReport _parseNative(List<String> lines, int n, List<Finding> extra) {
    String? process;
    String? pid;
    String? signal;
    String? abortMessage;
    final frames = <String>[];
    var frameCount = 0;

    for (final line in lines) {
      final t = line.trim();
      process ??= _tombstoneProcess.firstMatch(t)?.group(1)?.trim();
      pid ??= _tombstonePid.firstMatch(t)?.group(1);
      signal ??= _signal.firstMatch(t)?.group(1);
      abortMessage ??= _abortMessage.firstMatch(t)?.group(1);
      if (_nativeFrame.hasMatch(t)) {
        frameCount++;
        if (frames.length < _maxFrames) frames.add(t);
      }
    }

    final findings = <Finding>[];
    if (signal == 'SIGSEGV') {
      findings.add(const Finding(
        FindingLevel.critical,
        'Invalid memory access (SIGSEGV)',
        'Native code read or wrote memory it does not own. Common causes are a null or dangling pointer, '
            'use after free, or a buffer overflow. Check the top native frames and the library they point to.',
      ));
    } else if (signal == 'SIGABRT') {
      findings.add(const Finding(
        FindingLevel.warning,
        'Process aborted (SIGABRT)',
        'Native code or a runtime check called abort(). Read the abort message and the top frames.',
      ));
    } else if (signal == 'SIGBUS') {
      findings.add(const Finding(
        FindingLevel.warning,
        'Bus error (SIGBUS)',
        'Often a memory-mapped file that changed or was truncated, or a misaligned memory access.',
      ));
    } else if (signal == 'SIGILL' || signal == 'SIGFPE') {
      findings.add(const Finding(
        FindingLevel.warning,
        'Illegal instruction or arithmetic error',
        'Often a bug in native code, or a library built for a different CPU.',
      ));
    } else if (signal != null) {
      findings.add(Finding(
        FindingLevel.info,
        'Signal $signal',
        'The system reported this native signal. Read the top frames for the cause.',
      ));
    } else {
      findings.add(const Finding(
        FindingLevel.info,
        'Signal not found',
        'The tombstone header did not include a signal line. The file may be incomplete.',
      ));
    }

    if (abortMessage != null) {
      findings.add(Finding(FindingLevel.info, 'Abort message', abortMessage));
    }
    findings.addAll(extra);

    return PanicReport(
      kind: PanicKind.nativeCrash,
      lineCount: n,
      process: process,
      pid: pid,
      headline: signal,
      frames: frames,
      frameCount: frameCount,
      findings: findings,
    );
  }

  // ---------- Checks that apply to any format ----------

  List<Finding> _generalFindings(String text) {
    final out = <Finding>[];
    if (text.contains('lowmemorykiller') || text.contains('Low Memory Killer')) {
      out.add(const Finding(
        FindingLevel.warning,
        'Low-memory killer involved',
        'Android ended a process to free memory. This is a system action, not necessarily a bug in the app. '
            'Lower memory use or check how many apps are running.',
      ));
    }
    if (_processKill.hasMatch(text)) {
      out.add(const Finding(
        FindingLevel.info,
        'Process was killed by the system',
        'Android or the user stopped a process. This can be expected, for example after swiping the app away.',
      ));
    }
    return out;
  }
}