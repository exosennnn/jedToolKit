import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../../core/jedui/jedui_components.dart';
import '../../core/settings/app_settings.dart';
import 'disk_history.dart';
import 'disk_history_screen.dart';
import '../../core/jedui/jedui_route.dart';

// MARK: - Models

enum DiskPhase { idle, writing, reading, finished }

class DiskTestResult {
  final double writeSpeedMBps;
  final double readSpeedMBps;
  const DiskTestResult(this.writeSpeedMBps, this.readSpeedMBps);
}

class DiskSpaceInfo {
  final String total;
  final String available;
  final String optimistic;
  const DiskSpaceInfo(this.total, this.available, this.optimistic);
}

// MARK: - Screen

class DiskCheckerScreen extends StatefulWidget {
  const DiskCheckerScreen({super.key});

  @override
  State<DiskCheckerScreen> createState() => _DiskCheckerScreenState();
}

class _DiskCheckerScreenState extends State<DiskCheckerScreen> {
  static const _channel = MethodChannel('com.jedplatforms.jedtoolkit/disk');
  static const _maxLogLines = 400;

  DiskPhase _phase = DiskPhase.idle;
  int _pass = 0;
  bool _running = false;
  double _progress = 0;
  double _speed = 0;
  DiskTestResult? _result;
  DiskSpaceInfo? _disk;

  // High-frequency state lives in notifiers so the whole screen doesn't rebuild.
  final List<String> _logs = [];
  final _logTick = ValueNotifier<int>(0);
  final _elapsed = ValueNotifier<String>('Time: 0.0s');
  Timer? _elapsedTimer;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onNative);
    _loadDiskInfo();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    if (_running) _channel.invokeMethod<void>('cancelDiskTest');
    _channel.setMethodCallHandler(null);
    _logTick.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  // ---- derived ----

  /// Number of filled pass dots (iOS JedPulseTestState.passCount).
  int get _passCount {
    switch (_phase) {
      case DiskPhase.idle:
        return 0;
      case DiskPhase.writing:
      case DiskPhase.reading:
        return math.max(0, _pass - 1);
      case DiskPhase.finished:
        return 3;
    }
  }

  String get _statusText {
    switch (_phase) {
      case DiskPhase.idle:
        return _running ? 'Preparing Test...' : 'Press Start to Begin';
      case DiskPhase.writing:
        return 'Testing Write Speed...';
      case DiskPhase.reading:
        return 'Testing Read Speed...';
      case DiskPhase.finished:
        return _running ? 'Finishing...' : 'Test Complete!';
    }
  }

  // ---- logging ----

  String _ts() {
    final n = DateTime.now();
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(n.hour)}:${p(n.minute)}:${p(n.second)}.${p(n.millisecond, 3)}';
  }

  void _log(String message, {bool stamp = true}) {
    _logs.add(stamp ? '[${_ts()}] $message' : message);
    if (_logs.length > _maxLogLines) {
      _logs.removeRange(0, _logs.length - _maxLogLines);
    }
    _logTick.value++;
  }

  // ---- native ----

  Future<void> _loadDiskInfo() async {
    try {
      final m = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDiskSpace',
      );
      if (m == null || !mounted) return;
      setState(() {
        _disk = DiskSpaceInfo(
          _fmtBytes((m['totalBytes'] as num).toInt()),
          _fmtBytes((m['availableBytes'] as num).toInt()),
          _fmtBytes((m['optimisticBytes'] as num).toInt()),
        );
      });
    } catch (e) {
      debugPrint('Disk space read failed: $e');
    }
  }

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _result = null;
      _progress = 0;
      _speed = 0;
      _pass = 0;
      _phase = DiskPhase.idle;
    });
    _logs.clear();
    _log('Initializing Core Diagnostic Engine...');
    final d = _disk;
    if (d != null) {
      _log(
        'System Metrics -> Capacity: ${d.total} | Free Space: ${d.available}',
      );
    }

    _startTime = DateTime.now();
    _elapsed.value = 'Time: 0.0s';
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final s = _startTime;
      if (s == null) return;
      final secs = DateTime.now().difference(s).inMilliseconds / 1000.0;
      _elapsed.value = 'Time: ${secs.toStringAsFixed(1)}s';
    });

    try {
      final started = await _channel.invokeMethod<bool>('startDiskTest');
      if (started != true) _abort();
    } on PlatformException catch (e) {
      _log('CRITICAL ERROR: ${e.message}');
      _abort();
    }
  }

  void _abort() {
    _elapsedTimer?.cancel();
    if (mounted) setState(() => _running = false);
  }

  Future<dynamic> _onNative(MethodCall call) async {
    if (call.method != 'onDiskEvent' || !mounted) return;
    final e = call.arguments as Map<dynamic, dynamic>;
    switch (e['type']) {
      case 'log':
        _log(e['message']?.toString() ?? '', stamp: false);
      case 'state':
        _onState(e);
      case 'progress':
        _onProgress(e);
      case 'complete':
        _onComplete(e);
    }
  }

  void _onState(Map<dynamic, dynamic> e) {
    final pass = (e['pass'] as num?)?.toInt() ?? 0;
    final total = (e['totalPasses'] as num?)?.toInt() ?? 3;
    final phase = switch (e['state']) {
      'writing' => DiskPhase.writing,
      'reading' => DiskPhase.reading,
      'finished' => DiskPhase.finished,
      _ => DiskPhase.idle,
    };
    setState(() {
      _phase = phase;
      _pass = pass;
    });
    switch (phase) {
      case DiskPhase.idle:
        _log('Engine state transitioned to Idle.');
      case DiskPhase.writing:
        _log('Starting Write Sequence [Pass $pass/$total]...');
      case DiskPhase.reading:
        _log('Starting Read Sequence [Pass $pass/$total]...');
      case DiskPhase.finished:
        _log('Diagnostics sequence completed safely.');
    }
  }

  void _onProgress(Map<dynamic, dynamic> e) {
    final overall = (e['overall'] as num?)?.toDouble() ?? 0;
    final speed = (e['speed'] as num?)?.toDouble() ?? 0;
    setState(() {
      _progress = overall.clamp(0.0, 1.0);
      _speed = speed;
    });
    final s = '${speed.toStringAsFixed(1)} MB/s';
    final pct = '${(overall * 100).toStringAsFixed(0)}%';
    if (_phase == DiskPhase.writing) {
      _log('I/O Write Pipeline: Status $pct @ $s');
    } else if (_phase == DiskPhase.reading) {
      _log('I/O Read Pipeline: Status $pct @ $s');
    }
  }

  void _onComplete(Map<dynamic, dynamic> e) {
    _elapsedTimer?.cancel();
    if (e['cancelled'] == true) {
      setState(() => _running = false);
      return;
    }
    if (e['success'] == true) {
      final w = (e['writeSpeedMBps'] as num).toDouble();
      final r = (e['readSpeedMBps'] as num).toDouble();
      setState(() {
        _running = false;
        _progress = 1.0;
        _result = DiskTestResult(w, r);
      });
      DiskHistoryManager.add(w, r);
      _log('--- FINAL METRICS ---');
      _log('Average Write Speed: ${w.toStringAsFixed(2)} MB/s');
      _log('Average Read Speed: ${r.toStringAsFixed(2)} MB/s');
      _log('Testing session archived into Local Database successfully.');
      _loadDiskInfo(); // free space changed
    } else {
      _log('CRITICAL ERROR: ${e['error'] ?? 'Unknown error'}');
      setState(() {
        _running = false;
        _progress = 0;
        _phase = DiskPhase.idle;
      });
    }
  }

  // ---- UI ----

  void _openHistory() {
    Navigator.of(
      context,
    ).push(JedPageRoute<void>(builder: (_) => const DiskHistoryScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the accent color changes.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final accent = AppSettings.instance.accent.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final bottom = MediaQuery.of(context).padding.bottom;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: const Text('jedDiskChecker'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _openHistory,
              child: const Icon(CupertinoIcons.clock, size: 22),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(0, 20, 0, 40 + bottom),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ---- Core diagnostics console ----
                _Section(
                  title: 'Disk Diagnostics',
                  child: _Panel(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Text(
                          _statusText,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: label,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _PassIndicator(count: _passCount, accent: accent),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 20,
                          ),
                          child: RepaintBoundary(
                            child: _PulseDial(
                              progress: _progress,
                              speed: _speed,
                              result: _result,
                              accent: accent,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Overall Progress',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: secondary,
                                ),
                              ),
                              Opacity(
                                opacity: _running ? 1 : 0,
                                child: ValueListenableBuilder<String>(
                                  valueListenable: _elapsed,
                                  builder: (_, v, __) => Text(
                                    v,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'monospace',
                                      color: secondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 0.5,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          color: CupertinoColors.separator.resolveFrom(context),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: _StartButton(
                            running: _running,
                            again: _result != null,
                            accent: accent,
                            onTap: _start,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ---- Live log ----
                _Section(
                  title: 'Live Pipeline Log',
                  child: _LogConsole(logs: _logs, tick: _logTick),
                ),
                const SizedBox(height: 32),

                // ---- Storage matrix ----
                _Section(
                  title: 'Storage Matrix',
                  child: _Panel(
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: CupertinoIcons.folder,
                          title: 'Total Capacity',
                          value: _disk?.total ?? '...',
                          divider: true,
                        ),
                        _InfoRow(
                          icon: CupertinoIcons.doc_text_search,
                          title: 'Available (Raw)',
                          value: _disk?.available ?? '...',
                          divider: true,
                        ),
                        _InfoRow(
                          icon: CupertinoIcons.sparkles,
                          title: 'Available (Optimistic)',
                          value: _disk?.optimistic ?? '...',
                          divider: false,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ---- How it works ----
                _Section(
                  title: 'Test Architecture',
                  child: _Panel(
                    child: Column(
                      children: [
                        _HowRow(
                          icon: CupertinoIcons.arrow_down_doc,
                          title: 'Write Sequence',
                          body: 'A 1 GB temporary file is written to storage to check pipeline output throughput.',
                          color: accent,
                          divider: true,
                        ),
                        _HowRow(
                          icon: CupertinoIcons.arrow_up_doc,
                          title: 'Read Sequence',
                          body: 'The written 1 GB payload dataset is fetched to process immediate block decoding speeds.',
                          color: accent,
                          divider: true,
                        ),
                        _HowRow(
                          icon: CupertinoIcons.arrow_2_circlepath,
                          title: 'Loop Analytics',
                          body: 'Performs 3 distinct sequential runs, reporting a clean mathematical average. Cache elements are purged immediately.',
                          color: accent,
                          divider: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Layout helpers

/// Section title (20 semibold) + content inset 24 on each side.
class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: child,
        ),
      ],
    );
  }
}

/// Rounded card with hairline border + soft shadow (iOS JedPulse card style).
class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _alpha(CupertinoColors.label.resolveFrom(context), 0.04),
        ),
        boxShadow: [
          BoxShadow(
            color: _alpha(CupertinoColors.black, 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// MARK: - Dial

class _PulseDial extends StatelessWidget {
  final double progress;
  final double speed;
  final DiskTestResult? result;
  final Color accent;

  const _PulseDial({
    required this.progress,
    required this.speed,
    required this.result,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final r = result;

    TextStyle mono(double size) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      fontFamily: 'monospace',
      color: label,
    );
    TextStyle cap() =>
        TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: secondary);

    return Center(
      child: SizedBox(
        width: 170,
        height: 170,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // easeOut animation of the arc, like .animation(.easeOut(0.3))
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              builder: (_, value, __) => CustomPaint(
                size: const Size(170, 170),
                painter: _DialPainter(
                  progress: value,
                  color: accent,
                  track: _alpha(label, 0.06),
                ),
              ),
            ),
            if (r != null)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('WRITE', style: cap()),
                  Text(
                    '${r.writeSpeedMBps.toStringAsFixed(1)} MB/s',
                    style: mono(16),
                  ),
                  Container(
                    width: 60,
                    height: 0.5,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  Text('READ', style: cap()),
                  Text(
                    '${r.readSpeedMBps.toStringAsFixed(1)} MB/s',
                    style: mono(16),
                  ),
                ],
              )
            else
              SizedBox(
                width: 118,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(speed.toStringAsFixed(1), style: mono(40)),
                    ),
                    Text(
                      'MB/s',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  _DialPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const w = 12.0;
    final c = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - w) / 2;

    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      -math.pi / 2,
      2 * math.pi * p,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

// MARK: - Pass dots + button

class _PassIndicator extends StatelessWidget {
  final int count;
  final Color accent;
  const _PassIndicator({required this.count, required this.accent});

  @override
  Widget build(BuildContext context) {
    final off = _alpha(CupertinoColors.label.resolveFrom(context), 0.1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            width: i < count ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i < count ? accent : off,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    );
  }
}

class _StartButton extends StatelessWidget {
  final bool running;
  final bool again;
  final Color accent;
  final VoidCallback onTap;

  const _StartButton({
    required this.running,
    required this.again,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final bg = running
        ? _alpha(CupertinoColors.label.resolveFrom(context), 0.04)
        : accent;

    return JedPressable(
      onTap: running ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (running) ...[
              const CupertinoActivityIndicator(radius: 8),
              const SizedBox(width: 8),
            ],
            Text(
              again ? 'Test Storage Again' : 'Start Speed Test',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: running
                    ? secondary
                    : AppSettings.instance.contrastingForeground(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Log console

class _LogConsole extends StatefulWidget {
  final List<String> logs;
  final ValueListenable<int> tick;
  const _LogConsole({required this.logs, required this.tick});

  @override
  State<_LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends State<_LogConsole> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _snapToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _alpha(label, 0.06)),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: widget.tick,
        builder: (_, __, ___) {
          final logs = widget.logs;
          if (logs.isEmpty) {
            return Container(
              height: 120,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Text(
                'No diagnostics running. Awaiting input execution sequence...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                  color: secondary,
                ),
              ),
            );
          }
          _snapToBottom();
          return SizedBox(
            height: 140,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  logs[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: label,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// MARK: - Rows

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool divider;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.divider,
  });

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _alpha(label, 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 17, color: secondary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: label,
                ),
              ),
            ],
          ),
        ),
        if (divider)
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(left: 72),
            color: CupertinoColors.separator.resolveFrom(context),
          ),
      ],
    );
  }
}

class _HowRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final bool divider;

  const _HowRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.divider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _alpha(color, 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (divider)
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(left: 72),
            color: CupertinoColors.separator.resolveFrom(context),
          ),
      ],
    );
  }
}

// MARK: - Utils

Color _alpha(Color c, double opacity) =>
    c.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());

/// Decimal units, like ByteCountFormatter(.file) on iOS.
String _fmtBytes(int b) {
  const gb = 1e9, tb = 1e12;
  if (b >= tb) return '${(b / tb).toStringAsFixed(2)} TB';
  return '${(b / gb).toStringAsFixed(b >= 100 * gb ? 0 : 1)} GB';
}
