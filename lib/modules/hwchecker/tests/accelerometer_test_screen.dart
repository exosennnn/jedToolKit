import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class AccelerometerTestScreen extends StatefulWidget {
  const AccelerometerTestScreen({super.key});

  @override
  State<AccelerometerTestScreen> createState() => _AccelerometerTestScreenState();
}

class _AccelerometerTestScreenState extends State<AccelerometerTestScreen> {
  static const double _shakeThreshold = 1.8;

  bool _shakeDetected = false;
  Offset _tiltOffset = Offset.zero;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = HwNativeBridge.sensorStream('accelerometer').listen(
      (data) {
        if (!mounted) return;
        final x = (data['x'] as num?)?.toDouble() ?? 0.0;
        final y = (data['y'] as num?)?.toDouble() ?? 0.0;
        final z = (data['z'] as num?)?.toDouble() ?? 0.0;

        // Android X-axis is inverted relative to iOS CMAcceleration screen coordinates
        final targetX = (-x * 60.0).clamp(-64.0, 64.0);
        final targetY = (y * 60.0).clamp(-64.0, 64.0);

        final nextX = _tiltOffset.dx + (targetX - _tiltOffset.dx) * 0.3;
        final nextY = _tiltOffset.dy + (targetY - _tiltOffset.dy) * 0.3;

        var shook = _shakeDetected;
        if (!shook) {
          final magnitude = math.sqrt(x * x + y * y + z * z);
          if (magnitude > _shakeThreshold) {
            shook = true;
            HapticFeedback.mediumImpact();
          }
        }

        setState(() {
          _tiltOffset = Offset(nextX, nextY);
          _shakeDetected = shook;
        });
      },
      onError: (e) {
        if (mounted) {
          setState(() => _error = 'Accelerometer unavailable on this device.');
        }
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final activeBubbleColor = _shakeDetected ? green : accent;

    return HwTestPage(
      title: 'Accelerometer Test',
      instruction:
          'Tilt your device to move the bubble. Shake the device firmly to complete the test requirements.',
      canPass: _shakeDetected,
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
        child: Column(
          children: [
            SizedBox(
              height: 180,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer bounds rim
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: hwLabel(context, 0.08), width: 2),
                      ),
                    ),
                    // Center alignment target ring
                    CustomPaint(
                      size: const Size(44, 44),
                      painter: _DashedCirclePainter(
                        color: accent.withOpacity(0.30),
                        strokeWidth: 1.5,
                      ),
                    ),
                    // Floating physics bubble
                    Transform.translate(
                      offset: _tiltOffset,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: activeBubbleColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: activeBubbleColor.withOpacity(0.30),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            HwStatusPill(
              icon: _shakeDetected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.waveform,
              text: _error ??
                  (_shakeDetected
                      ? 'Shake Detected Successfully'
                      : 'Waiting for Firm Shake...'),
              color: _error != null
                  ? CupertinoColors.systemRed.resolveFrom(context)
                  : green,
              active: _shakeDetected || _error != null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _DashedCirclePainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final radius = size.width / 2;
    final center = Offset(radius, radius);
    const dashCount = 16;
    const sweep = (math.pi * 2) / dashCount;

    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * 0.45,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}