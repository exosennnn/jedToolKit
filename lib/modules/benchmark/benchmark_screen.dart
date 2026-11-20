import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../core/jedui/jedui_components.dart';
import '../../core/jedui/jedui_dock.dart';
import 'benchmark_history.dart';
import 'benchmark_history_screen.dart';
import 'device_specs.dart';
import 'benchmark_models.dart';
import 'benchmark_runners.dart';
import 'screen_awake.dart';
import 'gpu_benchmark_screen.dart';
import '../../core/jedui/jedui_route.dart';

/// Layout mirrors the iOS jedBenchmark screen:
/// device card -> Performance Tracker -> Summary -> How It Works.
class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final _history = BenchmarkHistory();
  final _cpu = CpuRunner();
  final _memory = MemoryRunner();

  List<BenchmarkResult> _runs = [];
  final Map<BenchmarkKind, BenchmarkResult> _session = {};
  DeviceSpecs? _specs;

  bool _busy = false;
  bool _cancelRequested = false;
  BenchmarkKind? _current;
  int _kindIndex = 0;
  int _kindTotal = 1;
  double _kindProgress = 0;
  String _overallText = 'Ready to start benchmark';

  Timer? _ticker;
  int _elapsedSeconds = 0;

  static const _disclaimer =
      'Results depend on temperature, battery level, background apps and power mode. '
      'Scores only compare within the same device, not against other benchmark apps.';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    DeviceSpecsService.load().then((v) {
      if (mounted) setState(() => _specs = v);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    ScreenAwake.set(false); // safety net if the user leaves mid-run
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final runs = await _history.load();
    if (mounted) setState(() => _runs = runs);
  }

  BenchmarkResult? _latest(BenchmarkKind kind) {
    for (final r in _runs) {
      if (r.kind == kind) return r;
    }
    return null;
  }

  /// iOS shows "—" until a test runs in this visit (history lives on its own
  /// screen). Set to true to show the last saved score in the rows instead.
  static const _showSavedScores = false;

  /// Score shown in a row: this session's result (optionally the last saved one).
  BenchmarkResult? _shown(BenchmarkKind kind) =>
      _session[kind] ??
      (_busy || !_showSavedScores ? null : _latest(kind));

  String _status(BenchmarkKind kind) {
    if (_busy &&
        (_current == kind ||
            (_current == BenchmarkKind.cpuSingle &&
                kind == BenchmarkKind.cpuMulti))) {
      return 'Running';
    }
    final r = _session[kind];
    if (r == null) return 'Waiting';
    return r.ok ? 'Completed' : 'Failed';
  }

  double get _overallProgress =>
      ((_kindIndex + _kindProgress) / _kindTotal).clamp(0.0, 1.0).toDouble();

  String get _elapsedText {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(_elapsedSeconds ~/ 60)}:${two(_elapsedSeconds % 60)}';
  }

  // ---------------------------------------------------------------- running

  Future<List<BenchmarkResult>?> _execute(BenchmarkKind kind) async {
    if (kind == BenchmarkKind.gpu) {
      setState(() => _overallText = 'Running Graphics Benchmark...');
      final r = await Navigator.of(context).push<BenchmarkResult>(
        JedPageRoute(builder: (_) => const GpuBenchmarkScreen()),
      );
      return r == null ? null : [r];
    }

    void onProgress(double p, String s) {
      if (!mounted) return;
      setState(() {
        _kindProgress = p;
        _overallText = s;
      });
    }

    bool isCancelled() => _cancelRequested;

    if (kind == BenchmarkKind.memory) {
      final r = await _memory.run(
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      return r == null ? null : [r];
    }
    // cpuSingle and cpuMulti come from one combined run
    return _cpu.run(onProgress: onProgress, isCancelled: isCancelled);
  }

  Future<void> _run(List<BenchmarkKind> kinds) async {
    if (_busy) return;
    // CPU single + multi are one stage
    final stages = <BenchmarkKind>[];
    for (final k in kinds) {
      final st = k == BenchmarkKind.cpuMulti ? BenchmarkKind.cpuSingle : k;
      if (!stages.contains(st)) stages.add(st);
    }
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _session.clear();
      _kindTotal = stages.length;
      _kindIndex = 0;
      _kindProgress = 0;
      _elapsedSeconds = 0;
      _overallText = 'Starting';
    });
    await ScreenAwake.set(true); // keep the screen on while the test runs
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });

    try {
      for (var i = 0; i < stages.length; i++) {
        if (_cancelRequested || !mounted) break;
        setState(() {
          _current = stages[i];
          _kindIndex = i;
          _kindProgress = 0;
        });
        final results = await _execute(stages[i]);
        if (results != null) {
          for (final r in results) {
            _session[r.kind] = r;
            await _history.add(r);
          }
        }
      }
    } finally {
      await ScreenAwake.set(false); // always release, even on error or stop
    }

    _ticker?.cancel();
    final runs = await _history.load();
    if (!mounted) return;
    final stopped = _cancelRequested;
    setState(() {
      _busy = false;
      _current = null;
      _runs = runs;
      if (!stopped) _kindIndex = _kindTotal;
      _kindProgress = 0;
      _overallText = stopped ? 'Stopped' : 'All benchmarks completed!';
    });
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      JedPageRoute<void>(builder: (_) => const BenchmarkHistoryScreen()),
    );
    _loadHistory(); // a swipe-delete there may have changed the list
  }

  // ----------------------------------------------------------------- styling

  Color _primary(BuildContext c) => CupertinoColors.label.resolveFrom(c);
  Color _secondary(BuildContext c) =>
      CupertinoColors.secondaryLabel.resolveFrom(c);

  /// iOS `secondarySystemGroupedBackground` card: radius 20, hairline stroke, soft shadow.
  Widget _card(BuildContext context, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _primary(context).withOpacity(0.04)),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: _primary(context),
      ),
    ),
  );

  Widget _divider(BuildContext context, double left, [double right = 0]) =>
      Container(
    height: 0.5,
    margin: EdgeInsets.only(left: left, right: right),
    color: _primary(context).withOpacity(0.05),
  );

  // -------------------------------------------------------------- components

  Widget _deviceCard(BuildContext context) {
    final sp = _specs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HARDWARE SPECIFICATIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: _secondary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sp?.model ?? 'This device',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _primary(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _card(
          context,
          Column(
            children: [
              _infoRow(
                context,
                CupertinoIcons.waveform_path_ecg,
                'Processor Architecture',
                sp == null ? 'Detecting…' : '${sp.cpuName}\n${sp.cpuLayout}',
              ),
              _divider(context, 72),
              _infoRow(
                context,
                CupertinoIcons.sparkles,
                'Graphics Core / Hardware',
                sp?.gpuName ?? 'Detecting…',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String? title,
    String text,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _primary(context).withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 16, color: _secondary(context)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _primary(context),
                      ),
                    ),
                  ),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _secondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreBox(BuildContext context, String title, BenchmarkResult? r) {
    final failed = r != null && !r.ok;
    final text = r == null
        ? '—'
        : !r.ok
        ? 'Fail'
        : (r.value == null ? '—' : r.value!.round().toString());
    return Container(
      constraints: const BoxConstraints(minWidth: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _primary(context).withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: 'Menlo',
              fontFamilyFallback: const ['monospace'],
              color: failed
                  ? CupertinoColors.systemRed.resolveFrom(context)
                  : _primary(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: _secondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _benchRow(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String status,
    required Widget content,
    VoidCallback? onTap,
  }) {
    final accent = CupertinoDynamicColor.resolve(
      CupertinoColors.systemBlue,
      context,
    );
    return JedPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _primary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _secondary(context),
                    ),
                  ),
                ],
              ),
            ),
            content,
          ],
        ),
      ),
    );
  }

  Widget _capsule(
    BuildContext context, {
    required String label,
    required VoidCallback? onTap,
    required Color fg,
    required Color bg,
  }) {
    return Expanded(
      child: JedPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _trackerCard(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(
      CupertinoColors.systemBlue,
      context,
    );
    final red = CupertinoColors.systemRed.resolveFrom(context);
    final idleBg = _primary(context).withOpacity(0.04);

    // CPU row status: running if either CPU test runs, else combine.
    String cpuStatus() {
      final a = _status(BenchmarkKind.cpuSingle);
      final b = _status(BenchmarkKind.cpuMulti);
      if (a == 'Running' || b == 'Running') return 'Running';
      if (a == 'Completed' && b == 'Completed') return 'Completed';
      if (a == 'Failed' || b == 'Failed') return 'Failed';
      if (a == 'Completed' || b == 'Completed') return 'Partial';
      return 'Waiting';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'Performance Tracker'),
        const SizedBox(height: 12),
        _card(
          context,
          Column(
            children: [
              _benchRow(
                context,
                title: 'CPU Performance',
                icon: CupertinoIcons.speedometer,
                status: cpuStatus(),
                onTap: _busy
                    ? null
                    : () => _run([
                        BenchmarkKind.cpuSingle,
                        BenchmarkKind.cpuMulti,
                      ]),
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _scoreBox(context, 'Sngl', _shown(BenchmarkKind.cpuSingle)),
                    const SizedBox(width: 8),
                    _scoreBox(context, 'Mlti', _shown(BenchmarkKind.cpuMulti)),
                  ],
                ),
              ),
              _divider(context, 64),
              _benchRow(
                context,
                title: 'System RAM',
                icon: CupertinoIcons.arrow_up_arrow_down_square,
                status: _status(BenchmarkKind.memory),
                onTap: _busy ? null : () => _run([BenchmarkKind.memory]),
                content: _scoreBox(
                  context,
                  'Score',
                  _shown(BenchmarkKind.memory),
                ),
              ),
              _divider(context, 64),
              _benchRow(
                context,
                title: 'GPU Raster',
                icon: CupertinoIcons.desktopcomputer,
                status: _status(BenchmarkKind.gpu),
                onTap: _busy ? null : () => _run([BenchmarkKind.gpu]),
                content: _scoreBox(context, 'Score', _shown(BenchmarkKind.gpu)),
              ),
              // Overall progress + timer
              Container(
                color: _primary(context).withOpacity(0.01),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      height: 4,
                      width: double.infinity,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemFill.resolveFrom(
                          context,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: _overallProgress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _overallText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _secondary(context),
                            ),
                          ),
                        ),
                        Text(
                          _elapsedText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Menlo',
                            fontFamilyFallback: const ['monospace'],
                            color: _secondary(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _divider(context, 16, 16), // .padding(.horizontal, 16)
              // Stop / Start
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _capsule(
                      context,
                      label: 'Stop',
                      onTap: _busy
                          ? () => setState(() => _cancelRequested = true)
                          : null,
                      fg: _busy ? red : _secondary(context),
                      bg: _busy ? red.withOpacity(0.08) : idleBg,
                    ),
                    const SizedBox(width: 16),
                    _capsule(
                      context,
                      label: 'Start Benchmark',
                      onTap: _busy ? null : () => _run(BenchmarkKind.values),
                      fg: _busy ? _secondary(context) : CupertinoColors.white,
                      bg: _busy ? idleBg : accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(BuildContext context) {
    String line(String label, BenchmarkKind k) {
      final r = _shown(k);
      final v = r == null ? 'Not yet run' : (r.ok ? r.valueText : 'Failed');
      return '${label.padRight(16)} $v';
    }

    final text = [
      'jedToolKit Benchmark Results:',
      '---------------------------------',
      line('CPU Single-Core:', BenchmarkKind.cpuSingle),
      line('CPU Multi-Core:', BenchmarkKind.cpuMulti),
      line('RAM Score:', BenchmarkKind.memory),
      line('Graphics Score:', BenchmarkKind.gpu),
      '---------------------------------',
    ].join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'Benchmark Summary'),
        const SizedBox(height: 12),
        _card(
          context,
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Menlo',
                  fontFamilyFallback: const ['monospace'],
                  color: _secondary(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _howItWorksCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'How It Works'),
        const SizedBox(height: 12),
        _card(
          context,
          Column(
            children: [
              _infoRow(
                context,
                CupertinoIcons.waveform_path_ecg,
                'CPU Computations',
                'Times 16 everyday tasks such as zipping files, sorting photos, route finding and ray tracing, first one by one, then across all cores.',
              ),
              _divider(context, 72),
              _infoRow(
                context,
                CupertinoIcons.memories,
                'RAM Throughput',
                'Tests sequential write, sequential read and random access speed of your device\'s memory.',
              ),
              _divider(context, 72),
              _infoRow(
                context,
                CupertinoIcons.paintbrush_fill,
                'Graphics Core',
                'Draws blur, filter, particle and blending scenes and times the GPU raster work for each.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            // jedBenchmarkViewController: large title 22 bold
            largeTitle: const Text(
              'jedBenchmark 2',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            // clock.arrow.circlepath
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openHistory,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  CupertinoIcons.clock,
                  size: 22,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemBlue,
                    context,
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 20),
              _deviceCard(context),
              const SizedBox(height: 32),
              _trackerCard(context),
              const SizedBox(height: 12),
              const JedFootnote(_disclaimer),
              const SizedBox(height: 20),
              _summaryCard(context),
              const SizedBox(height: 32),
              _howItWorksCard(context),
              const SizedBox(height: kDockClearance),
            ]),
          ),
        ],
      ),
    );
  }
}