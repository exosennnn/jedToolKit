import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';

import 'app_lock_gate.dart';
import 'user_profile_service.dart';

/// Cupertino port of AccountDetailView.swift + AccountDetailViewController.swift.
/// Push it from Settings:
///   Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const AccountDetailPage()));
class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({super.key});

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  final _service = UserProfileService.instance;
  final _auth = LocalAuthentication();
  final _picker = ImagePicker();
  late final TextEditingController _nameController;

  late String _originalUsername;
  Uint8List? _image;
  bool _photoDidChange = false;
  bool _appLock = false;
  bool _authInFlight = false;

  @override
  void initState() {
    super.initState();
    _originalUsername = _service.username ?? '';
    _image = _service.profileImage;
    _appLock = _service.isAppLockEnabled;
    _nameController = TextEditingController(text: _originalUsername)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ state
  String get _trimmed => _nameController.text.trim();
  bool get _hasUnsavedChanges => _trimmed != _originalUsername || _photoDidChange;
  bool get _canSave => _trimmed.isNotEmpty && _hasUnsavedChanges;

  // ---------------------------------------------------------------- actions
  Future<void> _save() async {
    if (_trimmed.isEmpty) return;

    await _service.saveUsername(_trimmed);
    if (_photoDidChange) {
      if (_image != null) {
        await _service.saveProfileImage(_image!);
      } else {
        await _service.removeProfileImage();
      }
    }

    HapticFeedback.lightImpact();
    if (mounted) Navigator.of(context).pop(); // direct pop bypasses PopScope
  }

  Future<void> _confirmDiscard() async {
    final discard = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text('You have unsaved changes to your profile.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _pickPhoto() async {
    try {
      // The picker leaves the app briefly; don't lock when we come back from it.
      final picked = await AppLockGate.runUnlocked(
        () => _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 90,
        ),
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _image = bytes;
        _photoDidChange = true;
      });
    } catch (_) {
      _notice('Photo Library', 'Could not open your photo library.');
    }
  }

  Future<void> _confirmRemovePhoto() async {
    if (_image == null) return;
    final remove = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Remove Photo?'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove Photo'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (remove == true && mounted) {
      setState(() {
        _image = null;
        _photoDidChange = true;
      });
    }
  }

  // ------------------------------------------------------------- App Lock
  Future<bool> _authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // biometrics OR device PIN/pattern/password
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _onAppLockToggled(bool wantOn) async {
    if (_authInFlight) return;
    _authInFlight = true;
    try {
      final supported = await _auth.isDeviceSupported();

      if (wantOn) {
        if (!supported) {
          _notice('App Lock', 'Set up a screen lock in Android Settings to use App Lock.');
          return;
        }
        final ok = await _authenticate('Authenticate to enable App Lock.');
        if (ok) await _setAppLock(true);
      } else {
        // Same rule as iOS: turning the lock off needs the same auth as turning it on,
        // unless the device has no lock at all.
        final ok = supported ? await _authenticate('Authenticate to disable App Lock.') : true;
        if (ok) await _setAppLock(false);
      }
    } finally {
      _authInFlight = false;
    }
  }

  Future<void> _setAppLock(bool value) async {
    await _service.saveAppLock(value);
    if (mounted) setState(() => _appLock = value);
  }

  void _notice(String title, String message) {
    if (!mounted) return;
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final accent = CupertinoTheme.of(context).primaryColor; // comes from JedTheme (s.accent)

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: CupertinoPageScaffold(
        backgroundColor: bg,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: bg,
          automaticallyImplyLeading: false,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 32,
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Icon(CupertinoIcons.chevron_back),
          ),
          middle: const Text(
            'jedAccount',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 32,
            onPressed: _canSave ? _save : null,
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            children: [
              _card(_profileCard(accent)),
              const SizedBox(height: 32),
              _card(_configRows()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    final border = CupertinoColors.label.resolveFrom(context).withOpacity(0.04);
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _profileCard(Color accent) {
    final placeholder = CupertinoColors.tertiaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: _image != null
                  ? Image.memory(_image!, width: 100, height: 100, fit: BoxFit.cover, gaplessPlayback: true)
                  : Icon(CupertinoIcons.person_crop_circle_fill, size: 100, color: placeholder),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minSize: 32,
                onPressed: _pickPhoto,
                child: Text(
                  _image == null ? 'Set Photo' : 'Change Photo',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: accent),
                ),
              ),
              if (_image != null)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minSize: 32,
                  onPressed: _confirmRemovePhoto,
                  child: const Text(
                    'Remove Photo',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.systemRed,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _configRows() {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final limit = UserProfileService.usernameCharacterLimit;

    return Column(
      children: [
        // Name row
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Text('Name', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: CupertinoTextField(
                      controller: _nameController,
                      placeholder: 'Your Name',
                      textAlign: TextAlign.end,
                      inputFormatters: [LengthLimitingTextInputFormatter(limit)],
                      textCapitalization: TextCapitalization.words,
                      padding: EdgeInsets.zero,
                      decoration: null, // borderless, like the SwiftUI TextField
                      style: TextStyle(fontSize: 16, color: secondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_nameController.text.characters.length}/$limit',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: secondary.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 0.5,
          margin: const EdgeInsets.only(left: 20),
          color: CupertinoColors.separator.resolveFrom(context),
        ),

        // App Lock row
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('App Lock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      'Require fingerprint, face unlock or screen lock',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
                    ),
                  ],
                ),
              ),
              CupertinoSwitch(value: _appLock, onChanged: _onAppLockToggled),
            ],
          ),
        ),
      ],
    );
  }
}