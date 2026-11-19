enum HwTestState { notTested, passed, failed }

class HwTest {
  final String id;
  final String title;
  final String description;
  final bool implemented;
  HwTestState state;

  HwTest({
    required this.id,
    required this.title,
    required this.description,
    this.implemented = false,
    this.state = HwTestState.notTested,
  });
}

/// Tests that need you to look, touch, or confirm. Planned tests are listed
/// honestly but can't run yet, because they need native work.
List<HwTest> buildHwTests() => [
      HwTest(
        id: 'display',
        title: 'Display',
        description:
            'Solid colors across the screen to spot dead or stuck pixels, tint, and burn-in.',
        implemented: true,
      ),
      HwTest(
        id: 'touch',
        title: 'Touchscreen',
        description: 'Tap every cell in a grid to check touches register across the screen.',
        implemented: true,
      ),
      HwTest(
        id: 'vibration',
        title: 'Vibration',
        description: 'Needs a native bridge.',
      ),
      HwTest(
        id: 'audio',
        title: 'Speakers & microphone',
        description: 'Needs audio playback and recording support.',
      ),
      HwTest(
        id: 'cameras',
        title: 'Cameras',
        description: 'Preview each lens.',
      ),
      HwTest(
        id: 'sensors',
        title: 'Sensors',
        description: 'Live accelerometer and gyroscope readings.',
      ),
      HwTest(
        id: 'buttons',
        title: 'Buttons',
        description: 'Volume and power button detection where Android allows it.',
      ),
      HwTest(
        id: 'connectivity',
        title: 'Wi-Fi & Bluetooth',
        description: 'Radio state and scan results.',
      ),
    ];