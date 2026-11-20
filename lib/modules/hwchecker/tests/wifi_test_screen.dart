import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class WifiTestScreen extends StatefulWidget {
  const WifiTestScreen({super.key});

  @override
  State<WifiTestScreen> createState() => _WifiTestScreenState();
}

class _WifiTestScreenState extends State<WifiTestScreen> {
  bool _isChecking = true;
  bool _isConnected = false;
  String _statusHeadline = 'Checking Connection...';
  String _detailText = 'Verifying active Wi-Fi interface...';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkStatus(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isChecking = true);
    }
    final status = await HwNativeBridge.getConnectivityStatus();
    if (!mounted) return;

    final wifi = status['wifiConnected'] == true;
    final cell = status['cellularConnected'] == true;
    final other = status['otherConnected'] == true;

    setState(() {
      _isChecking = false;
      _isConnected = wifi;
      if (wifi) {
        _statusHeadline = 'Connected via Wi-Fi';
        _detailText = 'Wi-Fi interface is active and online.';
      } else if (cell) {
        _statusHeadline = 'On Cellular Data';
        _detailText = 'Connect to a Wi-Fi network to complete this test.';
      } else if (other) {
        _statusHeadline = 'Connected (Ethernet/Other)';
        _detailText = 'Active connection is not Wi-Fi.';
      } else {
        _statusHeadline = 'Not Connected';
        _detailText = 'No active Wi-Fi connection detected.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);
    final activeColor = _isConnected ? green : (_isChecking ? accent : red);

    return HwTestPage(
      title: 'Wi-Fi Connectivity',
      instruction: 'Ensure your device is connected to an active Wi-Fi network.',
      canPass: _isConnected,
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: activeColor.withOpacity(0.10),
              ),
              child: Icon(
                _isConnected ? CupertinoIcons.wifi : CupertinoIcons.wifi_slash,
                size: 40,
                color: activeColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _statusHeadline,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _detailText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            HwStatusPill(
              icon: _isConnected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.xmark_circle_fill,
              text: _isConnected ? 'Wi-Fi Active' : 'Wi-Fi Inactive',
              color: activeColor,
              active: true,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                onPressed: () => _checkStatus(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.refresh, size: 17, color: accent),
                    const SizedBox(width: 8),
                    Text(
                      'Re-check Connection',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}