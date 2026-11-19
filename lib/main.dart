import 'package:flutter/cupertino.dart';
import 'app/jed_shell.dart';
import 'core/jedui/jedui_theme.dart';

void main() => runApp(const JedToolKitApp());

class JedToolKitApp extends StatelessWidget {
  const JedToolKitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'jedToolKit',
      debugShowCheckedModeBanner: false,
      theme: JedTheme.light,
      home: const JedShell(),
    );
  }
}