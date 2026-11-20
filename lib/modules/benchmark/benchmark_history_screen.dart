import 'package:flutter/cupertino.dart';

import 'benchmark_history.dart';
import 'benchmark_models.dart';

/// Mirrors BenchmarkHistoryViewController: a plain table with a large "History"
/// title, "<label>: N pts" rows with the date underneath and a disclosure
/// chevron, tap for a details alert, swipe to delete.
class BenchmarkHistoryScreen extends StatefulWidget {
  const BenchmarkHistoryScreen({super.key});

  @override
  State<BenchmarkHistoryScreen> createState() => _BenchmarkHistoryScreenState();
}

class _BenchmarkHistoryScreenState extends State<BenchmarkHistoryScreen> {
  final _history = BenchmarkHistory();
  List<BenchmarkResult>? _runs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final runs = await _history.load();
    if (mounted) setState(() => _runs = runs);
  }

  static String _label(BenchmarkKind k) => switch (k) {
    BenchmarkKind.cpuSingle => 'CPU Single-Core',
    BenchmarkKind.cpuMulti => 'CPU Multi-Core',
    BenchmarkKind.memory => 'RAM Score',
    BenchmarkKind.gpu => 'Graphics Score',
  };

  /// DateFormatter dateStyle .medium + timeStyle .short, e.g. "Nov 20, 2026, 6:24 AM"
  static String _dateText(DateTime t) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    return '${months[t.month - 1]} ${t.day}, ${t.year}, $h:$mm ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  void _showDetails(BenchmarkResult r) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Benchmark Details'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(child: Text(r.detailText)),
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

  void _delete(BenchmarkResult r) {
    setState(() => _runs!.remove(r));
    _history.remove(r);
  }

  @override
  Widget build(BuildContext context) {
    final runs = _runs;
    final bottom = MediaQuery.of(context).padding.bottom;

    return CupertinoPageScaffold(
      // UITableViewController (plain): systemBackground
      backgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text(
              'History',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          if (runs != null && runs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
                  child: Text(
                    'No benchmark history found.\nRun a test to see results here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else if (runs != null)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final r = runs[i];
                return Dismissible(
                  key: ValueKey(
                    '${r.kind.name}-${r.timestamp.microsecondsSinceEpoch}',
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _delete(r),
                  background: Container(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 17,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                  child: _HistoryRow(
                    title: '${_label(r.kind)}: ${r.ok ? r.valueText : 'Failed'}',
                    date: _dateText(r.timestamp),
                    showSeparator: i != runs.length - 1,
                    onTap: () => _showDetails(r),
                  ),
                );
              }, childCount: runs.length),
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottom + 16)),
        ],
      ),
    );
  }
}

/// Table cell: title (16 medium), date (secondary), disclosure chevron,
/// gray highlight while pressed, 16pt-inset hairline separator.
class _HistoryRow extends StatefulWidget {
  final String title;
  final String date;
  final bool showSeparator;
  final VoidCallback onTap;

  const _HistoryRow({
    required this.title,
    required this.date,
    required this.showSeparator,
    required this.onTap,
  });

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: Container(
        color: _down
            ? CupertinoColors.systemGrey5.resolveFrom(context)
            : CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.date,
                          style: TextStyle(
                            fontSize: 15,
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 14,
                    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ],
              ),
            ),
            if (widget.showSeparator)
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 16),
                color: CupertinoColors.separator.resolveFrom(context),
              ),
          ],
        ),
      ),
    );
  }
}