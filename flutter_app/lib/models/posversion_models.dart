// Domain model for the POS Version feature. Mirrors the `getposversion`
// row shape returned by `api.php` (data: [...], totalRecords: N).

class PosVersion {
  PosVersion({
    required this.id,
    required this.version,
    required this.date,
  });

  final int id;

  /// Semantic version string, e.g. "2.4.1".
  final String version;

  /// Release date in YYYY-MM-DD form.
  final String date;

  factory PosVersion.fromJson(Map<String, dynamic> json) => PosVersion(
        id: _asInt(json['id']),
        version: (json['version'] ?? '').toString(),
        date: (json['date'] ?? '').toString(),
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
