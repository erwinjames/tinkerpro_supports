// Domain model for the License Key feature. Mirrors the `getLicenseKey`
// row shape returned by `api.php` (data: [...], total: N).

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
  });

  final int id;
  final String licenseKey;

  /// 1 = trial (has an expiry), 0 = permanent.
  final int trial;
  final String? dateExpired;

  /// Whether a customer has already activated this key. Used keys can't be
  /// deleted (the backend rejects it).
  final bool isUsed;
  final String storeName;
  final String storeAddress;
  final String storeEmail;
  final String createdAt;

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
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
