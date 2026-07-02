// Domain model for the Emails (subscribers) feature. Mirrors the `getEmails`
// row shape returned by `api.php`:
//   {id, email, created_at, business_type, source} with
//   {totalRecords, limit, page} envelope.

class EmailEntry {
  EmailEntry({
    required this.id,
    required this.email,
    required this.createdAt,
    required this.businessType,
    required this.source,
  });

  final int id;
  final String email;
  final String createdAt;
  final String businessType;

  /// Origin table: 'emails' (newsletter subscribers) or 'leads'. Required by
  /// the backend on delete (leads are unsubscribed, emails are deleted).
  final String source;

  bool get isLead => source == 'leads';

  factory EmailEntry.fromJson(Map<String, dynamic> json) => EmailEntry(
        id: _asInt(json['id']),
        email: (json['email'] ?? '').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
        businessType: (json['business_type'] ?? '').toString(),
        source: (json['source'] ?? 'emails').toString(),
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
