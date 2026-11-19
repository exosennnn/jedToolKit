import 'package:flutter/cupertino.dart';
import '../../modules/phoneinfo/phone_info.dart';
import 'jedui_theme.dart';

/// iOS-style inset grouped section.
class JedSection extends StatelessWidget {
  final InfoSection section;

  const JedSection({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: Text(section.title),
      children: [
        for (final field in section.fields) JedInfoRow(field: field),
      ],
    );
  }
}

/// One label/value row. Long values wrap onto extra lines instead of
/// overflowing the screen width.
class JedInfoRow extends StatelessWidget {
  final InfoField field;

  const JedInfoRow({super.key, required this.field});

  @override
  Widget build(BuildContext context) {
    final available = field.status == DataStatus.available;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.label,
                  style: TextStyle(
                    fontSize: 17,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                if (field.note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      field.note!,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              field.displayValue,
              textAlign: TextAlign.end,
              softWrap: true,
              style: TextStyle(
                fontSize: 17,
                color: available
                    ? CupertinoColors.secondaryLabel.resolveFrom(context)
                    : JedTheme.statusColor(context, field.status),
              ),
            ),
          ),
        ],
      ),
    );
  }
}