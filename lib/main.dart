import 'package:flutter/cupertino.dart';
import 'app/jed_shell.dart';
import 'core/jedui/jedui_theme.dart';
import 'core/network/network_manager.dart';
import 'core/profile/app_lock_gate.dart'; // ADDED
import 'core/profile/user_profile_service.dart'; // ADDED
import 'core/settings/app_settings.dart';
import 'modules/appsetup/app_setup_screen.dart'; // ADDED
import 'modules/welcome/welcome_screen.dart'; // ADDED
import 'modules/whatsnew/whats_new.dart'; // ADDED: What's New popup

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  await NetworkManager.shared.load();
  await UserProfileService.instance.init(); // ADDED: loads name, photo, app lock flag
  runApp(const JedToolKitApp());
}

class JedToolKitApp extends StatelessWidget {
  const JedToolKitApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app when the theme or accent color changes.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final s = AppSettings.instance;
        return CupertinoApp(
          title: 'jedToolKit',
          debugShowCheckedModeBanner: false,
          theme: JedTheme.build(brightness: s.brightness, primary: s.accent),
          builder: (context, child) => AppLockGate(child: child!), // ADDED: App Lock
          // CHANGED: splash -> first-run setup (new users only) -> What's New (once per version) -> app
          home: const WelcomeGate(
            child: AppSetupGate(
              child: WhatsNewGate(child: JedShell()),
            ),
          ),
        );
      },
    );
  }
}