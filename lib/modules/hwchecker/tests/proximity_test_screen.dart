import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class ProximityTestScreen extends StatefulWidget {
  const ProximityTestScreen({super.key});

  @override
  State<ProximityTestScreen> createState() => _ProximityTestScreenState();
}

class _ProximityTestScreenState extends State<ProximityTestScreen> {
  bool _isSensorCovered = false;
  bool _hasTriggeredSensor = false;
  String? _fallbackNote;
  double? _firstDistance;
  double? _distance;
  double? _maxRange;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = HwNativeBridge.sensorStream('proximity').listen(
      (data) {
        if (!mounted) return;
        final dist = (data['distance'] as num?)?.toDouble();
        final max = (data['maxRange'] as num?)?.toDouble();
        var covered = data['isCovered'] == true;
        // Also accept any change from the first reading as a real trigger.
        _firstDistance ??= dist;
        final changed = dist != null && _firstDistance != null && dist != _firstDistance;
        if (changed && dist! < _firstDistance!) covered = true;
        if (dist == _distance && covered == _isSensorCovered) return; // nothing new
        setState(() {
          _distance = dist;
          _maxRange = max;
          _isSensorCovered = covered;
          if (covered || changed) _hasTriggeredSensor = true;
        });
      },
      onError: (e) {
        // Mirrors iOS fallback if hardware proximity sensor is absent (e.g. tablets)
        if (mounted) {
          setState(() {
            _hasTriggeredSensor = true;
            _fallbackNote = 'Proximity sensor not reported by Android (fallback)';
          });
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

    final statusText = _fallbackNote ??
        (_isSensorCovered
            ? 'Sensor Obstructed'
            : (_hasTriggeredSensor
                ? 'Sensor Triggered Successfully'
                : 'Waiting for Obstruction...'));

    return HwTestPage(
      title: 'Proximity Test',
      instruction:
          'Cover the area near the top speaker to test the proximity sensor.',
      canPass: _hasTriggeredSensor,
      content: HwCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Column(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isSensorCovered
                    ? green.withOpacity(0.12)
                    : accent.withOpacity(0.08),
              ),
              child: Icon(
                _isSensorCovered
                    ? CupertinoIcons.hand_raised_fill
                    : CupertinoIcons.dot_radiowaves_left_right,
                size: 48,
                color: _isSensorCovered ? green : accent,
              ),
            ),
            const SizedBox(height: 16),
            if (_distance != null)
              Text(
                'Reading: ${_distance!.toStringAsFixed(1)} cm'
                '${_maxRange != null ? '  (max ${_maxRange!.toStringAsFixed(1)})' : ''}',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            const SizedBox(height: 16),
            HwStatusPill(
              icon: _hasTriggeredSensor
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.dot_radiowaves_left_right,
              text: statusText,
              color: green,
              active: _hasTriggeredSensor,
            ),
          ],
        ),
      ),
    );
  }
}