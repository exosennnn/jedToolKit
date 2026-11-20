import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import 'settings_widgets.dart';

/// iOS: AccentColorViewController + AccentColorView.
class AccentColorScreen extends StatelessWidget {
  const AccentColorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final s = AppSettings.instance;

        return SettingsPage(
          title: 'Accent Color',
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.only(left: 0, bottom: 12),
                    child: Text(
                      'THEME COLORS',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ),
                  SettingsCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      child: GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 16,
                        children: [
                          for (final option in AppSettings.accents)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                AppSettings.instance.setAccent(option);
                              },
                              child: _Swatch(
                                option: option,
                                selected: option.name == s.accentName,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SettingsFootnote(
                    'Select an accent color to personalize the interface across the entire app.',
                  ),
                  const SizedBox(height: 24),
                  SettingsCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Multicolor',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.label.resolveFrom(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Give each module icon its own color.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: CupertinoColors.secondaryLabel
                                        .resolveFrom(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CupertinoSwitch(
                            value: s.multicolor,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              AppSettings.instance.setMulticolor(v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
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
    final mono = option.name == 'Monochrome';
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final check = mono ? (dark ? CupertinoColors.black : CupertinoColors.white) : CupertinoColors.white;
    final border = CupertinoColors.label
        .resolveFrom(context)
        .withAlpha(mono ? 38 : 13);

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
              ),
            ),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: border),
            ),
          ),
          if (selected) Icon(CupertinoIcons.checkmark_alt, size: 20, color: check),
        ],
      ),
    );
  }
}
