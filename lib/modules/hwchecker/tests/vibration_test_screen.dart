import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class VibrationTestScreen extends StatefulWidget {
  const VibrationTestScreen({super.key});

  @override
  State<VibrationTestScreen> createState() => _VibrationTestScreenState();
}

class _VibrationTestScreenState extends State<VibrationTestScreen> {
  bool _isTesting = false;
  bool _completed = false;
  String _statusText = 'Tap the button to start.';
  double _rippleScale = 1.0;
  Timer? _pulseTimer;

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  Future<void> _triggerTest() async {
    _pulseTimer?.cancel();
    setState(() {
      _isTesting = true;
      _statusText = 'Testing...';
    });

    // Light -> Medium -> Heavy pulses mirroring TapticTestViewController.swift
    final steps = [
      (delay: 300, duration: 50, amp: 80, scale: 1.3),
      (delay: 800, duration: 90, amp: 160, scale: 1.6),
      (delay: 1500, duration: 140, amp: 255, scale: 2.0),
    ];

    for (final s in steps) {
      Future.delayed(Duration(milliseconds: s.delay), () {
        if (!mounted) return;
        setState(() => _rippleScale = s.scale);
        HwNativeBridge.vibrate(durationMs: s.duration, amplitude: s.amp);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _rippleScale = 1.0);
        });
      });
    }

    // Continuous vibration phase (1.5s at 250ms intervals)
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      var elapsed = 0;
      _pulseTimer = Timer.periodic(const Duration(milliseconds: 250), (t) {
        if (!mounted) { t.cancel(); return; }
        HwNativeBridge.vibrate(durationMs: 120, amplitude: 180);
        elapsed += 250;
        if (elapsed >= 1500) {
          t.cancel();
          setState(() {
            _isTesting = false;
            _completed = true;
            _statusText = 'Did you feel the vibrations correctly?';
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return HwTestPage(
      title: 'Vibration Test',
      instruction: 'Feel the dynamic sequence of structural vibrations. Confirm if the hardware haptics operate properly.',
      canPass: _completed,
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
        child: Column(
          children: [
            SizedBox(
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedScale(
                    scale: _rippleScale,
                    duration: const Duration(milliseconds: 350),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent.withOpacity(0.25), width: 2),
                      ),
                    ),
                  ),
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isTesting ? accent.withOpacity(0.12) : hwLabel(context, 0.04),
                    ),
                    child: Icon(
                      _isTesting ? CupertinoIcons.waveform_path : CupertinoIcons.dot_radiowaves_left_right,
                      size: 36,
                      color: _isTesting ? accent : secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            HwStatusPill(
              icon: _completed ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
              text: _statusText,
              color: green,
              active: _completed,
            ),
            if (!_completed) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  color: _isTesting ? CupertinoColors.systemGrey4.resolveFrom(context) : accent,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _isTesting ? null : _triggerTest,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.play_fill, size: 18, color: CupertinoColors.white),
                      SizedBox(width: 8),
                      Text('Test Vibration', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: CupertinoColors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}