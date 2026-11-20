import 'package:flutter/cupertino.dart';

import 'disk_history.dart';

/// Port of HistoryViewController: card list, tap for details,
/// swipe left to delete, "Clear" in the nav bar.
class DiskHistoryScreen extends StatefulWidget {
  const DiskHistoryScreen({super.key});

  @override
  State<DiskHistoryScreen> createState() => _DiskHistoryScreenState();
}

class _DiskHistoryScreenState extends State<DiskHistoryScreen> {
  List<DiskHistoryEntry> _results = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DiskHistoryManager.load();
    if (mounted) {
      setState(() {
        _results = list;
        _loaded = true;
      });
    }
  }

  void _confirmClear() {
    if (_results.isEmpty) return;
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'Are you sure you want to delete all test results?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await DiskHistoryManager.clear();
              if (mounted) setState(() => _results = []);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showDetails(DiskHistoryEntry e) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Test Details'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            e.detailedDescription,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
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

  Future<void> _delete(int index) async {
    setState(() => _results.removeAt(index));
    await DiskHistoryManager.deleteAt(index);
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('History'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _results.isEmpty ? null : _confirmClear,
              child: const Text(
                'Clear',
                style: TextStyle(color: CupertinoColors.systemRed),
              ),
            ),
          ),
          if (_loaded && _results.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No test history found.\nRun a disk speed test to see results here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: secondary),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                20,
                10,
                20,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final e = _results[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Dismissible(
                        key: ValueKey(e.date.millisecondsSinceEpoch),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _delete(i),
                        background: Container(
                          color: CupertinoColors.systemRed,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(
                            CupertinoIcons.delete,
                            color: CupertinoColors.white,
                          ),
                        ),
                        child: _HistoryCard(
                          entry: e,
                          onTap: () => _showDetails(e),
                        ),
                      ),
                    ),
                  );
                }, childCount: _results.length),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final DiskHistoryEntry entry;
  final VoidCallback onTap;

  const _HistoryCard({required this.entry, required this.onTap});

  static String _date(DateTime d) {
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
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final min = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year} at $h12:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);

    Widget speed(String title, double v) => Expanded(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: title,
              style: TextStyle(fontSize: 16, color: secondary),
            ),
            TextSpan(
              text: '${v.toStringAsFixed(1)} MB/s',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: label,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 15, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _date(entry.date),
                    style: TextStyle(fontSize: 14, color: secondary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      speed('Write: ', entry.writeSpeedMBps),
                      const SizedBox(width: 8),
                      speed('Read: ', entry.readSpeedMBps),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 13,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }
}
