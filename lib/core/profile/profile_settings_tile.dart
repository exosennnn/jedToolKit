import 'package:flutter/cupertino.dart';

import '../jedui/jedui_components.dart';
import '../jedui/jedui_route.dart';
import 'account_detail_page.dart';
import 'user_profile_service.dart';

/// Profile card for the top of Settings (port of the `.profile` row in SettingsRowView).
/// Place it exactly where your other Settings cards go, e.g. as the first child of the
/// Settings ListView/Column:
///
///   const ProfileSettingsTile(),
///
/// Updates by itself when the name or photo changes.
class ProfileSettingsTile extends StatelessWidget {
  const ProfileSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;

    return ListenableBuilder(
      listenable: UserProfileService.instance,
      builder: (context, _) {
        final svc = UserProfileService.instance;
        final hasName = (svc.username ?? '').trim().isNotEmpty;

        return JedGroupCard(
          children: [
            JedPressable(
              onTap: () => Navigator.of(context).push(
                JedPageRoute(builder: (_) => const AccountDetailPage()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    if (svc.profileImage != null)
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: CupertinoColors.label
                                .resolveFrom(context)
                                .withOpacity(0.08),
                          ),
                        ),
                        child: ClipOval(
                          child: Image.memory(
                            svc.profileImage!,
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
                          color: accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          CupertinoIcons.person_crop_circle_fill,
                          color: accent,
                          size: 26,
                        ),
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
                      CupertinoIcons.chevron_right,
                      size: 14,
                      color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}