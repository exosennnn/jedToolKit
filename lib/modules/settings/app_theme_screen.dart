import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import 'settings_widgets.dart';

/// iOS: AppThemeViewController. System / Light / Dark.
class AppThemeScreen extends StatelessWidget {
  const AppThemeScreen({super.key});

  static const _options = <(AppThemeChoice, IconData, String)>[
    (AppThemeChoice.system, CupertinoIcons.circle_lefthalf_fill,
        'Matches your device appearance setting.'),
    (AppThemeChoice.light, CupertinoIcons.sun_max_fill, 'Always use the light theme.'),
    (AppThemeChoice.dark, CupertinoIcons.moon_fill, 'Always use the dark theme.'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final s = AppSettings.instance;
        final tint = CupertinoDynamicColor.resolve(s.accent, context);

        return SettingsPage(
          title: 'App Theme',
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  SettingsCard(
                    child: Column(
                      children: [
                        for (var i = 0; i < _options.length; i++) ...[
                          _row(context, _options[i], s.themeChoice, tint),
                          if (i != _options.length - 1) const SettingsDivider(),
                        ],
                      ],
                    ),
                  ),
                  const SettingsFootnote(
                    'Choose how jedToolKit looks. The change applies immediately.',
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    (AppThemeChoice, IconData, String) o,
    AppThemeChoice current,
    Color tint,
  ) {
    final selected = o.$1 == current;
    return SettingsPressRow(
      onTap: () {
        if (selected) return;
        HapticFeedback.selectionClick();
        AppSettings.instance.setTheme(o.$1);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tint.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(o.$2, size: 22, color: tint),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.$1.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    o.$3,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(CupertinoIcons.checkmark_alt, size: 20, color: tint),
          ],
        ),
      ),
    );
  }
}
