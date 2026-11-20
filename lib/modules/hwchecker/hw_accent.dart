import 'package:flutter/cupertino.dart';

class HwAccent extends ChangeNotifier {
  HwAccent._();
  static final HwAccent instance = HwAccent._();

  bool _multicolor = false;
  CupertinoDynamicColor _accent = CupertinoColors.systemBlue;

  static const List<CupertinoDynamicColor> _rainbow = [
    CupertinoColors.systemRed,
    CupertinoColors.systemOrange,
    CupertinoColors.systemYellow,
    CupertinoColors.systemGreen,
    CupertinoColors.systemTeal,
    CupertinoColors.systemBlue,
    CupertinoColors.systemIndigo,
    CupertinoColors.systemPurple,
    CupertinoColors.systemPink,
  ];

  bool get multicolor => _multicolor;

  void setAccent(CupertinoDynamicColor color, {bool multicolor = false}) {
    _accent = color;
    _multicolor = multicolor;
    notifyListeners();
  }

  Color resolvedAccent(BuildContext context) {
    return CupertinoDynamicColor.resolve(_accent, context);
  }

  Color iconColor(BuildContext context, int index) {
    final c = _multicolor ? _rainbow[index % _rainbow.length] : _accent;
    return CupertinoDynamicColor.resolve(c, context);
  }
}