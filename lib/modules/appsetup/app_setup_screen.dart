import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/profile/app_lock_gate.dart';
import '../../core/profile/user_profile_service.dart';
import '../../core/settings/app_settings.dart';

/// Shows the setup flow only for first-time users (same rule as
/// UserProfileManager.isReturningUser), then reveals [child].
///
///   home: const WelcomeGate(child: AppSetupGate(child: JedShell())),
class AppSetupGate extends StatefulWidget {
  final Widget child;
  const AppSetupGate({super.key, required this.child});

  @override
  State<AppSetupGate> createState() => _AppSetupGateState();
}

class _AppSetupGateState extends State<AppSetupGate> {
  // Decided once at launch, so saving the name mid-flow doesn't skip the other steps.
  bool _needsSetup = !UserProfileService.instance.isReturningUser;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: _needsSetup
          ? AppSetupScreen(
              key: const ValueKey('setup'),
              onFinished: () => setState(() => _needsSetup = false),
            )
          : KeyedSubtree(key: const ValueKey('app'), child: widget.child),
    );
  }
}

enum SetupMode { onboarding, accentColor, featureIntro }

class AppSetupScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const AppSetupScreen({super.key, required this.onFinished});

  @override
  State<AppSetupScreen> createState() => _AppSetupScreenState();
}

class _AppSetupScreenState extends State<AppSetupScreen> {
  final _service = UserProfileService.instance;
  final _picker = ImagePicker();
  late final TextEditingController _name;

  SetupMode _mode = SetupMode.onboarding;
  Uint8List? _photo;
  bool _flashError = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _service.username ?? '');
    _photo = _service.profileImage;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ actions
  Future<void> _pickPhoto() async {
    try {
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
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      // Photo library unavailable: the user can still continue without a photo.
    }
  }

  void _flashNameField() {
    setState(() => _flashError = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _flashError = false);
    });
  }

  Future<void> _next() async {
    switch (_mode) {
      case SetupMode.onboarding:
        final name = _name.text.trim();
        if (name.isEmpty) {
          HapticFeedback.mediumImpact();
          _flashNameField();
          return;
        }
        FocusScope.of(context).unfocus();
        await _service.saveUsername(name);
        final photo = _photo;
        if (photo != null) await _service.saveProfileImage(photo);
        if (mounted) setState(() => _mode = SetupMode.accentColor);
        break;
      case SetupMode.accentColor:
        setState(() => _mode = SetupMode.featureIntro);
        break;
      case SetupMode.featureIntro:
        await _service.setOnboardingCompleted(true);
        widget.onFinished();
        break;
    }
  }

  // ---------------------------------------------------------------------- UI
  ({String context, String title, String subtitle, String button}) get _copy {
    switch (_mode) {
      case SetupMode.onboarding:
        return (
          context: 'Profile Initialization',
          title: 'Welcome!',
          subtitle:
              'Set up your workspace nickname and profile photo to personalize your jedToolKit identity.',
          button: 'Continue',
        );
      case SetupMode.accentColor:
        return (
          context: 'Theme Personalization',
          title: 'Accent Color',
          subtitle:
              'Choose your custom interface accent styling. This will be implemented across all dashboard sections.',
          button: 'Save and Apply',
        );
      case SetupMode.featureIntro:
        return (
          context: 'Exploration Module',
          title: 'Key Features',
          subtitle:
              'Discover the main tools designed to analyze, benchmark, and test your device.',
          button: 'Get Started',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final copy = _copy;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previous, if (current != null) current],
                    ),
                    child: Column(
                      key: ValueKey(_mode),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.context.toUpperCase(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          copy.title,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          copy.subtitle,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: secondary),
                        ),
                        const SizedBox(height: 24),
                        _content(context, accent),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: accent,
                    borderRadius: BorderRadius.circular(16),
                    minSize: 54,
                    onPressed: _next,
                    child: Text(
                      copy.button,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppSettings.instance.contrastingForeground(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _content(BuildContext context, Color accent) {
    switch (_mode) {
      case SetupMode.onboarding:
        return _card(context, _onboarding(context, accent));
      case SetupMode.accentColor:
        return _card(context, _accentPicker(context));
      case SetupMode.featureIntro:
        return _card(context, _featureList(context));
    }
  }

  // --------------------------------------------------------------- onboarding
  Widget _onboarding(BuildContext context, Color accent) {
    final photo = _photo;
    final fieldBg = _flashError
        ? CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.15)
        : CupertinoColors.systemGroupedBackground.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      child: Column(
        children: [
          ClipOval(
            child: SizedBox(
              width: 120,
              height: 120,
              child: photo != null
                  ? Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true)
                  : Icon(
                      CupertinoIcons.person_crop_circle_fill,
                      size: 120,
                      color: CupertinoColors.systemGrey4.resolveFrom(context),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          CupertinoButton(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(100),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            minSize: 0,
            onPressed: _pickPhoto,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.camera_fill, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  photo == null ? 'Set Photo' : 'Change Photo',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(14)),
            child: CupertinoTextField(
              controller: _name,
              placeholder: 'Enter your name',
              decoration: null,
              padding: EdgeInsets.zero,
              autocorrect: false,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                LengthLimitingTextInputFormatter(UserProfileService.usernameCharacterLimit),
              ],
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label.resolveFrom(context),
              ),
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ accent colors
  Widget _accentPicker(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final s = AppSettings.instance;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 16),
                child: Text(
                  'AVAILABLE SWATCHES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 18,
                crossAxisSpacing: 8,
                children: [
                  for (final option in AppSettings.accents)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        AppSettings.instance.setAccent(option);
                      },
                      child: _Swatch(option: option, selected: option.name == s.accentName),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ feature intro
  // Only the modules that exist in the Android app (jedAI and jedXIP aren't ported).
  static const List<(IconData, String, String)> _features = [
    (CupertinoIcons.info_circle, 'jedPhoneInfo',
        "Get a complete picture of your device's specs and real-time stats."),
    (CupertinoIcons.wrench_fill, 'jedHWChecker',
        'Test everything from your screen and camera to sensors and biometrics.'),
    (CupertinoIcons.speedometer, 'jedBenchmark 2',
        "Measure your device's raw power with CPU, Memory, and GPU tests."),
    (CupertinoIcons.folder_fill, 'jedDiskChecker',
        "Accurately measure your device's storage read and write speeds."),
    (CupertinoIcons.memories, 'jedRAMChecker',
        'Monitor RAM footprint, pressure levels, and system capabilities at a glance.'),
  ];

  Widget _featureList(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      child: Column(
        children: [
          for (var i = 0; i < _features.length; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            Builder(builder: (context) {
              final f = _features[i];
              final tint = CupertinoDynamicColor.resolve(AppSettings.instance.tintFor(i), context);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(f.$1, size: 18, color: tint),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.$2, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          f.$3,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final AccentOption option;
  final bool selected;

  const _Swatch({required this.option, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = CupertinoDynamicColor.resolve(option.color, context);
    final check = option.name == 'Monochrome'
        ? CupertinoColors.systemBackground.resolveFrom(context)
        : CupertinoColors.white;

    return Center(
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (selected)
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 3),
                ),
              ),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: CupertinoColors.black.withValues(alpha: 0.05)),
              ),
            ),
            if (selected) Icon(CupertinoIcons.checkmark_alt, size: 22, color: check),
          ],
        ),
      ),
    );
  }
}