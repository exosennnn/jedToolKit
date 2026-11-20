import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class MagnetometerTestScreen extends StatefulWidget {
  const MagnetometerTestScreen({super.key});

  @override
  State<MagnetometerTestScreen> createState() => _MagnetometerTestScreenState();
}

class _MagnetometerTestScreenState extends State<MagnetometerTestScreen> {
  static const double _rotationThreshold = math.pi * 2.0 * 0.95; // 95% of 360°

  double _progress = 0.0;
  double _currentYaw = 0.0;
  bool _isCompleted = false;
  String? _error;

  double? _lastYaw;
  double _totalYawRotation = 0.0;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = HwNativeBridge.sensorStream('magnetometer').listen(
      (data) {
        if (!mounted || _isCompleted) return;
        final yaw = (data['yaw'] as num?)?.toDouble() ?? 0.0;

        if (_lastYaw != null) {
          var deltaYaw = yaw - _lastYaw!;
          if (deltaYaw > math.pi) {
            deltaYaw -= 2 * math.pi;
          } else if (deltaYaw < -math.pi) {
            deltaYaw += 2 * math.pi;
          }
          _totalYawRotation += deltaYaw;
        }
        _lastYaw = yaw;

        final nextProgress = (_totalYawRotation.abs() / _rotationThreshold).clamp(0.0, 1.0);
        final done = _totalYawRotation.abs() >= _rotationThreshold;

        if (done) {
          _sub?.cancel();
        }

        setState(() {
          _currentYaw = yaw;
          _progress = nextProgress;
          _isCompleted = done;
        });
      },
      onError: (_) {
        if (mounted) {
          setState(() => _error = 'Magnetometer / Rotation sensor unavailable.');
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
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);
    final tertiary = CupertinoColors.tertiaryLabel.resolveFrom(context);

    return HwTestPage(
      title: 'Magnetometer Test',
      instruction:
          'Slowly rotate your device in a full circle to calibrate and test the magnetometer.',
      canPass: _isCompleted,
      content: HwCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Column(
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(180, 180),
                    painter: _CompassRingPainter(
                      progress: _progress,
                      trackColor: tertiary,
                      progressColor: green,
                    ),
                  ),
                  Transform.rotate(
                    angle: -_currentYaw,
                    child: Icon(
                      CupertinoIcons.location_north_fill,
                      size: 110,
                      color: red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: red),
              )
            else if (_isCompleted)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: green),
                  const SizedBox(width: 6),
                  Text(
                    '360° Rotation Detected!',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: green),
                  ),
                ],
              )
            else
              Text(
                'Progress: ${(_progress * 100).round()}%',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompassRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;

  _CompassRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 8) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Dashed outer guide circle
    final dashPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const dashes = 36;
    const step = (math.pi * 2) / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * step, step * 0.4, false, dashPaint);
    }

    // Solid green progress arc starting from top (-pi / 2)
    if (progress > 0) {
      final arcPaint = Paint()
        ..color = progressColor
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress.clamp(0.0, 1.0), false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassRingPainter old) =>
      old.progress != progress || old.progressColor != progressColor;
}