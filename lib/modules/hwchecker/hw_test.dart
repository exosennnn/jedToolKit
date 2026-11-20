import 'package:flutter/cupertino.dart';

/// Result of a test. [partial] is only used by Physical Buttons.
enum HwTestState { notTested, passed, failed, partial }

class HwTest {
  /// Titles are identical to the iOS app. They are the lookup keys everywhere.
  final String title;
  final String subtitle;
  final IconData icon;
  HwTestState state;

  HwTest({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.state = HwTestState.notTested,
  });
}

class HwSection {
  final String title;
  final List<HwTest> tests;
  HwSection(this.title, this.tests);
}

/// Same sections, order, titles and subtitles as HardwareCheckViewModel.swift.
/// Icons are the closest CupertinoIcons to the SF Symbols used on iOS.
List<HwSection> buildHwSections() => [
  HwSection('Core Components', [
    HwTest(
      title: 'Display Test',
      subtitle: 'Check for dead pixels, burn-in, or discoloration',
      icon: CupertinoIcons.tv,
    ),
    HwTest(
      title: 'Touch Responsiveness',
      subtitle: 'Swipe across the entire screen to check touch response',
      icon: CupertinoIcons.hand_draw_fill,
    ),
    HwTest(
      title: 'Physical Buttons Test',
      subtitle: 'Test volume, power, and other hardware buttons',
      icon: CupertinoIcons.device_phone_portrait,
    ),
  ]),
  HwSection('Audio & Visual', [
    HwTest(
      title: 'Speaker Test',
      subtitle: 'Test the main speaker output',
      icon: CupertinoIcons.speaker_3_fill,
    ),
    HwTest(
      title: 'Microphone Test',
      subtitle: 'Record and play back audio',
      icon: CupertinoIcons.mic_fill,
    ),
    HwTest(
      title: 'Camera Test',
      subtitle: 'Test all front and rear cameras',
      icon: CupertinoIcons.camera_fill,
    ),
    HwTest(
      title: 'LED Flash Test',
      subtitle: "Test the camera's LED flash (torch)",
      icon: CupertinoIcons.lightbulb_fill,
    ),
  ]),
  HwSection('Sensors', [
    HwTest(
      title: 'Biometric Test',
      subtitle: 'Test Face ID or Touch ID sensor',
      icon: CupertinoIcons.lock_shield_fill,
    ),
    HwTest(
      title: 'Accelerometer Test',
      subtitle: 'Test motion and shake detection',
      icon: CupertinoIcons.cube,
    ),
    HwTest(
      title: 'Gyroscope Test',
      subtitle: 'Test device rotation tracking',
      icon: CupertinoIcons.rotate_right,
    ),
    HwTest(
      title: 'Magnetometer Test',
      subtitle: 'Test the compass and magnetic sensor',
      icon: CupertinoIcons.location_north_fill,
    ),
    HwTest(
      title: 'Proximity Sensor Test',
      subtitle: 'Test the sensor used during phone calls',
      icon: CupertinoIcons.dot_radiowaves_left_right,
    ),
    HwTest(
      title: 'Vibration Test',
      subtitle: 'Test the Taptic Engine with haptics',
      icon: CupertinoIcons.bell_fill,
    ),
    HwTest(
      title: 'Brightness Test',
      subtitle: 'Test manual and automatic screen brightness',
      icon: CupertinoIcons.sun_max_fill,
    ),
  ]),
  HwSection('Connectivity', [
    HwTest(
      title: 'Wi-Fi Connectivity Test',
      subtitle: 'Check the Wi-Fi connection status',
      icon: CupertinoIcons.wifi,
    ),
    HwTest(
      title: 'Bluetooth Connectivity Test',
      subtitle: 'Check the Bluetooth module status',
      icon: CupertinoIcons.bluetooth,
    ),
    HwTest(
      title: 'Cellular & VoLTE Test',
      subtitle: 'Verify cellular data and VoLTE functionality',
      icon: CupertinoIcons.antenna_radiowaves_left_right,
    ),
    HwTest(
      title: 'Charger Test',
      subtitle: 'Verify charging port functionality',
      icon: CupertinoIcons.bolt_fill,
    ),
  ]),
  HwSection('Tools', [
    HwTest(
      title: 'Battery Health Info',
      subtitle: 'View live charge level and thermal state',
      icon: CupertinoIcons.battery_charging,
    ),
  ]),
];