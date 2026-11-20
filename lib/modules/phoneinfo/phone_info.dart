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
    DataStatus.restricted => 'Hidden by Android',
    DataStatus.unsupported => 'Not available on this phone',
    DataStatus.permissionRequired => 'Needs your permission',
    DataStatus.notTested => 'Not checked yet',
    DataStatus.error => "Couldn't read this",
  };
}

/// Categories shown in the filter bar, in display order.
enum InfoCategory { device, cpu, gpu, system, battery, thermal, sensors }

extension InfoCategoryLabel on InfoCategory {
  String get title => switch (this) {
    InfoCategory.device => 'Device',
    InfoCategory.cpu => 'CPU',
    InfoCategory.gpu => 'GPU',
    InfoCategory.system => 'System',
    InfoCategory.battery => 'Battery',
    InfoCategory.thermal => 'Thermal',
    InfoCategory.sensors => 'Sensors',
  };
}

/// Maps a section title from the Java collector to a display category.
InfoCategory categoryForSection(String title) => switch (title) {
  'Device' => InfoCategory.device,
  'CPU' => InfoCategory.cpu,
  'GPU' => InfoCategory.gpu,
  'Battery' => InfoCategory.battery,
  'Thermal' => InfoCategory.thermal,
  'Sensors' => InfoCategory.sensors,
  _ => InfoCategory.system,
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
