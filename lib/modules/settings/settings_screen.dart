import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/network/network_manager.dart';
import '../../core/profile/account_detail_page.dart'; // ADDED
import '../../core/profile/user_profile_service.dart'; // ADDED
import '../../core/settings/app_settings.dart';
import 'accent_color_screen.dart';
import 'app_theme_screen.dart';
import 'settings_widgets.dart';
import 'tab_customization_screen.dart';
import '../../core/jedui/jedui_route.dart';

/// Update these (or read them with package_info_plus) to match your build.
const String kAppVersion = '1.0.0';
const String kAppCodename = 'jedIntelligence';

/// iOS: SettingsViewController + SettingsView. Rows for features that are not
/// ported yet (App Icon, jedAI, ...) can be added the same way.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(JedPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppSettings.instance,
        NetworkManager.shared,
        UserProfileService.instance, // ADDED: refresh the profile row when name/photo change
      ]),
      builder: (context, _) {
        final s = AppSettings.instance;
        final tint = CupertinoDynamicColor.resolve(s.accent, context);

        return SettingsPage(
          title: 'Settings',
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ADDED: Account section (no header, like iOS)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SettingsCard(
                      child: _ProfileRow(
                        tint: tint,
                        onTap: () => _push(context, const AccountDetailPage()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _section(
                    header: 'App Preferences',
                    rows: [
                      SettingsNavRow(
                        icon: CupertinoIcons.circle_lefthalf_fill,
                        color: tint,
                        title: 'App Theme',
                        detail: s.themeChoice.label,
                        onTap: () => _push(context, const AppThemeScreen()),
                      ),
                      SettingsNavRow(
                        icon: CupertinoIcons.color_filter,
                        color: tint,
                        title: 'Accent Color',
                        detail: s.accentName,
                        onTap: () => _push(context, const AccentColorScreen()),
                      ),
                      SettingsNavRow(
                        icon: CupertinoIcons.square_grid_2x2,
                        color: tint,
                        title: 'Customize Tab Bar',
                        onTap: () => _push(context, const TabCustomizationScreen()),
                      ),
                      SettingsNavRow(
                        icon: CupertinoIcons.airplane,
                        color: tint,
                        title: 'Offline Mode',
                        detail: NetworkManager.shared.isOfflineModeEnabled
                            ? 'On. Internet access is blocked for this app.'
                            : 'Off. The app can use the internet.',
                        chevron: false,
                        trailing: CupertinoSwitch(
                          value: NetworkManager.shared.isOfflineModeEnabled,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            NetworkManager.shared.setOfflineMode(v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _section(
                    header: 'App Information',
                    rows: [
                      SettingsNavRow(
                        icon: CupertinoIcons.info_circle,
                        color: tint,
                        title: 'Version',
                        detail: kAppVersion,
                      ),
                      SettingsNavRow(
                        icon: CupertinoIcons.command,
                        color: tint,
                        title: 'Codename',
                        detail: kAppCodename,
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section({required String header, required List<Widget> rows}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(header),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SettingsCard(
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i != rows.length - 1) const SettingsDivider(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// iOS: the `.profile` case of SettingsRowView.
/// Shows the saved photo (circle) or a tinted person icon, the name, and "jedAccount".
class _ProfileRow extends StatelessWidget {
  final Color tint;
  final VoidCallback onTap;

  const _ProfileRow({required this.tint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final svc = UserProfileService.instance;
    final hasName = (svc.username ?? '').trim().isNotEmpty;
    final photo = svc.profileImage;

    return SettingsPressRow(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (photo != null)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: CupertinoColors.label.resolveFrom(context).withAlpha(20),
                  ),
                ),
                child: ClipOval(
                  child: Image.memory(
                    photo,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(CupertinoIcons.person_crop_circle_fill, size: 24, color: tint),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasName ? svc.username! : 'Profile',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasName ? 'jedAccount' : 'Set up your profile',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }
}