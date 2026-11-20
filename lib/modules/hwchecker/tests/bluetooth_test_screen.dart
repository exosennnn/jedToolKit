import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class BluetoothTestScreen extends StatefulWidget {
  const BluetoothTestScreen({super.key});

  @override
  State<BluetoothTestScreen> createState() => _BluetoothTestScreenState();
}

class _BluetoothTestScreenState extends State<BluetoothTestScreen> {
  String _btState = 'checking';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkBluetooth());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkBluetooth() async {
    final status = await HwNativeBridge.getConnectivityStatus();
    if (!mounted) return;
    setState(() {
      _btState = (status['btState'] as String?) ?? 'unsupported';
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final orange = CupertinoColors.systemOrange.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);

    final isOn = _btState == 'poweredOn';
    final isOff = _btState == 'poweredOff';

    final (headline, subtitle, badgeColor) = switch (_btState) {
      'poweredOn' => (
          'Bluetooth is Powered On',
          'Bluetooth radio is active and ready for pairing.',
          green
        ),
      'poweredOff' => (
          'Bluetooth is Turned Off',
          'Turn on Bluetooth in Quick Settings or System Settings.',
          orange
        ),
      'checking' => (
          'Checking Bluetooth...',
          'Querying local Bluetooth adapter state...',
          accent
        ),
      _ => (
          'Bluetooth Unsupported',
          'This device does not report a Bluetooth adapter.',
          red
        ),
    };

    return HwTestPage(
      title: 'Bluetooth Test',
      instruction: 'Verify that the Bluetooth hardware module initializes and turns on properly.',
      canPass: isOn,
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: badgeColor.withOpacity(0.10),
              ),
              child: Icon(
                CupertinoIcons.bluetooth,
                size: 42,
                color: badgeColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            HwStatusPill(
              icon: isOn
                  ? CupertinoIcons.checkmark_circle_fill
                  : (isOff ? CupertinoIcons.exclamationmark_triangle_fill : CupertinoIcons.xmark_circle_fill),
              text: isOn ? 'Module Ready' : (isOff ? 'Radio Disabled' : 'Unavailable'),
              color: badgeColor,
              active: true,
            ),
          ],
        ),
      ),
    );
  }
}