import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android/Flutter port of UserProfileManager.swift.
///
/// Call `await UserProfileService.instance.init();` in main() before runApp().
/// Listen to it (ListenableBuilder / addListener) wherever the old iOS code
/// observed `profileChangedNotification`.
class UserProfileService extends ChangeNotifier {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  static const _kUsername = 'userProfileUsername';
  static const _kAppLock = 'isAppLockEnabled';
  static const _kOnboarding = 'hasCompletedOnboarding';
  static const _imageFileName = 'jed_profile_image.bin';

  /// Same clamp the iOS controller applied.
  static const int usernameCharacterLimit = 30;

  late SharedPreferences _prefs;
  String? _username;
  Uint8List? _imageBytes;
  bool _appLock = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _username = _prefs.getString(_kUsername);
    _appLock = _prefs.getBool(_kAppLock) ?? false;

    final file = await _imageFile();
    if (await file.exists()) {
      try {
        _imageBytes = await file.readAsBytes();
      } catch (_) {
        _imageBytes = null;
      }
    }
  }

  Future<File> _imageFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_imageFileName');
  }

  // ---------------------------------------------------------------- Username
  String? get username => _username;

  Future<void> saveUsername(String name) async {
    _username = name;
    await _prefs.setString(_kUsername, name);
    notifyListeners();
  }

  // ------------------------------------------------------------ Profile image
  Uint8List? get profileImage => _imageBytes;

  Future<void> saveProfileImage(Uint8List bytes) async {
    final file = await _imageFile();
    await file.writeAsBytes(bytes, flush: true);
    _imageBytes = bytes;
    notifyListeners();
  }

  /// Falls back to the default person icon everywhere.
  Future<void> removeProfileImage() async {
    final file = await _imageFile();
    if (await file.exists()) await file.delete();
    _imageBytes = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- App Lock
  bool get isAppLockEnabled => _appLock;

  Future<void> saveAppLock(bool enabled) async {
    _appLock = enabled;
    await _prefs.setBool(_kAppLock, enabled);
  }

  // -------------------------------------------------------------- Onboarding
  bool get hasCompletedOnboarding => _prefs.getBool(_kOnboarding) ?? false;

  Future<void> setOnboardingCompleted(bool status) =>
      _prefs.setBool(_kOnboarding, status);

  bool get isReturningUser =>
      hasCompletedOnboarding || _prefs.getString(_kUsername) != null;
}