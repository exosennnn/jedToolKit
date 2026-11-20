import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/hwchecker/hw_accent.dart';
import 'tab_modules.dart';

/// iOS: AppThemeViewModel. Index order matches iOS (0 System, 1 Light, 2 Dark).
enum AppThemeChoice { system, light, dark }

extension AppThemeChoiceX on AppThemeChoice {
  String get label => const ['System', 'Light', 'Dark'][index];
}

/// iOS: one entry of AccentColorManager.availableColors.
class AccentOption {
  final String name;
  final CupertinoDynamicColor color;
  const AccentOption(this.name, this.color);
}

/// Android counterpart of AccentColorManager + the theme / tab-bar preferences.
/// Load once in main(), then listen to it (ListenableBuilder) wherever the UI
/// depends on these values.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  // Same keys as iOS so the meaning is identical.
  static const _kTheme = 'appTheme';
  static const _kAccent = 'appAccentColorName';
  static const _kMulticolor = 'isMulticolorModeEnabled';
  static const _kTabs = 'customTabBarModules';
  static const _kDefaultTab = 'defaultTab';

  static const List<AccentOption> accents = [
    AccentOption('Default Blue', CupertinoColors.systemBlue),
    AccentOption('Indigo', CupertinoColors.systemIndigo),
    AccentOption('Purple', CupertinoColors.systemPurple),
    AccentOption('Pink', CupertinoColors.systemPink),
    AccentOption('Red', CupertinoColors.systemRed),
    AccentOption('Orange', CupertinoColors.systemOrange),
    AccentOption('Green', CupertinoColors.systemGreen),
    AccentOption('Teal', CupertinoColors.systemTeal),
    AccentOption('Monochrome', CupertinoColors.label), // dynamic: black / white
    AccentOption('Graphite', CupertinoColors.systemGrey),
  ];

  /// iOS: AccentColorManager.fixedRainbowColors (used in multicolor mode).
  static const List<CupertinoDynamicColor> rainbow = [
    CupertinoColors.systemGrey,
    CupertinoColors.systemOrange,
    CupertinoColors.systemMint,
    CupertinoColors.systemRed,
    CupertinoColors.systemPurple,
    CupertinoColors.systemGreen,
    CupertinoColors.systemTeal,
    CupertinoColors.systemBlue,
    CupertinoColors.systemIndigo,
    CupertinoColors.systemCyan,
  ];

  AppThemeChoice _theme = AppThemeChoice.system;
  String _accentName = 'Default Blue';
  bool _multicolor = false;
  List<String> _tabIds = List.of(kDefaultTabIds);
  String _defaultTabId = kHomeModuleId;

  // ---------------------------------------------------------------- getters

  AppThemeChoice get themeChoice => _theme;

  /// null = follow the system.
  Brightness? get brightness => switch (_theme) {
        AppThemeChoice.system => null,
        AppThemeChoice.light => Brightness.light,
        AppThemeChoice.dark => Brightness.dark,
      };

  AccentOption get accentOption =>
      accents.firstWhere((a) => a.name == _accentName, orElse: () => accents.first);
  String get accentName => accentOption.name;
  CupertinoDynamicColor get accent => accentOption.color;
  bool get multicolor => _multicolor;

  /// Color for the Nth icon: rainbow in multicolor mode, otherwise the accent.
  CupertinoDynamicColor tintFor(int index) =>
      _multicolor ? rainbow[index % rainbow.length] : accent;

  /// iOS: contrastingForegroundColor.
  Color contrastingForeground(BuildContext context) => _accentName == 'Monochrome'
      ? CupertinoColors.systemBackground.resolveFrom(context)
      : CupertinoColors.white;

  List<String> get tabIds => List.unmodifiable(_tabIds);
  String get defaultTabId => _defaultTabId;

  // ------------------------------------------------------------------- load

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();

    final t = p.getInt(_kTheme) ?? 0;
    _theme = AppThemeChoice.values[t.clamp(0, AppThemeChoice.values.length - 1)];
    _accentName = p.getString(_kAccent) ?? 'Default Blue';
    _multicolor = p.getBool(_kMulticolor) ?? false;

    _tabIds = _normalizeTabs(p.getStringList(_kTabs) ?? kDefaultTabIds);
    final defIndex = p.getInt(_kDefaultTab) ?? 0;
    _defaultTabId = defIndex >= 0 && defIndex < _tabIds.length
        ? _tabIds[defIndex]
        : _tabIds.first;

    _syncHwAccent();
  }

  // ---------------------------------------------------------------- setters

  Future<void> setTheme(AppThemeChoice choice) async {
    if (choice == _theme) return;
    _theme = choice;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kTheme, choice.index);
  }

  Future<void> setAccent(AccentOption option) async {
    if (option.name == _accentName) return;
    _accentName = option.name;
    _syncHwAccent();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccent, option.name);
  }

  Future<void> setMulticolor(bool value) async {
    if (value == _multicolor) return;
    _multicolor = value;
    _syncHwAccent();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kMulticolor, value);
  }

  /// Saves the dock layout. Home is forced to the first slot, ids are validated
  /// and the list is capped at [kMaxDockTabs].
  Future<void> setTabs(List<String> ids, String defaultId) async {
    _tabIds = _normalizeTabs(ids);
    _defaultTabId = _tabIds.contains(defaultId) ? defaultId : _tabIds.first;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kTabs, _tabIds);
    await p.setInt(_kDefaultTab, _tabIds.indexOf(_defaultTabId));
  }

  // ---------------------------------------------------------------- helpers

  List<String> _normalizeTabs(List<String> ids) {
    final out = <String>[kHomeModuleId];
    for (final id in ids) {
      if (id == kHomeModuleId || out.contains(id)) continue;
      if (tabModuleById(id) == null) continue;
      out.add(id);
      if (out.length == kMaxDockTabs) break;
    }
    return out;
  }

  /// Keeps the jedHWChecker screens (which read HwAccent) in step.
  void _syncHwAccent() =>
      HwAccent.instance.setAccent(accent, multicolor: _multicolor);
}
