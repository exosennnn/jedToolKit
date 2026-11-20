import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../hw_accent.dart';
import '../hw_test.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

enum _BtnType { volumeUp, volumeDown, power }
enum _BtnStatus { notTested, passed, failed }

class PhysicalButtonsTestScreen extends StatefulWidget {
  const PhysicalButtonsTestScreen({super.key});

  @override
  State<PhysicalButtonsTestScreen> createState() => _PhysicalButtonsTestScreenState();
}

class _PhysicalButtonsTestScreenState extends State<PhysicalButtonsTestScreen> {
  final Map<_BtnType, _BtnStatus> _states = {
    _BtnType.volumeUp: _BtnStatus.notTested,
    _BtnType.volumeDown: _BtnStatus.notTested,
    _BtnType.power: _BtnStatus.notTested,
  };
  StreamSubscription<int>? _keySub;

  @override
  void initState() {
    super.initState();
    HwNativeBridge.setKeyIntercept(true);
    _keySub = HwNativeBridge.keyPressStream().listen((keyCode) {
      if (!mounted) return;
      // Android KeyEvent.KEYCODE_VOLUME_UP = 24, KEYCODE_VOLUME_DOWN = 25
      final btn = keyCode == 24 ? _BtnType.volumeUp : (keyCode == 25 ? _BtnType.volumeDown : null);
      if (btn != null && _states[btn] != _BtnStatus.failed) {
        setState(() => _states[btn] = _BtnStatus.passed);
      }
    });
  }

  @override
  void dispose() {
    _keySub?.cancel();
    HwNativeBridge.setKeyIntercept(false);
    super.dispose();
  }

  String _title(_BtnType b) => switch (b) {
    _BtnType.volumeUp => 'Volume Up',
    _BtnType.volumeDown => 'Volume Down',
    _BtnType.power => 'Power',
  };

  IconData _icon(_BtnType b) => switch (b) {
    _BtnType.volumeUp => CupertinoIcons.speaker_2_fill,
    _BtnType.volumeDown => CupertinoIcons.speaker_1_fill,
    _BtnType.power => CupertinoIcons.power,
  };

  @override
  Widget build(BuildContext context) {
    final buttons = _BtnType.values;
    final passedCount = _states.values.where((s) => s == _BtnStatus.passed).length;
    final failedCount = _states.values.where((s) => s == _BtnStatus.failed).length;
    final canPass = passedCount == buttons.length;
    final canPartial = passedCount > 0 && failedCount > 0;
    final canFail = failedCount > 0 && passedCount == 0;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Buttons Test'),
        backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Press Volume buttons to test automatically, or manually mark each button as Passed or Failed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    HwCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < buttons.length; i++) ...[
                            _buildRow(context, buttons[i], i),
                            if (i != buttons.length - 1)
                              Container(height: 0.5, margin: const EdgeInsets.only(left: 72), color: hwLabel(context, 0.05)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildThreeButtonBar(context, canPass: canPass, canPartial: canPartial, canFail: canFail),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, _BtnType btn, int index) {
    final status = _states[btn]!;
    final color = HwAccent.instance.iconColor(context, index);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
            child: Icon(_icon(btn), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title(btn), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      status == _BtnStatus.passed
                          ? CupertinoIcons.checkmark_circle_fill
                          : (status == _BtnStatus.failed ? CupertinoIcons.xmark_circle_fill : CupertinoIcons.question_circle_fill),
                      size: 12,
                      color: status == _BtnStatus.passed ? green : (status == _BtnStatus.failed ? red : secondary),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      status == _BtnStatus.passed ? 'Passed' : (status == _BtnStatus.failed ? 'Failed' : 'Not Tested'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: status == _BtnStatus.passed ? green : (status == _BtnStatus.failed ? red : secondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (status == _BtnStatus.notTested) ...[
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minSize: 0,
              color: green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(100),
              onPressed: () => setState(() => _states[btn] = _BtnStatus.passed),
              child: Text('Pass', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: green)),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minSize: 0,
              color: red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(100),
              onPressed: () => setState(() => _states[btn] = _BtnStatus.failed),
              child: Text('Fail', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: red)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThreeButtonBar(BuildContext context, {required bool canPass, required bool canPartial, required bool canFail}) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final off = CupertinoColors.systemGrey4.resolveFrom(context);

    Widget pill(String label, Color color, bool enabled, HwTestState result) => Expanded(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        onPressed: enabled ? () => Navigator.of(context).pop(result) : null,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: enabled ? color : off, borderRadius: BorderRadius.circular(12)),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: enabled ? CupertinoColors.white : CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ),
    );

    return Container(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
            child: Row(
              children: [
                pill('Pass Test', CupertinoColors.systemGreen.resolveFrom(context), canPass, HwTestState.passed),
                const SizedBox(width: 10),
                pill('Partial', CupertinoColors.systemOrange.resolveFrom(context), canPartial, HwTestState.partial),
                const SizedBox(width: 10),
                pill('Fail Test', CupertinoColors.systemRed.resolveFrom(context), canFail, HwTestState.failed),
              ],
            ),
          ),
        ],
      ),
    );
  }
}