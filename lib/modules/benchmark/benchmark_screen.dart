import 'package:flutter/cupertino.dart';
import '../../core/jedui/jedui_dock.dart';
import 'benchmark_history.dart';
import 'benchmark_models.dart';
import 'benchmark_runners.dart';
import 'gpu_benchmark_screen.dart';

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
  bool _busy = false;
  bool _cancelRequested = false;
  BenchmarkKind? _current;
  double _progress = 0;
  String? _stage;

  static const _disclaimer =
      'Results depend on temperature, battery level, background apps and power mode. '
      'Use a charged, cool device, close other apps, and compare runs under similar conditions. '
      'Scores only compare within the same device, not against other benchmark apps.';

  @override
  void initState() {
    super.initState();
    _loadHistory();
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

  Future<BenchmarkResult?> _execute(BenchmarkKind kind) {
    if (kind == BenchmarkKind.gpu) {
      return Navigator.of(context).push<BenchmarkResult>(
        CupertinoPageRoute(builder: (_) => const GpuBenchmarkScreen()),
      );
    }

    void onProgress(double p, String s) {
      if (!mounted) return;
      setState(() {
        _progress = p;
        _stage = s;
      });
    }

    bool isCancelled() => _cancelRequested;

    return switch (kind) {
      BenchmarkKind.cpuSingle => _cpu.run(
          multiThread: false,
          onProgress: onProgress,
          isCancelled: isCancelled,
        ),
      BenchmarkKind.cpuMulti => _cpu.run(
          multiThread: true,
          onProgress: onProgress,
          isCancelled: isCancelled,
        ),
      BenchmarkKind.memory => _memory.run(
          onProgress: onProgress,
          isCancelled: isCancelled,
        ),
      BenchmarkKind.gpu => Future<BenchmarkResult?>.value(null),
    };
  }

  Future<void> _run(List<BenchmarkKind> kinds) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _cancelRequested = false;
    });

    for (final kind in kinds) {
      if (_cancelRequested || !mounted) break;
      setState(() {
        _current = kind;
        _progress = 0;
        _stage = 'Starting';
      });
      final result = await _execute(kind);
      if (result != null) await _history.add(result);
    }

    final runs = await _history.load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _current = null;
      _stage = null;
      _progress = 0;
      _runs = runs;
    });
  }

  Future<void> _clearHistory() async {
    await _history.clear();
    if (mounted) setState(() => _runs = []);
  }

  void _showDetails(BenchmarkResult r) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(r.kind.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: Text(r.detailText, textAlign: TextAlign.start),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _dateText(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}  ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _valueText(BuildContext context, String text, {bool failed = false}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: TextStyle(
          color: failed
              ? CupertinoColors.systemRed.resolveFrom(context)
              : CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }

  Widget _testRow(BuildContext context, BenchmarkKind kind) {
    final latest = _latest(kind);
    final running = _busy && _current == kind;

    return CupertinoListTile(
      title: Text(kind.title),
      subtitle: Text(kind.description),
      trailing: running
          ? const CupertinoActivityIndicator()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _valueText(
                  context,
                  latest == null ? 'Not run' : latest.valueText,
                  failed: latest != null && !latest.ok,
                ),
                const CupertinoListTileChevron(),
              ],
            ),
      onTap: _busy ? null : () => _run([kind]),
    );
  }

  Widget _progressSection(BuildContext context) {
    final fraction = _progress.clamp(0.0, 1.0).toDouble();
    return CupertinoListSection.insetGrouped(
      header: Text(_current?.title ?? 'Running'),
      footer: const Text(
        'CPU and memory tests stop after the current round. The GPU test has its own Cancel button.',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _stage ?? 'Starting',
                style: TextStyle(
                  fontSize: 15,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 6,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _historySection(BuildContext context) {
    final shown = _runs.take(10).toList();
    return CupertinoListSection.insetGrouped(
      header: const Text('History'),
      footer: const Text(
        'Last 10 runs shown. Tap a run for details. Results are stored on this device only.',
      ),
      children: [
        if (shown.isEmpty)
          const CupertinoListTile(title: Text('No runs yet')),
        for (final r in shown)
          CupertinoListTile(
            title: Text(r.kind.title),
            subtitle: Text(_dateText(r.timestamp)),
            trailing: _valueText(context, r.valueText, failed: !r.ok),
            onTap: () => _showDetails(r),
          ),
        if (_runs.isNotEmpty)
          CupertinoListTile(
            title: Text(
              'Clear history',
              style: TextStyle(
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
            onTap: _busy ? null : _clearHistory,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Benchmark'),
            trailing: _busy
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _cancelRequested = true),
                    child: const Text('Cancel'),
                  )
                : CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _run(BenchmarkKind.values),
                    child: const Text('Run all'),
                  ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              if (_busy) _progressSection(context),
              CupertinoListSection.insetGrouped(
                header: const Text('Tests'),
                footer: Text(_disclaimer),
                children: [
                  for (final k in BenchmarkKind.values) _testRow(context, k),
                ],
              ),
              _historySection(context),
              const SizedBox(height: kDockClearance),
            ]),
          ),
        ],
      ),
    );
  }
}