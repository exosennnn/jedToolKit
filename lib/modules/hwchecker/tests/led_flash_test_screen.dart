import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../hw_accent.dart';
import '../hw_test.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class LedFlashTestScreen extends StatefulWidget {
  const LedFlashTestScreen({super.key});

  @override
  State<LedFlashTestScreen> createState() => _LedFlashTestScreenState();
}

class _LedFlashTestScreenState extends State<LedFlashTestScreen> {
  bool _isFlashOn = false;
  String? _error;

  @override
  void dispose() {
    if (_isFlashOn) {
      HwNativeBridge.setTorch(false);
    }
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    try {
      final next = !_isFlashOn;
      await HwNativeBridge.setTorch(next);
      if (mounted) setState(() { _isFlashOn = next; _error = null; });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Unable to toggle LED flash.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final activeColor = _isFlashOn ? CupertinoColors.systemYellow.resolveFrom(context) : accent;

    return HwTestPage(
      title: 'LED Flash Test',
      instruction: 'Tap the button below to toggle the LED flash. Observe if the light turns on and off correctly.',
      onComplete: (ok) async {
        if (_isFlashOn) await HwNativeBridge.setTorch(false);
        if (context.mounted) Navigator.of(context).pop(ok ? HwTestState.passed : HwTestState.failed);
      },
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: activeColor.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isFlashOn ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt_slash_fill,
                size: 40,
                color: activeColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _error ?? (_isFlashOn ? 'Flash is Active' : 'Flash is Inactive'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _error != null ? CupertinoColors.systemRed.resolveFrom(context) : null,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                color: _isFlashOn ? CupertinoColors.systemOrange.resolveFrom(context) : accent,
                borderRadius: BorderRadius.circular(14),
                onPressed: _toggleFlash,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isFlashOn ? CupertinoIcons.bolt_slash_fill : CupertinoIcons.bolt_fill, size: 18, color: CupertinoColors.white),
                    const SizedBox(width: 8),
                    Text(
                      _isFlashOn ? 'Turn Off Flash' : 'Turn On Flash',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: CupertinoColors.white),
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