// Domain model for the Credentials Storage feature. Mirrors a row from
// `getCredentials` on api.php (data: [...]) — the `client_credentials` table.

class Credential {
  Credential({
    required this.id,
    required this.clientName,
    required this.credentialsText,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String clientName;
  final String credentialsText;
  final String createdAt;
  final String updatedAt;

  factory Credential.fromJson(Map<String, dynamic> json) => Credential(
        id: _asInt(json['id']),
        clientName: (json['client_name'] ?? '').toString(),
        credentialsText: (json['credentials_text'] ?? '').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
        updatedAt: (json['updated_at'] ?? '').toString(),
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
