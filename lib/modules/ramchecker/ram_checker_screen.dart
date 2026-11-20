import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/jedui/jedui_components.dart';
import '../../core/jedui/jedui_dock.dart';
import '../../core/settings/app_settings.dart';

// MARK: - Models

enum MemoryPressureLevel {
  normal('Normal'),
  warning('Warning'),
  critical('Critical');

  final String label;
  const MemoryPressureLevel(this.label);

  Color get color {
    switch (this) {
      case MemoryPressureLevel.normal:
        return CupertinoColors.systemGreen;
      case MemoryPressureLevel.warning:
        return CupertinoColors.systemYellow;
      case MemoryPressureLevel.critical:
        return CupertinoColors.systemRed;
    }
  }

  static MemoryPressureLevel fromString(String? value) {
    switch (value) {
      case 'Critical':
        return MemoryPressureLevel.critical;
      case 'Warning':
        return MemoryPressureLevel.warning;
      default:
        return MemoryPressureLevel.normal;
    }
  }
}

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

class AppMemoryMetrics {
  final int physicalFootprintBytes;
  final int residentMemoryBytes;
  final int virtualMemoryBytes;
  final int availableBudgetBytes;
  final int totalBudgetEstimateBytes;

  const AppMemoryMetrics({
    required this.physicalFootprintBytes,
    required this.residentMemoryBytes,
    required this.virtualMemoryBytes,
    required this.availableBudgetBytes,
    required this.totalBudgetEstimateBytes,
  });

  double get usagePercentage {
    if (totalBudgetEstimateBytes <= 0) return 0.0;
    return (physicalFootprintBytes / totalBudgetEstimateBytes) * 100.0;
  }

  factory AppMemoryMetrics.fromMap(Map<dynamic, dynamic> m) => AppMemoryMetrics(
    physicalFootprintBytes: _int(m['physicalFootprintBytes']),
    residentMemoryBytes: _int(m['residentMemoryBytes']),
    virtualMemoryBytes: _int(m['virtualMemoryBytes']),
    availableBudgetBytes: _int(m['availableBudgetBytes']),
    totalBudgetEstimateBytes: _int(m['totalBudgetEstimateBytes']),
  );
}

class SystemMemoryMetrics {
  final int totalPhysicalBytes;
  final int usedBytes;
  final int availableBytes;
  final int? freeBytes;
  final int pageSizeBytes;
  final int addressWidthBits;
  final int virtualAddressSpaceBytes;
  final bool lowMemory;

  const SystemMemoryMetrics({
    required this.totalPhysicalBytes,
    required this.usedBytes,
    required this.availableBytes,
    required this.freeBytes,
    required this.pageSizeBytes,
    required this.addressWidthBits,
    required this.virtualAddressSpaceBytes,
    required this.lowMemory,
  });

  factory SystemMemoryMetrics.fromMap(Map<dynamic, dynamic> m) =>
      SystemMemoryMetrics(
        totalPhysicalBytes: _int(m['totalPhysicalBytes']),
        usedBytes: _int(m['usedBytes']),
        availableBytes: _int(m['availableBytes']),
        freeBytes: (m['freeBytes'] as num?)?.toInt(),
        pageSizeBytes: _int(m['pageSizeBytes'], 4096),
        addressWidthBits: _int(m['addressWidthBits'], 64),
        virtualAddressSpaceBytes: _int(m['virtualAddressSpaceBytes']),
        lowMemory: m['lowMemory'] == true,
      );
}

class MemoryCapability {
  final String title;
  final String status;
  final String summary;

  const MemoryCapability({
    required this.title,
    required this.status,
    required this.summary,
  });

  Color get statusColor {
    switch (status) {
      case 'Available':
        return CupertinoColors.systemGreen;
      case 'Unavailable':
        return CupertinoColors.systemOrange;
      default:
        return CupertinoColors.systemGrey;
    }
  }

  factory MemoryCapability.fromMap(Map<dynamic, dynamic> m) => MemoryCapability(
    title: m['title']?.toString() ?? '',
    status: m['status']?.toString() ?? 'Unsupported',
    summary: m['summary']?.toString() ?? '',
  );
}

class MemoryDataPoint {
  final DateTime timestamp;
  final double usedMB;
  final double budgetMB;
  final MemoryPressureLevel pressureLevel;

  const MemoryDataPoint({
    required this.timestamp,
    required this.usedMB,
    required this.budgetMB,
    required this.pressureLevel,
  });
}

// MARK: - Screen

class RamCheckerScreen extends StatefulWidget {
  const RamCheckerScreen({super.key});

  @override
  State<RamCheckerScreen> createState() => _RamCheckerScreenState();
}

class _RamCheckerScreenState extends State<RamCheckerScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel(
    'com.jedplatforms.jedtoolkit/phoneinfo',
  );

  /// Longest window the picker offers; history is kept this long so switching
  /// from 30s to 5m doesn't throw data away.
  static const _maxHistorySeconds = 300;

  /// How long a trim/low-memory event keeps the pressure badge raised.
  static const _pressureHold = Duration(seconds: 20);

  Timer? _timer;
  bool _busy = false;

  AppMemoryMetrics? _appMetrics;
  SystemMemoryMetrics? _sysMetrics;
  List<MemoryCapability> _capabilities = [];

  MemoryPressureLevel _trimLevel = MemoryPressureLevel.normal;
  DateTime? _trimAt;
  bool _lowMem = false;

  int _warningCount = 0;
  DateTime? _lastWarningTime;
  final List<MemoryDataPoint> _history = [];
  int _timeWindowSeconds = 60;

  /// Raised by a recent trim event or the system low-memory flag; decays back
  /// to normal on its own (otherwise the badge would stick forever).
  MemoryPressureLevel get _pressureLevel {
    var level = MemoryPressureLevel.normal;
    final at = _trimAt;
    if (at != null && DateTime.now().difference(at) < _pressureHold) {
      level = _trimLevel;
    }
    if (_lowMem && level == MemoryPressureLevel.normal) {
      level = MemoryPressureLevel.warning;
    }
    return level;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_handleNativeCallback);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel(); // don't sample while backgrounded
      _timer = null;
    }
  }

  void _start() {
    _timer?.cancel();
    _refreshMetrics();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshMetrics(),
    );
  }

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method != 'onMemoryPressure' || !mounted) return;
    final level = MemoryPressureLevel.fromString(call.arguments as String?);
    setState(() {
      _trimLevel = level;
      _trimAt = DateTime.now();
      if (level != MemoryPressureLevel.normal) {
        _warningCount++;
        _lastWarningTime = DateTime.now();
      }
    });
  }

  Future<void> _refreshMetrics() async {
    if (_busy) return; // never stack calls if one is slow
    _busy = true;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getRamMetrics',
        {'includeCapabilities': _capabilities.isEmpty},
      );
      if (result == null || !mounted) return;

      final app = AppMemoryMetrics.fromMap(result['app'] as Map);
      final sys = SystemMemoryMetrics.fromMap(result['system'] as Map);
      final caps = (result['capabilities'] as List<dynamic>?)
          ?.map((e) => MemoryCapability.fromMap(e as Map))
          .toList();

      final now = DateTime.now();
      setState(() {
        _appMetrics = app;
        _sysMetrics = sys;
        if (caps != null && caps.isNotEmpty) _capabilities = caps;

        if (sys.lowMemory && !_lowMem) {
          _warningCount++;
          _lastWarningTime = now;
        }
        _lowMem = sys.lowMemory;

        _history.add(
          MemoryDataPoint(
            timestamp: now,
            usedMB: app.physicalFootprintBytes / (1024 * 1024),
            budgetMB: app.totalBudgetEstimateBytes / (1024 * 1024),
            pressureLevel: _pressureLevel,
          ),
        );
        final cutoff = now.subtract(
          const Duration(seconds: _maxHistorySeconds),
        );
        while (_history.isNotEmpty &&
            _history.first.timestamp.isBefore(cutoff)) {
          _history.removeAt(0);
        }
      });
    } catch (e) {
      debugPrint('RAM sample failed: $e');
    } finally {
      _busy = false;
    }
  }

  List<MemoryDataPoint> get _visibleHistory {
    if (_history.isEmpty) return const [];
    final cutoff = _history.last.timestamp.subtract(
      Duration(seconds: _timeWindowSeconds),
    );
    return _history.where((p) => !p.timestamp.isBefore(cutoff)).toList();
  }

  (String title, String detail, Color color) get _diagnosticsSummary {
    final app = _appMetrics;
    final pressure = _pressureLevel;
    if (app == null) {
      return (
        'Initializing',
        'Reading kernel and ART runtime statistics...',
        CupertinoColors.systemGreen,
      );
    }
    if (pressure == MemoryPressureLevel.critical ||
        app.usagePercentage > 85.0) {
      return (
        'Critical',
        'High memory utilization detected. System memory pressure is elevated.',
        CupertinoColors.systemRed,
      );
    } else if (pressure == MemoryPressureLevel.warning ||
        app.usagePercentage > 70.0) {
      return (
        'Warning',
        'App memory budget is limited. Monitor footprint to avoid LMKD termination.',
        CupertinoColors.systemYellow,
      );
    }
    return (
      'Excellent',
      'Memory usage is healthy. App operates well within safe allocation boundaries.',
      CupertinoColors.systemGreen,
    );
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
    final (diagTitle, diagDetail, diagColor) = _diagnosticsSummary;
    final pressure = _pressureLevel;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final app = _appMetrics;
    final sys = _sysMetrics;
    final visible = _visibleHistory;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: Text('jedRAMChecker'),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, kDockClearance),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 1. Diagnostics header
                JedCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.heart_fill,
                            color: CupertinoDynamicColor.resolve(
                              diagColor,
                              context,
                            ),
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            diagTitle,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        diagDetail,
                        style: TextStyle(fontSize: 14, color: secondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. App memory budget gauge
                JedCard(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const _CardTitle('App Memory Budget'),
                          JedPill(label: pressure.label, color: pressure.color),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (app != null)
                        Row(
                          children: [
                            SizedBox(
                              width: 100,
                              height: 100,
                              child: CustomPaint(
                                painter: _RingGaugePainter(
                                  progress: (app.usagePercentage / 100).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  color: CupertinoDynamicColor.resolve(
                                    app.usagePercentage > 80
                                        ? CupertinoColors.systemRed
                                        : (app.usagePercentage > 60
                                              ? CupertinoColors.systemYellow
                                              : AppSettings.instance.accent),
                                    context,
                                  ),
                                  trackColor: _alpha(
                                    CupertinoColors.systemGrey.resolveFrom(
                                      context,
                                    ),
                                    0.2,
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${app.usagePercentage.toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Used',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                children: [
                                  _MetricRow(
                                    title: 'Current Usage',
                                    value: _formatBytes(
                                      app.physicalFootprintBytes,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _MetricRow(
                                    title: 'Remaining Budget',
                                    value: _formatBytes(
                                      app.availableBudgetBytes,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _MetricRow(
                                    title: 'Estimated Limit',
                                    value: _formatBytes(
                                      app.totalBudgetEstimateBytes,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: CupertinoActivityIndicator(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Live footprint graph
                JedCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _CardTitle('App Footprint Live Graph'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoSlidingSegmentedControl<int>(
                          groupValue: _timeWindowSeconds,
                          children: const {
                            30: Text('30s', style: TextStyle(fontSize: 13)),
                            60: Text('60s', style: TextStyle(fontSize: 13)),
                            300: Text('5m', style: TextStyle(fontSize: 13)),
                          },
                          onValueChanged: (val) {
                            if (val != null) {
                              setState(() => _timeWindowSeconds = val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 160,
                        width: double.infinity,
                        child: visible.length > 1
                            ? RepaintBoundary(
                                child: CustomPaint(
                                  painter: _LiveLineChartPainter(
                                    history: visible,
                                    lineColor: AppSettings.instance.accent
                                        .resolveFrom(context),
                                    gridColor: CupertinoColors.separator
                                        .resolveFrom(context),
                                    labelColor: secondary,
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  'Collecting memory samples...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: secondary,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Memory pressure statistics
                JedCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _CardTitle('Memory Pressure Statistics'),
                      const SizedBox(height: 10),
                      _MetricRow(
                        title: 'Current Pressure Level',
                        value: pressure.label,
                      ),
                      const SizedBox(height: 8),
                      _MetricRow(
                        title: 'Warning Events',
                        value: '$_warningCount',
                      ),
                      const SizedBox(height: 8),
                      _MetricRow(
                        title: 'Last Warning Time',
                        value: _lastWarningTime != null
                            ? _formatTime(_lastWarningTime!)
                            : 'None',
                      ),
                      const SizedBox(height: 8),
                      const _MetricRow(
                        title: 'Application State',
                        value: 'Active',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Current application memory (2x2)
                if (app != null) ...[
                  JedCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _CardTitle('Current Application Memory'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _StatBox(
                                title: 'Physical Footprint (PSS)',
                                value: _formatBytes(app.physicalFootprintBytes),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatBox(
                                title: 'Resident Memory (RSS)',
                                value: _formatBytes(app.residentMemoryBytes),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _StatBox(
                                title: 'Virtual Memory',
                                value: _formatBytes(app.virtualMemoryBytes),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatBox(
                                title: 'Remaining Budget',
                                value: _formatBytes(app.availableBudgetBytes),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 6. Device hardware memory
                if (sys != null) ...[
                  JedCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _CardTitle('Device Hardware Memory'),
                        const SizedBox(height: 12),
                        _MetricRow(
                          title: 'Total Physical RAM',
                          value: _formatBytes(sys.totalPhysicalBytes),
                        ),
                        const SizedBox(height: 8),
                        _MetricRow(
                          title: 'Active/Kernel Memory',
                          value: _formatBytes(sys.usedBytes),
                        ),
                        const SizedBox(height: 8),
                        _MetricRow(
                          title: 'Available RAM',
                          value: _formatBytes(sys.availableBytes),
                        ),
                        const SizedBox(height: 8),
                        _MetricRow(
                          title: 'Unallocated Free RAM',
                          value: sys.freeBytes != null
                              ? _formatBytes(sys.freeBytes!)
                              : 'Unavailable',
                        ),
                        const SizedBox(height: 8),
                        _MetricRow(
                          title: 'Page Size',
                          value: '${sys.pageSizeBytes} bytes',
                        ),
                        const SizedBox(height: 8),
                        _MetricRow(
                          title: 'Address Width',
                          value: '${sys.addressWidthBits}-bit',
                        ),
                        const SizedBox(height: 8),
                        _MetricRow(
                          title: 'Virtual Address Space',
                          value: _formatBytes(sys.virtualAddressSpaceBytes),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 7. Capability checker
                if (_capabilities.isNotEmpty) ...[
                  const JedSectionLabel('Memory Capability Checker'),
                  JedGroupCard(
                    children: [
                      for (final cap in _capabilities)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cap.title,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      cap.summary,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              JedPill(
                                label: cap.status,
                                color: cap.statusColor,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Helper widgets

class _CardTitle extends StatelessWidget {
  final String text;
  const _CardTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
  );
}

class _MetricRow extends StatelessWidget {
  final String title;
  final String value;

  const _MetricRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String title;
  final String value;

  const _StatBox({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// MARK: - Painters

class _RingGaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _RingGaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 11.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingGaugePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// Mirrors the iOS Swift Charts view: auto-scaled Y axis with labels and
/// gridlines on the trailing edge, smooth monotone line, gradient area fill,
/// X domain fitted to the visible samples (no X labels).
class _LiveLineChartPainter extends CustomPainter {
  final List<MemoryDataPoint> history;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  _LiveLineChartPainter({
    required this.history,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  static const double _labelWidth = 52;
  static const double _vPad = 10;
  static const double _minSpanMB =
      8; // keeps tiny PSS jitter from looking dramatic

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;

    final chartW = size.width - _labelWidth;
    final chartH = size.height - _vPad * 2;
    if (chartW <= 0 || chartH <= 0) return;

    // ---- Y scale (nice ticks) ----
    var lo = history.first.usedMB;
    var hi = lo;
    for (final p in history) {
      lo = math.min(lo, p.usedMB);
      hi = math.max(hi, p.usedMB);
    }
    final span = math.max(hi - lo, _minSpanMB);
    final mid = (hi + lo) / 2;
    final padded = span * 1.25;
    final rawMin = math.max(0.0, mid - padded / 2);
    final rawMax = rawMin + padded;

    final step = _niceStep(padded / 3);
    final axisMin = (rawMin / step).floor() * step;
    var axisMax = (rawMax / step).ceil() * step;
    if (axisMax <= axisMin) axisMax = axisMin + step;
    final axisRange = axisMax - axisMin;

    double yFor(double mb) =>
        _vPad + chartH * (1.0 - (mb - axisMin) / axisRange);

    // ---- gridlines + labels ----
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var v = axisMin; v <= axisMax + step * 0.001; v += step) {
      final y = yFor(v);
      canvas.drawLine(Offset(0, y), Offset(chartW, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: _axisLabel(v),
          style: TextStyle(fontSize: 10, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chartW + 8, y - tp.height / 2));
    }

    // ---- X by timestamp across visible span ----
    final t0 = history.first.timestamp.millisecondsSinceEpoch.toDouble();
    final t1 = history.last.timestamp.millisecondsSinceEpoch.toDouble();
    final tSpan = math.max(1.0, t1 - t0);

    final pts = <Offset>[
      for (final p in history)
        Offset(
          chartW * ((p.timestamp.millisecondsSinceEpoch - t0) / tSpan),
          yFor(p.usedMB),
        ),
    ];

    // ---- smooth line + fill ----
    final linePath = _monotonePath(pts);
    final bottom = _vPad + chartH;
    final fillPath = Path.from(linePath)
      ..lineTo(pts.last.dx, bottom)
      ..lineTo(pts.first.dx, bottom)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_alpha(lineColor, 0.30), _alpha(lineColor, 0.0)],
        ).createShader(Rect.fromLTWH(0, _vPad, chartW, chartH)),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

    // ---- live dot ----
    canvas.drawCircle(pts.last, 5, Paint()..color = _alpha(lineColor, 0.25));
    canvas.drawCircle(pts.last, 3, Paint()..color = lineColor);
  }

  /// Fritsch–Carlson monotone cubic: smooth like Swift Charts' .monotone,
  /// never overshoots the data.
  static Path _monotonePath(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    final n = p.length;
    if (n == 2) {
      path.lineTo(p[1].dx, p[1].dy);
      return path;
    }

    final d = List<double>.filled(n - 1, 0);
    for (var i = 0; i < n - 1; i++) {
      final dx = p[i + 1].dx - p[i].dx;
      d[i] = dx == 0 ? 0 : (p[i + 1].dy - p[i].dy) / dx;
    }
    final m = List<double>.filled(n, 0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    }
    for (var i = 0; i < n - 1; i++) {
      if (d[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
      } else {
        final a = m[i] / d[i];
        final b = m[i + 1] / d[i];
        final s = a * a + b * b;
        if (s > 9) {
          final t = 3 / math.sqrt(s);
          m[i] = t * a * d[i];
          m[i + 1] = t * b * d[i];
        }
      }
    }
    for (var i = 0; i < n - 1; i++) {
      final dx = (p[i + 1].dx - p[i].dx) / 3;
      path.cubicTo(
        p[i].dx + dx,
        p[i].dy + m[i] * dx,
        p[i + 1].dx - dx,
        p[i + 1].dy - m[i + 1] * dx,
        p[i + 1].dx,
        p[i + 1].dy,
      );
    }
    return path;
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / exp;
    final nf = f <= 1 ? 1.0 : (f <= 2 ? 2.0 : (f <= 5 ? 5.0 : 10.0));
    return nf * exp;
  }

  static String _axisLabel(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.round()} MB';
  }

  @override
  bool shouldRepaint(covariant _LiveLineChartPainter old) =>
      old.history.length != history.length ||
      old.history.last.timestamp != history.last.timestamp ||
      old.history.first.timestamp != history.first.timestamp ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor;
}

// MARK: - Utils

/// Version-proof replacement for withOpacity / withValues.
Color _alpha(Color c, double opacity) =>
    c.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());

String _formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const mb = 1024 * 1024;
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  return '${(bytes / mb).toStringAsFixed(1)} MB';
}
