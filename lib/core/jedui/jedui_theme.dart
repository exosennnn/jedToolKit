import 'package:flutter/cupertino.dart';
import '../../modules/phoneinfo/phone_info.dart' show DataStatus;

/// jedUI theme: iOS-style grouped backgrounds, system blue accent,
/// and Apple's adaptive system colors so light and dark mode both work.
class JedTheme {
  static const CupertinoThemeData light = CupertinoThemeData(
    primaryColor: CupertinoColors.systemBlue,
    scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
    barBackgroundColor: CupertinoColors.systemGroupedBackground,
  );

  /// Theme driven by Settings: [brightness] null = follow the system,
  /// [primary] is the chosen accent color.
  static CupertinoThemeData build({
    Brightness? brightness,
    required Color primary,
  }) {
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: primary,
      scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
      barBackgroundColor: CupertinoColors.systemGroupedBackground,
    );
  }

  /// Status colors shared by every module.
  static Color statusColor(BuildContext context, DataStatus status) {
    switch (status) {
      case DataStatus.available:
        return CupertinoColors.label.resolveFrom(context);
      case DataStatus.restricted:
      case DataStatus.permissionRequired:
        return CupertinoColors.systemOrange.resolveFrom(context);
      case DataStatus.unsupported:
      case DataStatus.notTested:
        return CupertinoColors.secondaryLabel.resolveFrom(context);
      case DataStatus.error:
        return CupertinoColors.systemRed.resolveFrom(context);
    }
  }
}