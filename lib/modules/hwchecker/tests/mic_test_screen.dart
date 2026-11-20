import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../hw_accent.dart';
import '../hw_test.dart';
import '../hw_widgets.dart';
import '../hw_media_bridge.dart';

class MicTestScreen extends StatefulWidget {
  const MicTestScreen({super.key});

  @override
  State<MicTestScreen> createState() => _MicTestScreenState();
}

class _MicTestScreenState extends State<MicTestScreen> {
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _hasRecorded = false;
  bool _hasPlayedBack = false;
  double _level = 0.0;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = HwMediaBridge.micEvents().listen((event) {
      if (!mounted) return;
      if (event['playbackDone'] == true) {
        setState(() => _isPlaying = false);
      } else if (event.containsKey('level')) {
        setState(() => _level = (event['level'] as num).toDouble());
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    HwMediaBridge.stopMicRecord();
    HwMediaBridge.stopMicPlayback();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      await HwMediaBridge.stopMicRecord();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _level = 0.0;
          _hasRecorded = true;
        });
      }
    } else {
      try {
        await HwMediaBridge.startMicRecord();
        if (mounted) {
          setState(() {
            _isRecording = true;
            _isPlaying = false;
            _error = null;
          });
        }
      } on PlatformException catch (e) {
        if (mounted) {
          setState(() => _error = e.message ?? 'Microphone permission denied.');
        }
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await HwMediaBridge.stopMicPlayback();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      try {
        await HwMediaBridge.playMicRecording();
        if (mounted) {
          setState(() {
            _isPlaying = true;
            _hasPlayedBack = true;
            _error = null;
          });
        }
      } on PlatformException catch (e) {
        if (mounted) {
          setState(() => _error = e.message ?? 'Unable to play recording.');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);

    return HwTestPage(
      title: 'Microphone Test',
      instruction:
          'Record a short voice sample while watching the level meter, then play it back to confirm clarity.',
      canPass: _hasRecorded && _hasPlayedBack,
      onComplete: (ok) async {
        await HwMediaBridge.stopMicRecord();
        await HwMediaBridge.stopMicPlayback();
        if (context.mounted) {
          Navigator.of(context).pop(ok ? HwTestState.passed : HwTestState.failed);
        }
      },
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
        child: Column(
          children: [
            // 12-segment live amplitude bar meter
            SizedBox(
              height: 76,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(12, (i) {
                  final threshold = (i + 1) / 12.0;
                  final active = _isRecording && _level >= threshold * 0.75;
                  final barHeight = 16.0 + (i * 4.5);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      width: 10,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: active ? (i > 9 ? red : green) : hwLabel(context, 0.08),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 18),
            HwStatusPill(
              icon: _error != null
                  ? CupertinoIcons.exclamationmark_triangle_fill
                  : (_hasPlayedBack
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.mic_fill),
              text: _error ??
                  (_isRecording
                      ? 'Recording... Speak into Mic'
                      : (_isPlaying
                          ? 'Playing Back Sample...'
                          : (_hasPlayedBack
                              ? 'Playback Verified'
                              : (_hasRecorded ? 'Tap Play to Verify' : 'Ready to Record')))),
              color: _error != null ? red : green,
              active: _hasPlayedBack || _error != null,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      color: _isRecording ? red : accent,
                      borderRadius: BorderRadius.circular(14),
                      onPressed: _toggleRecord,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isRecording ? CupertinoIcons.stop_fill : CupertinoIcons.mic_fill,
                            size: 17,
                            color: CupertinoColors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isRecording ? 'Stop' : 'Record',
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      color: _hasRecorded && !_isRecording
                          ? green
                          : CupertinoColors.systemGrey4.resolveFrom(context),
                      borderRadius: BorderRadius.circular(14),
                      onPressed: (_hasRecorded && !_isRecording) ? _togglePlayback : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isPlaying ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill,
                            size: 17,
                            color: CupertinoColors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isPlaying ? 'Stop' : 'Play',
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}