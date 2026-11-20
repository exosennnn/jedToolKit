import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/app_settings.dart';
import '../settings/settings_screen.dart' show kAppVersion;


class WhatsNewFeature {
  final IconData icon;
  final String title;
  final String subtitle;
  const WhatsNewFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

// ============================================================================
// Service (iOS: WhatsNewViewModel.shouldShow / markAsSeen / loadFeatures)
// ============================================================================

class WhatsNewService {
  WhatsNewService._();

  /// Same key as iOS.
  static const _kLastSeen = 'lastSeenVersion';

  /// iOS reads CFBundleShortVersionString. Here it is kAppVersion from
  /// settings_screen.dart (swap for package_info_plus if you add it).
  static String get currentVersion => kAppVersion;

  static String get title => "What's New in $currentVersion";

  static Future<bool> shouldShow() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastSeen) != currentVersion;
  }

  static Future<void> markAsSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastSeen, currentVersion);
  }

  /// iOS: loadFeatures(). Edit this list for every release.
  /// NOTE: the first four are copied from iOS. The jedAI widgets don't exist
  /// on Android, so replace them with what actually changed in the Android build.
  static const List<WhatsNewFeature> features = [
    WhatsNewFeature(
      icon: CupertinoIcons.sparkles,
      title: 'jedAI Recents Widget',
      subtitle:
          'A new home screen widget showing your most recent jedAI conversations — mode icon, title, last message, and how long ago you left off. Tap to jump straight back into jedAI.',
    ),
    WhatsNewFeature(
      icon: CupertinoIcons.textformat,
      title: 'Refreshed Widget Design',
      subtitle:
          'The jedAI widget now uses an expanded-width title to match the rest of the app\'s large-title style, with tinted icon badges, card-style rows, and relative timestamps like "2h ago."',
    ),
    WhatsNewFeature(
      icon: CupertinoIcons.arrow_2_circlepath,
      title: 'Live Widget Sync',
      subtitle:
          'Every new chat, reply, or deleted conversation now syncs to the jedAI widget automatically, so what you see on your home screen always matches what\'s in Recents.',
    ),
    WhatsNewFeature(
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      title: 'Clearer Widget Troubleshooting',
      subtitle:
          'Both widgets now tell the difference between "just needs a sync" and "needs jedToolKit reinstalled" instead of one generic error, so sideloaded installs are easier to fix.',
    ),
  ];
}


class WhatsNewGate extends StatefulWidget {
  final Widget child;
  const WhatsNewGate({super.key, required this.child});

  @override
  State<WhatsNewGate> createState() => _WhatsNewGateState();
}

class _WhatsNewGateState extends State<WhatsNewGate> {
  @override
  void initState() {
    super.initState();
    _maybeShow();
  }

  Future<void> _maybeShow() async {
    if (!await WhatsNewService.shouldShow()) return;
    if (!mounted) return;
    // Wait for the first frame so the Navigator is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true, // slides up from the bottom, like a modal
          builder: (_) => PopScope(
            canPop: false, // only "Continue" dismisses, and it marks the version as seen
            child: WhatsNewScreen(onContinue: () => Navigator.of(context).pop()),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}


class WhatsNewScreen extends StatelessWidget {
  final VoidCallback onContinue;
  final List<WhatsNewFeature> features;

  const WhatsNewScreen({
    super.key,
    required this.onContinue,
    this.features = WhatsNewService.features,
  });

  @override
  Widget build(BuildContext context) {
    // iOS observes "AccentColorChanged"; here we listen to AppSettings.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final s = AppSettings.instance;
        final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
        final label = CupertinoColors.label.resolveFrom(context);
        final accent = CupertinoDynamicColor.resolve(s.accent, context);

        return CupertinoPageScaffold(
          backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
          child: DefaultTextStyle(
            style: CupertinoTheme.of(context).textTheme.textStyle,
            child: SafeArea(
              child: Column(
                children: [
                  // ---- Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                    child: Column(
                      children: [
                        Text(
                          'WELCOME',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                            color: secondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          WhatsNewService.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: label,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ---- Feature card
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CupertinoColors.secondarySystemGroupedBackground
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: label.withValues(alpha: 0.04)),
                          boxShadow: [
                            BoxShadow(
                              color: CupertinoColors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Column(
                            children: [
                              for (var i = 0; i < features.length; i++) ...[
                                _FeatureRow(
                                  feature: features[i],
                                  color: CupertinoDynamicColor.resolve(s.tintFor(i), context),
                                ),
                                if (i != features.length - 1)
                                  Container(
                                    height: 1,
                                    margin: const EdgeInsets.only(left: 80),
                                    color: label.withValues(alpha: 0.05),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ---- Continue button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        await WhatsNewService.markAsSeen();
                        onContinue();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: s.contrastingForeground(context),
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
      },
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final WhatsNewFeature feature;
  final Color color;
  const _FeatureRow({required this.feature, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(feature.icon, size: 22, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  feature.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}