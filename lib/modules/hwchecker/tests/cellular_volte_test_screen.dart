import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class CellularVolteTestScreen extends StatefulWidget {
  const CellularVolteTestScreen({super.key});

  @override
  State<CellularVolteTestScreen> createState() => _CellularVolteTestScreenState();
}

class _CellularVolteTestScreenState extends State<CellularVolteTestScreen> {
  String _carrierName = 'Detecting Carrier...';
  bool _cellularConnected = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final status = await HwNativeBridge.getConnectivityStatus();
    if (!mounted) return;
    setState(() {
      _carrierName = (status['carrierName'] as String?) ?? 'No SIM / Unknown';
      _cellularConnected = status['cellularConnected'] == true;
    });
  }

  void _showDialerInstructions() {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Test VoLTE Call'),
        content: const Text(
          'Open your Phone app and place a test call (such as your carrier\'s voicemail or balance check). '
          'Verify that audio is clear and mobile data stays active on 4G/LTE or 5G during the call.',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final orange = CupertinoColors.systemOrange.resolveFrom(context);
    final hasCarrier = _carrierName != 'No SIM / Unknown' && _carrierName != 'Detecting Carrier...';

    return HwTestPage(
      title: 'Cellular & VoLTE',
      instruction:
          'Verify cellular network registration, mobile data connectivity, and voice call quality.',
      canPass: hasCarrier || _cellularConnected,
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.10),
              ),
              child: Icon(
                CupertinoIcons.antenna_radiowaves_left_right,
                size: 40,
                color: accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _carrierName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                HwStatusPill(
                  icon: hasCarrier ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
                  text: hasCarrier ? 'SIM Registered' : 'No Active SIM',
                  color: hasCarrier ? green : orange,
                  active: true,
                ),
                HwStatusPill(
                  icon: _cellularConnected ? CupertinoIcons.arrow_up_arrow_down : CupertinoIcons.wifi_slash,
                  text: _cellularConnected ? 'Cellular Data Online' : 'Mobile Data Off / On Wi-Fi',
                  color: _cellularConnected ? green : orange,
                  active: _cellularConnected,
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                color: accent,
                borderRadius: BorderRadius.circular(14),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _showDialerInstructions();
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.phone_fill, size: 17, color: CupertinoColors.white),
                    SizedBox(width: 8),
                    Text(
                      'VoLTE Call Check Guide',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: CupertinoColors.white),
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