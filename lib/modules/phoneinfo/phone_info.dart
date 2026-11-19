/// Shared result states from the jedToolKit brief.
enum DataStatus {
  available,
  restricted,
  unsupported,
  permissionRequired,
  notTested,
  error,
}

extension DataStatusLabel on DataStatus {
  String get label => switch (this) {
        DataStatus.available => 'Available',
        DataStatus.restricted => 'Restricted',
        DataStatus.unsupported => 'Unavailable on this device/API',
        DataStatus.permissionRequired => 'Permission required',
        DataStatus.notTested => 'Not tested',
        DataStatus.error => 'Error',
      };
}

/// Categories shown in the filter bar, in display order.
enum InfoCategory {
  overview,
  processor,
  memoryStorage,
  displayGraphics,
  battery,
  hardware,
}

extension InfoCategoryLabel on InfoCategory {
  String get title => switch (this) {
        InfoCategory.overview => 'Overview',
        InfoCategory.processor => 'Processor',
        InfoCategory.memoryStorage => 'Memory & Storage',
        InfoCategory.displayGraphics => 'Display & Graphics',
        InfoCategory.battery => 'Battery',
        InfoCategory.hardware => 'Hardware',
      };
}

/// Maps a section title from the Java collector to a display category.
InfoCategory categoryForSection(String title) => switch (title) {
      'Device' || 'Android' => InfoCategory.overview,
      'System on Chip' || 'CPU' => InfoCategory.processor,
      'Memory' || 'Storage' => InfoCategory.memoryStorage,
      'Display' || 'Graphics' => InfoCategory.displayGraphics,
      'Battery' => InfoCategory.battery,
      _ => InfoCategory.hardware,
    };

class InfoField {
  final String label;
  final String? value;
  final DataStatus status;
  final String? note;

  const InfoField({
    required this.label,
    this.value,
    required this.status,
    this.note,
  });

  String get displayValue =>
      status == DataStatus.available ? (value ?? '—') : status.label;
}

class InfoSection {
  final String title;
  final List<InfoField> fields;

  const InfoSection({required this.title, required this.fields});

  InfoCategory get category => categoryForSection(title);
}