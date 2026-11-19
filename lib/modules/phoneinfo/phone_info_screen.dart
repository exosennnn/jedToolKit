import 'package:flutter/cupertino.dart';
import '../../core/jedui/jedui_components.dart';
import 'phone_info.dart';
import 'phone_info_service.dart';

class PhoneInfoScreen extends StatefulWidget {
  const PhoneInfoScreen({super.key});

  @override
  State<PhoneInfoScreen> createState() => _PhoneInfoScreenState();
}

class _PhoneInfoScreenState extends State<PhoneInfoScreen> {
  final _service = PhoneInfoService();
  List<InfoSection>? _sections;
  InfoCategory? _filter; // null means "All"

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sections = await _service.load();
    if (mounted) setState(() => _sections = sections);
  }

  /// Groups sections by category in display order, applying the active filter.
  List<InfoSection> _visible(List<InfoSection> all) => [
        for (final c in InfoCategory.values)
          if (_filter == null || _filter == c)
            for (final s in all)
              if (s.category == c) s,
      ];

  @override
  Widget build(BuildContext context) {
    final all = _sections;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(largeTitle: Text('Phone Info')),
          CupertinoSliverRefreshControl(onRefresh: _load),
          SliverToBoxAdapter(child: _filterBar(context)),
          if (all == null)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else
            SliverList(
              delegate: SliverChildListDelegate([
                for (final s in _visible(all)) JedSection(section: s),
                const SizedBox(height: 24),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _filterBar(BuildContext context) {
    final options = <(String, InfoCategory?)>[
      ('All', null),
      for (final c in InfoCategory.values) (c.title, c),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, category) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(
                context,
                label,
                selected: _filter == category,
                onTap: () => setState(() => _filter = category),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? CupertinoColors.activeBlue
              : CupertinoColors.tertiarySystemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? CupertinoColors.white
                : CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}