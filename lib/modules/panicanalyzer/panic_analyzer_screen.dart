import 'dart:convert';


import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/jedui/jedui_components.dart';
import '../../core/jedui/jedui_dock.dart';
import '../phoneinfo/phone_info.dart';
import 'panic_channel.dart';
import 'panic_mock_samples.dart';
import 'panic_models.dart';
import 'panic_parser.dart';

const int _maxFileBytes = 5 * 1024 * 1024;

class _UserError implements Exception {
  final String message;
  const _UserError(this.message);
}

class PanicAnalyzerScreen extends StatefulWidget {
  const PanicAnalyzerScreen({super.key});

  @override
  State<PanicAnalyzerScreen> createState() => _PanicAnalyzerScreenState();
}

class _PanicAnalyzerScreenState extends State<PanicAnalyzerScreen> {
  final _parser = PanicParser();

  PanicCapabilities? _caps; // null while checking the device
  String? _busy; // 'exits' | 'logcat' | 'import' while an action runs
  String? _error;
  String? _source; // where the current report came from
  String? _fileName;
  int? _fileBytes;
  PanicReport? _report;
  ExitHistory? _exits;
  List<MockResult>? _mock;

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    try {
      final caps = await PanicChannel.capabilities();
      if (mounted) setState(() => _caps = caps);
    } catch (_) {
      // Not on Android, or channel missing: exit history stays off.
      if (mounted) {
        setState(() => _caps = const PanicCapabilities(sdkInt: 0, exitHistory: false));
      }
    }
  }

  /// Runs one action at a time and turns every failure into a visible message.
  Future<void> _run(String key, Future<void> Function() body) async {
    if (_busy != null) return;
    setState(() {
      _busy = key;
      _error = null;
    });
    try {
      await body();
    } on _UserError catch (e) {
      _setError(e.message);
    } on PlatformException catch (e) {
      _setError(e.message ?? 'Android could not complete that (${e.code}).');
    } catch (e) {
      _setError('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _setError(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _showReport(String text, {required String source, String? file, int? bytes}) {
    final report = _parser.parse(text);
    if (!mounted) return;
    setState(() {
      _report = report;
      _source = source;
      _fileName = file;
      _fileBytes = bytes;
    });
  }

    Future<void> _importFile() => _run('import', () async {
      // Storage Access Framework picker: the user chooses the file and the app
      // gets only that file. No storage permission is requested.
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) return; // user cancelled

      // Reject oversized files before loading them, when the size is known.
      final size = await file.length();
      if (size != null && size > _maxFileBytes) {
        throw _UserError(
          'That file is ${_mb(size)} MB. The limit is 5 MB. '
          'Export a smaller part of the log.',
        );
      }

      final bytes = await file.readAsBytes();
      // Fallback for when the size wasn't known before reading.
      if (bytes.length > _maxFileBytes) {
        throw _UserError(
          'That file is ${_mb(bytes.length)} MB. The limit is 5 MB. '
          'Export a smaller part of the log.',
        );
      }

      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.trim().isEmpty) throw const _UserError('That file is empty.');
      _showReport(text, source: 'Imported file', file: file.name, bytes: bytes.length);
    });

  Future<void> _loadExits() => _run('exits', () async {
        final history = await PanicChannel.exitHistory();
        if (!mounted) return;
        setState(() => _exits = history);
      });

  Future<void> _readLogcat() => _run('logcat', () async {
        final text = await PanicChannel.logcat();
        if (text.trim().isEmpty) {
          throw const _UserError('Android returned no log lines for this app.');
        }
        _showReport(text, source: "This app's logcat");
      });

  void _openExit(ExitRecord r) {
    final trace = r.trace;
    if (trace == null) return;
    _showReport(trace, source: '${r.reasonName} · ${_formatTime(r.time)}');
  }

  void _runMock() {
    setState(() {
      _mock = [for (final s in kMockPanicSamples) MockResult(s, _parser.parse(s.text))];
    });
  }

  String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  String _headlineLabel(PanicKind kind) => switch (kind) {
        PanicKind.javaCrash => 'Exception',
        PanicKind.anr => 'Reason',
        PanicKind.nativeCrash => 'Signal',
        PanicKind.unknown => 'Headline',
      };
  InfoSection _summary(PanicReport r) {
    final bytes = _fileBytes;
    final fileName = _fileName;
    final source = _source;
    final process = r.process;
    final pid = r.pid;
    final headline = r.headline;
    final mainThread = r.mainThreadState;
    final load = r.load;

    return InfoSection(
      title: 'Summary',
      fields: [
        if (fileName != null)
          InfoField(label: 'File', value: fileName, status: DataStatus.available),
        if (bytes != null)
          InfoField(
            label: 'Size',
            value: '${_mb(bytes)} MB · ${r.lineCount} lines',
            status: DataStatus.available,
          )
        else
          InfoField(label: 'Lines', value: '${r.lineCount}', status: DataStatus.available),
        InfoField(label: 'Type', value: r.kind.title, status: DataStatus.available),
        if (source != null)
          InfoField(label: 'Source', value: source, status: DataStatus.available),
        if (process != null)
          InfoField(label: 'Process', value: process, status: DataStatus.available),
        if (pid != null)
          InfoField(label: 'PID', value: pid, status: DataStatus.available),
        if (headline != null)
          InfoField(
            label: _headlineLabel(r.kind),
            value: headline,
            status: DataStatus.available,
          ),
        if (mainThread != null)
          InfoField(
            label: 'Main thread',
            value: mainThread,
            status: DataStatus.available,
          ),
        if (load != null)
          InfoField(label: 'System load', value: load, status: DataStatus.available),
      ],
    );
  }

  // ---------------- Sections ----------------

  Widget _sourcesCard(BuildContext context) {
    final busy = _busy;
    final accent = CupertinoTheme.of(context).primaryColor;
    final exitsSupported = _caps?.exitHistory;
    final String exitSubtitle;
    if (exitsSupported == null) {
      exitSubtitle = 'Checking this device…';
    } else if (exitsSupported) {
      exitSubtitle = 'Crashes and ANRs Android recorded for this app';
    } else {
      exitSubtitle = 'Needs Android 11 or newer';
    }

    return JedGroupCard(children: [
      _ActionRow(
        icon: CupertinoIcons.clock_fill,
        tint: accent,
        title: 'Exit history',
        subtitle: exitSubtitle,
        busy: busy == 'exits',
        enabled: busy == null && exitsSupported == true,
        onTap: _loadExits,
      ),
      _ActionRow(
        icon: CupertinoIcons.text_alignleft,
        tint: accent,
        title: "This app's logcat",
        subtitle: 'Recent log lines from this app',
        busy: busy == 'logcat',
        enabled: busy == null,
        onTap: _readLogcat,
      ),
      _ActionRow(
        icon: CupertinoIcons.doc_text_search,
        tint: accent,
        title: 'Import a log file',
        subtitle: 'Logcat export, bug report or tombstone',
        busy: busy == 'import',
        enabled: busy == null,
        onTap: _importFile,
      ),
      _ActionRow(
        icon: CupertinoIcons.checkmark_seal_fill,
        tint: accent,
        title: 'Run mock test',
        subtitle: 'Checks the analyzer on built-in samples',
        busy: false,
        enabled: true,
        onTap: _runMock,
      ),
    ]);
  }

  List<Widget> _mockBlock(BuildContext context) {
    final results = _mock!;
    final passed = results.where((m) => m.passed).length;
    return [
      JedSectionLabel('Mock test · $passed of ${results.length} passed'),
      JedGroupCard(children: [for (final m in results) _MockRow(result: m)]),
      const JedFootnote(
        'Built-in samples go through the same parser as your files. '
        'A failure points to the analyzer, not your phone.',
      ),
    ];
  }

  List<Widget> _exitBlock(BuildContext context) {
    final history = _exits!;
    return [
      const JedSectionLabel('Exit history'),
      if (!history.supported)
        _messageCard(
          context,
          'This Android version does not keep exit history. It needs Android 11 or newer.',
          CupertinoColors.secondaryLabel,
        )
      else if (history.records.isEmpty)
        _messageCard(
          context,
          'Android has no recorded exits for this app yet.',
          CupertinoColors.secondaryLabel,
        )
      else ...[
        JedGroupCard(children: [
          for (final r in history.records)
            _ExitRow(record: r, onTap: r.hasTrace ? () => _openExit(r) : null),
        ]),
        const JedFootnote(
          'Tap an ANR or native crash to analyze its stored trace. '
          'Java crashes keep no trace, so only their details are shown.',
        ),
      ],
    ];
  }

  List<Widget> _reportBlock(BuildContext context, PanicReport r) {
    return [
      JedSection(
        section: _summary(r),
        tint: CupertinoTheme.of(context).primaryColor,
      ),
      const JedSectionLabel('Findings'),
      JedGroupCard(children: [for (final f in r.findings) _FindingRow(finding: f)]),
      const JedFootnote(
        'Pattern-based suggestions from the text in your file. '
        'They point to likely causes and do not prove them.',
      ),
      if (r.frames.isNotEmpty) ...[
        JedSectionLabel('Trace · ${r.frameCount} frames'),
        JedCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final frame in r.frames)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    frame,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
            ],
          ),
        ),
        JedFootnote(
          r.kind == PanicKind.anr
              ? 'Frames from the main thread at the time of the ANR.'
              : 'Top frames in the order the system recorded them. '
                  'The first frame in your own code is usually the most useful.',
        ),
      ],
    ];
  }

  Widget _messageCard(BuildContext context, String text, CupertinoDynamicColor color) {
    return JedCard(
      child: Text(
        text,
        style: TextStyle(fontSize: 15, color: color.resolveFrom(context)),
      ),
    );
  }

  Widget _limitsCard(BuildContext context) {
    return const JedGroupCard(children: [
      _NoteRow(
        title: "Other apps' logs",
        body: 'Android hides most logs from other apps. You can read logs for this app, or logs you export yourself.',
      ),
      _NoteRow(
        title: 'Tombstones',
        body: "Android writes native crash tombstones, and normal apps can't read them directly. Use one exported from a bug report or adb.",
      ),
      _NoteRow(
        title: 'Root and system files',
        body: 'This app never requests root and never reads system folders. It only reads this app\'s own data and the file you choose.',
      ),
      _NoteRow(
        title: 'Accuracy',
        body: "Findings come from text patterns. Confirm them with the full trace and your app's source code.",
      ),
    ]);
  }

  Widget _howToCard(BuildContext context) {
    return const JedGroupCard(children: [
      _NoteRow(
        title: 'Bug report (on the phone)',
        body: 'Turn on Developer options, then choose Take bug report. The menu location varies by manufacturer. '
            'If the download is a zip, choose the text file inside it, often named bugreport-…txt.',
      ),
      _NoteRow(
        title: 'logcat (on a computer)',
        body: 'With USB debugging on, run adb logcat -d > log.txt in a terminal, then choose log.txt here.',
      ),
      _NoteRow(
        title: 'Your own app',
        body: 'Crashes appear as FATAL EXCEPTION. ANRs appear as ANR in followed by your package name. Copy that block from logcat.',
      ),
    ]);
  }

  // ---------------- Page ----------------

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final r = _report;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: Text('jedPanicAnalyzer'),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, kDockClearance + bottom),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const JedSectionLabel('Sources'),
                _sourcesCard(context),
                const JedFootnote('Only data about this app is read. Nothing is uploaded or saved.'),
                if (_error != null) ...[
                  const JedSectionLabel('Could not analyze'),
                  _messageCard(context, _error!, CupertinoColors.systemRed),
                ],
                if (_mock != null) ..._mockBlock(context),
                if (_exits != null) ..._exitBlock(context),
                if (r != null) ..._reportBlock(context, r),
                const JedSectionLabel('What Android allows'),
                _limitsCard(context),
                const JedSectionLabel('Getting a useful log'),
                _howToCard(context),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Helpers and rows ----------------

String _formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

Color _reasonTint(int reason) => switch (reason) {
      4 || 5 => CupertinoColors.systemRed, // Java / native crash
      6 => CupertinoColors.systemOrange, // ANR
      3 || 9 => CupertinoColors.systemPurple, // low memory / resource use
      _ => CupertinoColors.systemGrey,
    };

IconData _reasonIcon(int reason) => switch (reason) {
      4 || 5 => CupertinoIcons.exclamationmark_triangle_fill,
      6 => CupertinoIcons.hourglass,
      3 || 9 => CupertinoIcons.memories,
      _ => CupertinoIcons.power,
    };

/// Shared row layout: glyph, title and optional subtitle, trailing widget.
class _RowShell extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _RowShell({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled || busy ? 1 : 0.4,
      child: JedPressable(
        onTap: enabled ? onTap : null,
        child: _RowShell(
          leading: JedIconBadge(icon: icon, color: tint),
          title: title,
          subtitle: subtitle,
          trailing: busy
              ? const CupertinoActivityIndicator()
              : const CupertinoListTileChevron(),
        ),
      ),
    );
  }
}

class _ExitRow extends StatelessWidget {
  final ExitRecord record;
  final VoidCallback? onTap;

  const _ExitRow({required this.record, this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final tint = _reasonTint(r.reason);
    final detail = r.description == null
        ? '${r.process} · PID ${r.pid} · ${_formatTime(r.time)}'
        : '${r.process} · PID ${r.pid} · ${_formatTime(r.time)}\n${r.description}';

    return JedPressable(
      onTap: onTap,
      child: _RowShell(
        leading: JedIconBadge(icon: _reasonIcon(r.reason), color: tint),
        title: r.reasonName,
        subtitle: detail,
        trailing: JedPill(
          label: r.hasTrace ? 'Trace' : 'No trace',
          color: r.hasTrace
              ? CupertinoTheme.of(context).primaryColor
              : CupertinoColors.systemGrey,
        ),
      ),
    );
  }
}

class _MockRow extends StatelessWidget {
  final MockResult result;

  const _MockRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = result.passed;
    final tint = ok ? CupertinoColors.systemGreen : CupertinoColors.systemRed;
    return _RowShell(
      leading: JedIconBadge(
        icon: ok ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.xmark_octagon_fill,
        color: tint,
      ),
      title: result.sample.name,
      subtitle: 'Expected ${result.sample.expected.title} · got ${result.report.kind.title}',
      trailing: JedPill(label: ok ? 'PASS' : 'FAIL', color: tint),
    );
  }
}

class _FindingRow extends StatelessWidget {
  final Finding finding;

  const _FindingRow({required this.finding});

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = switch (finding.level) {
      FindingLevel.critical => (CupertinoIcons.exclamationmark_octagon_fill, CupertinoColors.systemRed),
      FindingLevel.warning => (CupertinoIcons.exclamationmark_triangle_fill, CupertinoColors.systemOrange),
      FindingLevel.info => (CupertinoIcons.info_circle_fill, CupertinoTheme.of(context).primaryColor),
    };
    return _RowShell(
      leading: JedIconBadge(icon: icon, color: tint),
      title: finding.title,
      subtitle: finding.detail,
    );
  }
}

class _NoteRow extends StatelessWidget {
  final String title;
  final String body;

  const _NoteRow({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}