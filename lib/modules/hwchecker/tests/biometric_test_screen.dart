import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_media_bridge.dart';

class BiometricTestScreen extends StatefulWidget {
  const BiometricTestScreen({super.key});

  @override
  State<BiometricTestScreen> createState() => _BiometricTestScreenState();
}

class _BiometricTestScreenState extends State<BiometricTestScreen> {
  bool _verified = false;
  String _statusText = 'Ready to Scan';
  bool _isError = false;

  Future<void> _authenticate() async {
    try {
      final ok = await HwMediaBridge.authenticateBiometric();
      if (!mounted) return;
      setState(() {
        _verified = ok;
        _isError = false;
        _statusText = ok ? 'Biometric Sensor Verified' : 'Verification Incomplete';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _statusText = e.message ?? 'Biometric authentication failed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);
    final activeColor = _verified ? green : (_isError ? red : accent);

    return HwTestPage(
      title: 'Biometric Test',
      instruction:
          'Trigger the system biometric prompt and scan your enrolled fingerprint or face.',
      canPass: _verified,
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
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
                CupertinoIcons.lock_shield_fill,
                size: 46,
                color: activeColor,
              ),
            ),
            const SizedBox(height: 20),
            HwStatusPill(
              icon: _verified
                  ? CupertinoIcons.checkmark_circle_fill
                  : (_isError
                      ? CupertinoIcons.exclamationmark_triangle_fill
                      : CupertinoIcons.person_crop_circle),
              text: _statusText,
              color: _verified ? green : (_isError ? red : accent),
              active: _verified || _isError,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                color: accent,
                borderRadius: BorderRadius.circular(14),
                onPressed: _authenticate,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.lock_open_fill, size: 18, color: CupertinoColors.white),
                    SizedBox(width: 8),
                    Text(
                      'Authenticate Biometrics',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: CupertinoColors.white,
                      ),
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