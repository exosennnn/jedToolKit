import 'package:flutter/cupertino.dart';

/// Id of the Home tab. It is always the first tab and can't be moved or removed.
const String kHomeModuleId = 'home';

/// Maximum number of tabs in the dock (Home included).
const int kMaxDockTabs = 3;

/// A module that can be placed in the dock.
class JedTabModule {
  final String id;
  final String title;
  final IconData icon;
  final CupertinoDynamicColor color;

  const JedTabModule(this.id, this.title, this.icon, this.color);
}

/// Every module Customize Tab Bar can offer. Ids match the ids used on Home.
const List<JedTabModule> kTabModules = [
  JedTabModule(kHomeModuleId, 'jedHome', CupertinoIcons.house_fill,
      CupertinoColors.systemBlue),
  JedTabModule('phoneinfo', 'jedPhoneInfo', CupertinoIcons.device_phone_portrait,
      CupertinoColors.systemBlue),
  JedTabModule('hwchecker', 'jedHWChecker', CupertinoIcons.wrench_fill,
      CupertinoColors.systemOrange),
  JedTabModule('benchmark', 'jedBenchmark 2', CupertinoIcons.speedometer,
      CupertinoColors.systemPurple),
  JedTabModule('ram', 'jedRAMChecker', CupertinoIcons.memories,
      CupertinoColors.systemIndigo),
  JedTabModule('disk', 'jedDiskChecker', CupertinoIcons.folder_fill,
      CupertinoColors.systemGreen),
];

JedTabModule? tabModuleById(String id) {
  for (final m in kTabModules) {
    if (m.id == id) return m;
  }
  return null;
}

/// Same defaults as the dock had before customization existed.
const List<String> kDefaultTabIds = [kHomeModuleId, 'phoneinfo', 'hwchecker'];
