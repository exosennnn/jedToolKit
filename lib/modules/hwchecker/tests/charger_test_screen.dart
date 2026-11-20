import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class ChargerTestScreen extends StatefulWidget {
  const ChargerTestScreen({super.key});

  @override
  State<ChargerTestScreen> createState() => _ChargerTestScreenState();
}

class _ChargerTestScreenState extends State<ChargerTestScreen> {
  bool _isCharging = false;
  int _batteryLevel = 0;
  String _powerSource = 'Internal Battery Power';
  bool _detectedOnce = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollBattery();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollBattery());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollBattery() async {
    final data = await HwNativeBridge.getBatteryAndAccessories();
    if (!mounted) return;

    final charging = data['isCharging'] == true;
    if (charging && !_detectedOnce) {
      HapticFeedback.mediumImpact();
    }

    setState(() {
      _isCharging = charging;
      if (charging) _detectedOnce = true;
      _batteryLevel = (data['level'] as num?)?.toInt() ?? 0;
      _powerSource = (data['powerSource'] as String?) ?? 'Internal Battery Power';
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final activeColor = _isCharging ? green : accent;

    return HwTestPage(
      title: 'Charger Test',
      instruction: 'Connect a USB-C / charging cable or place the device on a wireless charger.',
      canPass: _detectedOnce,
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
        child: Column(
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: activeColor.withOpacity(0.10),
              ),
              child: Icon(
                _isCharging ? CupertinoIcons.battery_charging : CupertinoIcons.bolt_slash_fill,
                size: 46,
                color: activeColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '$_batteryLevel%',
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _powerSource,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            HwStatusPill(
              icon: _detectedOnce
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.bolt_fill,
              text: _isCharging
                  ? 'Charging Power Detected'
                  : (_detectedOnce ? 'Charger Verified' : 'Waiting for Charger...'),
              color: green,
              active: _detectedOnce,
            ),
          ],
        ),
      ),
    );
  }
}