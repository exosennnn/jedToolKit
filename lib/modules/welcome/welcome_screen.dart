import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/profile/user_profile_service.dart';

/// Port of WelcomeViewController: shows the splash, then fades it out over [child]
/// (the app). Use it as `home:` in CupertinoApp:
///
///   home: const WelcomeGate(child: JedShell()),
class WelcomeGate extends StatefulWidget {
  final Widget child;
  const WelcomeGate({super.key, required this.child});

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  bool _showChild = false;
  bool _fading = false;
  bool _done = false;

  void _finish() {
    if (_fading) return;
    // Mount the app under the splash and fade the splash out (0.5s, like iOS).
    setState(() {
      _showChild = true;
      _fading = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_showChild) KeyedSubtree(key: const ValueKey('app'), child: widget.child),
        if (!_done)
          IgnorePointer(
            key: const ValueKey('welcome'),
            ignoring: _fading,
            child: AnimatedOpacity(
              opacity: _fading ? 0 : 1,
              duration: const Duration(milliseconds: 500),
              onEnd: () {
                if (_fading && mounted) setState(() => _done = true);
              },
              child: WelcomeScreen(onFinished: _finish),
            ),
          ),
      ],
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const WelcomeScreen({super.key, required this.onFinished});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  // iOS: totalDuration 2.8s, a new step every 0.7s.
  static const _totalSeconds = 2.8;
  static const _stepSeconds = 0.7;

  late final AnimationController _drift; // orbs, 9s ease-in-out, reversing
  late final AnimationController _entrance; // icon / title / rows appearing
  late final AnimationController _progress; // 0 -> 1 over 2.8s, linear

  // Edit this list to change the checklist.
static const List<String> _messages = [
  'Loading jedModules...',
  'Initializing jedRamChecker...',
  'Calibrating toolkits...',
  'Launching jedHWChecker...',
  'Finalizing...',
];

  late final String? _username;
  late final bool _isUser;
  int _lastStep = 0;
  bool _finishedCalled = false;

  @override
  void initState() {
    super.initState();
    final svc = UserProfileService.instance;
    final name = svc.username; // local copy: field promotion needs Dart 3.2+
    _username = name;
    _isUser = name != null && name.isNotEmpty && name != 'User';

    _drift = AnimationController(vsync: this, duration: const Duration(seconds: 9))
      ..repeat(reverse: true);
    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _progress = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_totalSeconds * 1000).round()),
    );

    _progress.addListener(_onProgress);
    _progress.addStatusListener((s) {
      if (s == AnimationStatus.completed) _onCompleted();
    });

    HapticFeedback.lightImpact();
    _entrance.forward();
    _progress.forward();
  }

  @override
  void dispose() {
    _drift.dispose();
    _entrance.dispose();
    _progress.dispose();
    super.dispose();
  }

  int get _stepIndex {
    final elapsed = _progress.value * _totalSeconds;
    return (elapsed / _stepSeconds).floor().clamp(0, _messages.length - 1);
  }

  void _onProgress() {
    final i = _stepIndex;
    if (i != _lastStep) {
      _lastStep = i;
      HapticFeedback.lightImpact();
    }
  }

  void _onCompleted() {
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_finishedCalled) {
        _finishedCalled = true;
        widget.onFinished();
      }
    });
  }

  double _iv(double a, double b, Curve c) =>
      Interval(a, b, curve: c).transform(_entrance.value);

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final accent = CupertinoTheme.of(context).primaryColor;

    return DefaultTextStyle(
      style: CupertinoTheme.of(context).textTheme.textStyle,
      child: AnimatedBuilder(
        animation: Listenable.merge([_drift, _entrance, _progress]),
        builder: (context, _) {
          final iconT = _iv(0, 0.5, Curves.easeOut); // 0.5s
          final appear = _iv(0.15, 0.75, Curves.easeOut); // delayed 0.15s
          final titleT = _iv(0.1, 1.0, Curves.easeOut); // delayed 0.1s, 0.9s long

          return Container(
            color: bg,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _background(context, bg, accent),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      children: [
                        const Spacer(),
                        _brandIcon(context, accent, iconT),
                        const SizedBox(height: 34),
                        _titleBlock(context, appear, titleT),
                        const SizedBox(height: 24),
                        _progressBar(context, accent),
                        const SizedBox(height: 28),
                        _stepList(context, accent, appear),
                        const Spacer(),
                        Opacity(
                          opacity: appear,
                          child: Text(
                            '© 2026 jedPlatforms.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context)
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- background

  Widget _background(BuildContext context, Color bg, Color accent) {
    final t = Curves.easeInOut.transform(_drift.value);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;

        // (from, to) offsets as fractions of width/height, measured from the center.
        Widget orb(Color color, double sizeFactor, Offset from, Offset to) {
          final dx = (from.dx + (to.dx - from.dx) * t) * w;
          final dy = (from.dy + (to.dy - from.dy) * t) * h;
          final size = w * sizeFactor * 1.4; // gradient edge fades out, so draw it larger
          return Center(
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)],
                    stops: const [0.25, 1.0],
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            orb(accent, 0.9, const Offset(-0.22, 0.10), const Offset(0.25, -0.16)),
            orb(CupertinoColors.systemPurple.resolveFrom(context), 0.7,
                const Offset(0.22, -0.05), const Offset(-0.30, 0.28)),
            orb(CupertinoColors.systemCyan.resolveFrom(context), 0.6,
                const Offset(-0.16, 0.52), const Offset(0.12, 0.38)),
            // Soft vignette, like the iOS RadialGradient overlay.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.95)],
                    stops: const [0.33, 1.0],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --------------------------------------------------------------------- icon

  Widget _brandIcon(BuildContext context, Color accent, double t) {
    final photo = UserProfileService.instance.profileImage;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    Widget content;
    if (_isUser) {
      content = photo != null
          ? ClipOval(
              child: Image.memory(photo, width: 84, height: 84, fit: BoxFit.cover, gaplessPlayback: true),
            )
          : Icon(
              CupertinoIcons.person_crop_circle_fill,
              size: 84,
              color: secondary.withValues(alpha: 0.6),
            );
    } else {
      content = Icon(CupertinoIcons.hammer_fill, size: 38, color: accent);
    }

    return Opacity(
      opacity: t,
      child: Transform.scale(
        scale: 0.8 + 0.2 * t,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Container(
            width: 100,
            height: 100,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CupertinoColors.systemBackground.resolveFrom(context).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: CupertinoColors.label.resolveFrom(context).withValues(alpha: 0.06),
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- title

  Widget _titleBlock(BuildContext context, double appear, double titleT) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final blur = 14 * (1 - titleT);

    Widget title = Text(
      'jedToolKit',
      style: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6, // stands in for iOS's .expanded font width
        color: CupertinoColors.label.resolveFrom(context),
      ),
    );
    if (blur > 0.05) {
      title = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
        child: title,
      );
    }

    return Column(
      children: [
        Opacity(
          opacity: appear,
          child: Text(
            _isUser ? 'Welcome back, $_username to' : 'Welcome to',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: secondary),
          ),
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: titleT,
          child: Transform.scale(scale: 1.18 - 0.18 * titleT, child: title),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- progress bar

  Widget _progressBar(BuildContext context, Color accent) {
    final track = CupertinoColors.label.resolveFrom(context).withValues(alpha: 0.06);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: LayoutBuilder(
        builder: (context, c) {
          final fill = (c.maxWidth * _progress.value).clamp(5.0, c.maxWidth);
          return SizedBox(
            height: 5,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(5)),
                ),
                Container(
                  width: fill,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    gradient: LinearGradient(colors: [accent.withValues(alpha: 0.7), accent]),
                    boxShadow: [
                      BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------- step list

  Widget _stepList(BuildContext context, Color accent, double appear) {
    final current = _stepIndex;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _messages.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _stepRow(context, accent, i, current),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepRow(BuildContext context, Color accent, int index, int current) {
    final isDone = index < current;
    final isCurrent = index == current;

    // Each row slides in 0.06s after the previous one.
    final start = 0.15 + index * 0.06;
    final rowT = Interval(start, (start + 0.5).clamp(0.0, 1.0), curve: Curves.easeOut)
        .transform(_entrance.value);

    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final textColor = isCurrent
        ? label
        : (isDone ? secondary : secondary.withValues(alpha: 0.4));

    return Opacity(
      opacity: rowT,
      child: Transform.translate(
        offset: Offset(-12 * (1 - rowT), 0),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? accent : label.withValues(alpha: 0.08),
              ),
              child: isDone
                  ? const Icon(CupertinoIcons.checkmark_alt, size: 12, color: CupertinoColors.white)
                  : (isCurrent
                      ? Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                        )
                      : null),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _messages[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}