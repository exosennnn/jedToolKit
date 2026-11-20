import 'package:flutter/cupertino.dart';
import '../hw_accent.dart';
import '../hw_test.dart';
import '../hw_widgets.dart';
import '../hw_media_bridge.dart';

class SpeakerTestScreen extends StatefulWidget {
  const SpeakerTestScreen({super.key});

  @override
  State<SpeakerTestScreen> createState() => _SpeakerTestScreenState();
}

class _SpeakerTestScreenState extends State<SpeakerTestScreen> {
  bool _isPlaying = false;
  bool _hasPlayedOnce = false;

  @override
  void dispose() {
    if (_isPlaying) {
      HwMediaBridge.stopSpeakerTone();
    }
    super.dispose();
  }

  Future<void> _toggleTone() async {
    if (_isPlaying) {
      await HwMediaBridge.stopSpeakerTone();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await HwMediaBridge.startSpeakerTone();
      if (mounted) {
        setState(() {
          _isPlaying = true;
          _hasPlayedOnce = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return HwTestPage(
      title: 'Speaker Test',
      instruction:
          'Turn up your media volume and play the 440 Hz reference tone. Listen for clear, distortion-free output.',
      canPass: _hasPlayedOnce,
      onComplete: (ok) async {
        if (_isPlaying) await HwMediaBridge.stopSpeakerTone();
        if (context.mounted) {
          Navigator.of(context).pop(ok ? HwTestState.passed : HwTestState.failed);
        }
      },
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
        child: Column(
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isPlaying ? accent.withOpacity(0.12) : hwLabel(context, 0.04),
              ),
              child: Icon(
                _isPlaying ? CupertinoIcons.speaker_3_fill : CupertinoIcons.speaker_2_fill,
                size: 44,
                color: _isPlaying ? accent : secondary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _isPlaying ? 'Playing 440 Hz Tone...' : 'Tone Stopped',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            HwStatusPill(
              icon: _hasPlayedOnce
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.waveform,
              text: _hasPlayedOnce ? 'Audio Output Triggered' : 'Tap Play to Test',
              color: green,
              active: _hasPlayedOnce,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                color: _isPlaying ? CupertinoColors.systemOrange.resolveFrom(context) : accent,
                borderRadius: BorderRadius.circular(14),
                onPressed: _toggleTone,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isPlaying ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill,
                      size: 18,
                      color: CupertinoColors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isPlaying ? 'Stop Tone' : 'Play Test Tone',
                      style: const TextStyle(
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