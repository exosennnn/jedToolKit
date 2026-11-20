import 'package:flutter/cupertino.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class BrightnessTestScreen extends StatefulWidget {
  const BrightnessTestScreen({super.key});

  @override
  State<BrightnessTestScreen> createState() => _BrightnessTestScreenState();
}

class _BrightnessTestScreenState extends State<BrightnessTestScreen> {
  double _brightness = 0.5;
  bool _minReached = false;
  bool _maxReached = false;

  @override
  void initState() {
    super.initState();
    _initBrightness();
  }

  Future<void> _initBrightness() async {
    final current = await HwNativeBridge.getBrightness();
    if (!mounted) return;
    setState(() {
      _brightness = current;
      if (current <= 0.15) _minReached = true;
      if (current >= 0.85) _maxReached = true;
    });
  }

  @override
  void dispose() {
    HwNativeBridge.setBrightness(-1.0); // Restore system automatic brightness
    super.dispose();
  }

  void _onChanged(double v) {
    setState(() {
      _brightness = v;
      if (v <= 0.15) _minReached = true;
      if (v >= 0.85) _maxReached = true;
    });
    HwNativeBridge.setBrightness(v);
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return HwTestPage(
      title: 'Brightness Test',
      instruction: 'Drag the slider to test the full range of your screen\'s brightness.',
      canPass: _minReached && _maxReached,
      content: HwCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Column(
          children: [
            Text(
              '${(_brightness * 100).round()}%',
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(CupertinoIcons.sun_min_fill, size: 18, color: _minReached ? green : secondary),
                Expanded(
                  child: CupertinoSlider(
                    value: _brightness,
                    activeColor: accent,
                    onChanged: _onChanged,
                  ),
                ),
                Icon(CupertinoIcons.sun_max_fill, size: 22, color: _maxReached ? green : secondary),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                HwStatusPill(
                  icon: _minReached ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                  text: 'Min Reach (≤15%)',
                  color: green,
                  active: _minReached,
                ),
                HwStatusPill(
                  icon: _maxReached ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                  text: 'Max Reach (≥85%)',
                  color: green,
                  active: _maxReached,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}