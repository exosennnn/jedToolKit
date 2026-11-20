import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../core/jedui/jedui_dock.dart';
import 'hw_accent.dart';
import 'hw_native_bridge.dart';
import 'hw_test.dart';
import 'hw_test_screens.dart';
import 'hw_view_model.dart';
import 'hw_widgets.dart';
import 'tests/accelerometer_test_screen.dart';
import 'tests/battery_info_screen.dart';
import 'tests/biometric_test_screen.dart';
import 'tests/bluetooth_test_screen.dart';
import 'tests/brightness_test_screen.dart';
import 'tests/camera_test_screen.dart';
import 'tests/cellular_volte_test_screen.dart';
import 'tests/charger_test_screen.dart';
import 'tests/gyroscope_test_screen.dart';
import 'tests/led_flash_test_screen.dart';
import 'tests/magnetometer_test_screen.dart';
import 'tests/mic_test_screen.dart';
import 'tests/physical_buttons_test_screen.dart';
import 'tests/proximity_test_screen.dart';
import 'tests/speaker_test_screen.dart';
import 'tests/vibration_test_screen.dart';
import 'tests/wifi_test_screen.dart';
import '../../core/jedui/jedui_route.dart';

/// Which screen opens for each test title, and whether it is full-screen modal
/// (iOS `present`) or pushed (iOS `pushViewController`).
({Widget page, bool modal})? _routeFor(String title) => switch (title) {
  // Core Components
  'Display Test' => (page: const DisplayTestScreen(), modal: true),
  'Touch Responsiveness' => (page: const TouchTestScreen(), modal: true),
  'Physical Buttons Test' => (page: const PhysicalButtonsTestScreen(), modal: false),

  // Audio & Visual
  'Speaker Test' => (page: const SpeakerTestScreen(), modal: false),
  'Microphone Test' => (page: const MicTestScreen(), modal: false),
  'Camera Test' => (page: const CameraTestScreen(), modal: false),
  'LED Flash Test' => (page: const LedFlashTestScreen(), modal: false),

  // Sensors
  'Biometric Test' => (page: const BiometricTestScreen(), modal: false),
  'Accelerometer Test' => (page: const AccelerometerTestScreen(), modal: false),
  'Gyroscope Test' => (page: const GyroscopeTestScreen(), modal: false),
  'Magnetometer Test' => (page: const MagnetometerTestScreen(), modal: false),
  'Proximity Sensor Test' => (page: const ProximityTestScreen(), modal: false),
  'Vibration Test' => (page: const VibrationTestScreen(), modal: false),
  'Brightness Test' => (page: const BrightnessTestScreen(), modal: false),

  // Connectivity
  'Wi-Fi Connectivity Test' => (page: const WifiTestScreen(), modal: false),
  'Bluetooth Connectivity Test' => (page: const BluetoothTestScreen(), modal: false),
  'Cellular & VoLTE Test' => (page: const CellularVolteTestScreen(), modal: false),
  'Charger Test' => (page: const ChargerTestScreen(), modal: false),

  // Tools
  'Battery Health Info' => (page: const BatteryInfoScreen(), modal: false),

  _ => null,
};

class HwCheckerScreen extends StatefulWidget {
  const HwCheckerScreen({super.key});

  @override
  State<HwCheckerScreen> createState() => _HwCheckerScreenState();
}

class _HwCheckerScreenState extends State<HwCheckerScreen> {
  final HwViewModel _vm = HwViewModel();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _open(HwTest test) async {
    final route = _routeFor(test.title);
    if (route == null) {
      showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: Text(test.title),
          content: const Text('This test has not been ported to Android yet.'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final result = await Navigator.of(context).push<HwTestState>(
      JedPageRoute(fullscreenDialog: route.modal, builder: (_) => route.page),
    );
    if (result != null && mounted) _vm.updateTestResult(test.title, result);
  }

  void _share() => HwNativeBridge.shareText(_vm.generateShareText());

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: const Text(
            'jedHWChecker',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
            border: null,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: _share,
              child: const Icon(CupertinoIcons.share, size: 22),
            ),
          ),
          SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: Listenable.merge([_vm, HwAccent.instance]),
              builder: (context, _) {
                var iconIndex = 0;
                return Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: kDockClearance),
                  child: Column(
                    children: [
                      _OverallStatusCard(vm: _vm),
                      for (final section in _vm.sections) ...[
                        const SizedBox(height: 32),
                        _SectionCard(
                          section: section,
                          firstIconIndex: (iconIndex += section.tests.length) - section.tests.length,
                          onTap: _open,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ overall card

class _OverallStatusCard extends StatelessWidget {
  final HwViewModel vm;
  const _OverallStatusCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final percent = (vm.scorePercentage * 100).round();

    return HwCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(80, 80),
                  painter: _RingPainter(
                    progress: vm.scorePercentage,
                    track: hwLabel(context, 0.05),
                    color: accent,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$percent%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(
                      '${vm.completedTestCount}/${vm.totalTestCount}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          const Text('Overall Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color color;
  _RingPainter({required this.progress, required this.track, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect, 0, math.pi * 2, false,
      Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = track,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect, -math.pi / 2, math.pi * 2 * progress.clamp(0.0, 1.0), false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) =>
      o.progress != progress || o.color != color || o.track != track;
}

// ------------------------------------------------------------ section card

class _SectionCard extends StatelessWidget {
  final HwSection section;
  final int firstIconIndex;
  final ValueChanged<HwTest> onTap;
  const _SectionCard({required this.section, required this.firstIconIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              section.title.toUpperCase(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: hwCardDecoration(context),
            child: Column(
              children: [
                for (var i = 0; i < section.tests.length; i++) ...[
                  _TestRow(
                    test: section.tests[i],
                    iconColor: HwAccent.instance.iconColor(context, firstIconIndex + i),
                    onTap: () => onTap(section.tests[i]),
                  ),
                  if (i != section.tests.length - 1)
                    Container(height: 0.5, margin: const EdgeInsets.only(left: 64), color: hwLabel(context, 0.05)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TestRow extends StatefulWidget {
  final HwTest test;
  final Color iconColor;
  final VoidCallback onTap;
  const _TestRow({required this.test, required this.iconColor, required this.onTap});

  @override
  State<_TestRow> createState() => _TestRowState();
}

class _TestRowState extends State<_TestRow> {
  bool _down = false;

  (IconData, Color)? _status(BuildContext c) => switch (widget.test.state) {
    HwTestState.passed => (CupertinoIcons.checkmark_circle_fill, CupertinoColors.systemGreen.resolveFrom(c)),
    HwTestState.failed => (CupertinoIcons.xmark_circle_fill, CupertinoColors.systemRed.resolveFrom(c)),
    HwTestState.partial => (CupertinoIcons.exclamationmark_triangle_fill, CupertinoColors.systemOrange.resolveFrom(c)),
    HwTestState.notTested => null,
  };

  @override
  Widget build(BuildContext context) {
    final status = _status(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: Container(
        color: _down ? hwLabel(context, 0.06) : const Color(0x00000000),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Icon(widget.test.icon, size: 20, color: widget.iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.test.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.test.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (status != null)
              Icon(status.$1, size: 16, color: status.$2)
            else
              Icon(
                CupertinoIcons.chevron_forward,
                size: 14,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
          ],
        ),
      ),
    );
  }
}