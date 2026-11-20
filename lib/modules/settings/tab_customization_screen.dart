import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/tab_modules.dart';
import 'settings_widgets.dart';

/// iOS: TabCustomizationViewController.
/// Edit mode lets you remove / reorder / add tabs. Tapping a selected tab makes
/// it the default (checkmark). jedHome is pinned to the first slot.
/// Every change is saved immediately to [AppSettings].
class TabCustomizationScreen extends StatefulWidget {
  const TabCustomizationScreen({super.key});

  @override
  State<TabCustomizationScreen> createState() => _TabCustomizationScreenState();
}

class _TabCustomizationScreenState extends State<TabCustomizationScreen> {
  late List<String> _selected;
  late String _default;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _selected = List.of(AppSettings.instance.tabIds);
    _default = AppSettings.instance.defaultTabId;
  }

  List<JedTabModule> get _available => [
        for (final m in kTabModules)
          if (m.id != kHomeModuleId && !_selected.contains(m.id)) m,
      ]..sort((a, b) => a.title.compareTo(b.title));

  void _save() => AppSettings.instance.setTabs(_selected, _default);

  void _remove(String id) {
    if (id == kHomeModuleId) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selected.remove(id);
      if (_default == id) _default = _selected.first;
    });
    _save();
  }

  void _insert(String id) {
    if (_selected.length >= kMaxDockTabs) return;
    HapticFeedback.selectionClick();
    setState(() => _selected.add(id));
    _save();
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    // jedHome (index 0) can't move and nothing can go before it.
    if (oldIndex == 0 || newIndex == 0) return;
    setState(() {
      final id = _selected.removeAt(oldIndex);
      _selected.insert(newIndex, id);
    });
    _save();
  }

  void _makeDefault(String id) {
    if (_default == id) return;
    HapticFeedback.selectionClick();
    setState(() => _default = id);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final tint = CupertinoDynamicColor.resolve(AppSettings.instance.accent, context);
    final cardColor = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final available = _available;

    return SettingsPage(
      title: 'Customize Tab Bar',
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        onPressed: () => setState(() => _editing = !_editing),
        child: Text(
          _editing ? 'Done' : 'Edit',
          style: TextStyle(fontWeight: _editing ? FontWeight.w600 : FontWeight.w400),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: SettingsSectionHeader(
              'Selected Tabs (${_selected.length}/$kMaxDockTabs)',
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverReorderableList(
            itemCount: _selected.length,
            onReorder: _reorder,
            itemBuilder: (context, index) {
              final id = _selected[index];
              final m = tabModuleById(id)!;
              final isHome = id == kHomeModuleId;
              final first = index == 0;
              final last = index == _selected.length - 1;

              Widget row = Container(
                key: ValueKey('sel_$id'),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(first ? 20 : 0),
                    bottom: Radius.circular(last ? 20 : 0),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SettingsPressRow(
                      onTap: () => _makeDefault(id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            if (_editing && !isHome) ...[
                              GestureDetector(
                                onTap: () => _remove(id),
                                child: const Icon(
                                  CupertinoIcons.minus_circle_fill,
                                  color: CupertinoColors.systemRed,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Icon(
                              m.icon,
                              size: 22,
                              color: CupertinoDynamicColor.resolve(m.color, context),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                m.title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _editing && isHome
                                      ? CupertinoColors.secondaryLabel.resolveFrom(context)
                                      : CupertinoColors.label.resolveFrom(context),
                                ),
                              ),
                            ),
                            if (id == _default)
                              Icon(CupertinoIcons.checkmark_alt, size: 20, color: tint),
                            if (_editing && !isHome) ...[
                              const SizedBox(width: 12),
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  CupertinoIcons.line_horizontal_3,
                                  size: 20,
                                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (!last) const SettingsDivider(indent: 52),
                  ],
                ),
              );
              return row;
            },
          ),
        ),
        if (_editing && available.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 32),
              child: SettingsSectionHeader('Available Tools'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(
              child: SettingsCard(
                child: Column(
                  children: [
                    for (var i = 0; i < available.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              available[i].icon,
                              size: 22,
                              color: CupertinoDynamicColor.resolve(available[i].color, context),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                available[i].title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: CupertinoColors.label.resolveFrom(context),
                                ),
                              ),
                            ),
                            if (_selected.length < kMaxDockTabs)
                              GestureDetector(
                                onTap: () => _insert(available[i].id),
                                child: const Icon(
                                  CupertinoIcons.plus_circle_fill,
                                  color: CupertinoColors.systemGreen,
                                  size: 24,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (i != available.length - 1) const SettingsDivider(indent: 52),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(
          child: SettingsFootnote(
            'You can add up to $kMaxDockTabs tabs to the tab bar. '
            'The checked tab will be the default when the app opens.',
          ),
        ),
      ],
    );
  }
}
