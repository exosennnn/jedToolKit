import 'package:flutter/cupertino.dart';
import 'package:local_auth/local_auth.dart';

import 'user_profile_service.dart';

/// Enforces App Lock. Wrap the whole app with it (see main.dart: CupertinoApp.builder).
///
/// - Cold start: locked, fingerprint / screen-lock prompt shows right away.
/// - Leaving the app (home, recents, another app): the content is covered, and the
///   app locks. Coming back prompts again.
/// - If the device no longer has any screen lock, it unlocks instead of trapping you.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  static int _suppress = 0;

  /// Wrap anything that legitimately leaves the app for a moment (photo picker, etc.)
  /// so coming back from it does not trigger the lock.
  static Future<T> runUnlocked<T>(Future<T> Function() action) async {
    _suppress++;
    try {
      return await action();
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () => _suppress--);
    }
  }

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _locked = false;
  bool _covered = false;
  bool _authenticating = false;

  bool get _enabled => UserProfileService.instance.isAppLockEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = _enabled;
    if (_locked) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _locked) _unlock();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || _authenticating || AppLockGate._suppress > 0) {
      if (state == AppLifecycleState.resumed && !_locked && _covered) {
        setState(() => _covered = false);
      }
      return;
    }

    if (state == AppLifecycleState.inactive) {
      setState(() => _covered = true); // hides content in the app switcher
    } else if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      setState(() {
        _covered = true;
        _locked = true;
      });
    } else if (state == AppLifecycleState.resumed) {
      if (_locked) {
        _unlock();
      } else if (_covered) {
        setState(() => _covered = false);
      }
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    var ok = false;
    try {
      final supported = await _auth.isDeviceSupported();
      ok = supported
          ? await _auth.authenticate(
              localizedReason: 'Unlock jedToolKit',
              options: const AuthenticationOptions(
                biometricOnly: false, // fingerprint / face OR PIN / pattern / password
                stickyAuth: true,
              ),
            )
          : true; // no screen lock on the device: don't lock the user out
    } catch (_) {
      ok = false;
    }
    _authenticating = false;
    if (!mounted) return;
    if (ok) {
      setState(() {
        _locked = false;
        _covered = false;
      });
    } else {
      setState(() {}); // stay locked, the Unlock button remains
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_locked || _covered)
          Positioned.fill(
            child: _LockScreen(showButton: _locked, onUnlock: _unlock),
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  final bool showButton;
  final VoidCallback onUnlock;

  const _LockScreen({required this.showButton, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    return DefaultTextStyle(
      style: CupertinoTheme.of(context).textTheme.textStyle,
      child: Container(
        color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.lock_fill, size: 56, color: accent),
            const SizedBox(height: 20),
            const Text(
              'jedToolKit is Locked',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Authenticate to continue.',
              style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            if (showButton) ...[
              const SizedBox(height: 28),
              CupertinoButton.filled(
                onPressed: onUnlock,
                child: const Text('Unlock'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}