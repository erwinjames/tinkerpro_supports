class LicenseKey {
  LicenseKey({
    required this.id,
    required this.licenseKey,
    required this.trial,
    required this.dateExpired,
    required this.isUsed,
    required this.storeName,
    required this.storeAddress,
    required this.storeEmail,
    required this.createdAt,
    this.machineType = '',
  });

  final int id;
  final String licenseKey;

  final int trial;
  final String? dateExpired;

  final bool isUsed;
  final String storeName;
  final String storeAddress;
  final String storeEmail;
  final String createdAt;
  final String machineType;

  bool get isTrial => trial == 1;

  factory LicenseKey.fromJson(Map<String, dynamic> json) => LicenseKey(
    id: _asInt(json['id']),
    licenseKey: (json['license_key'] ?? '').toString(),
    trial: _asInt(json['trial']),
    dateExpired: json['date_expired']?.toString(),
    isUsed: _asInt(json['is_used']) == 1,
    storeName: (json['store_name'] ?? '').toString(),
    storeAddress: (json['store_address'] ?? '').toString(),
    storeEmail: (json['store_email'] ?? '').toString(),
    createdAt: (json['created_at'] ?? '').toString(),
    machineType: _machineType(json['machine_type']),
  );
}

String _machineType(Object? value) {
  final v = (value ?? '').toString().trim().toLowerCase();
  if (v == 'server') return 'Server';
  if (v == 'terminal') return 'Terminal';
  return '';
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
