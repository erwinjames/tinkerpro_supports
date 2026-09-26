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

class InternalRecipient {
  InternalRecipient({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.email,
    required this.tag,
    required this.status,
    required this.notes,
    required this.source,
  });

  final int id;
  final String name;
  final String subtitle;
  final String email;
  final String tag;
  final String status;
  final String notes;
  final String source;

  bool get isStaff => source == 'staff';
  bool get isContact => source == 'contact';
  String get displayName => name.isEmpty ? email : name;

  factory InternalRecipient.fromJson(Map<String, dynamic> json) =>
      InternalRecipient(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        subtitle: (json['subtitle'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        tag: (json['tag'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
        source: (json['source'] ?? 'contact').toString(),
      );
}

class RecipientTally {
  const RecipientTally({required this.value, required this.total});

  final String value;
  final int total;
}

class InternalFilters {
  const InternalFilters({this.roles = const [], this.labels = const []});

  final List<RecipientTally> roles;
  final List<RecipientTally> labels;

  factory InternalFilters.fromJson(Map<String, dynamic> json) {
    List<RecipientTally> read(Object? raw, String key) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
            (e) => RecipientTally(
              value: (e[key] ?? '').toString(),
              total: _asInt(e['total']),
            ),
          )
          .where((t) => t.value.isNotEmpty)
          .toList();
    }

    return InternalFilters(
      roles: read(json['roles'], 'role'),
      labels: read(json['labels'], 'label'),
    );
  }
}

class InternalRecipientPage {
  const InternalRecipientPage({
    this.rows = const [],
    this.totalRecords = 0,
    this.filters = const InternalFilters(),
    this.contactsError = '',
    this.ok = true,
  });

  final List<InternalRecipient> rows;
  final int totalRecords;
  final InternalFilters filters;
  final String contactsError;
  final bool ok;
}

class RecipientGroup {
  const RecipientGroup({
    required this.id,
    required this.label,
    required this.hint,
    required this.count,
  });

  final String id;
  final String label;
  final String hint;
  final int count;

  factory RecipientGroup.fromJson(Map<String, dynamic> json) => RecipientGroup(
    id: (json['id'] ?? '').toString(),
    label: (json['label'] ?? '').toString(),
    hint: (json['hint'] ?? '').toString(),
    count: _asInt(json['count']),
  );
}

class InternalSuggestions {
  const InternalSuggestions({
    this.groups = const [],
    this.people = const [],
    this.peopleTotal = 0,
  });

  final List<RecipientGroup> groups;
  final List<InternalRecipient> people;
  final int peopleTotal;
}

enum ChipKind { email, group }

class RecipientChip {
  const RecipientChip({
    required this.kind,
    required this.value,
    required this.label,
    this.sub = '',
    this.count,
    this.isNew = false,
    this.invalid = false,
  });

  final ChipKind kind;
  final String value;
  final String label;
  final String sub;
  final int? count;
  final bool isNew;
  final bool invalid;

  bool get isGroup => kind == ChipKind.group;
  String get key => '${kind.name}|${value.toLowerCase()}';
  int get weight => isGroup ? (count ?? 0) : 1;
}

class ContactDraft {
  const ContactDraft({
    this.id = 0,
    this.name = '',
    this.email = '',
    this.company = '',
    this.label = '',
    this.notes = '',
  });

  final int id;
  final String name;
  final String email;
  final String company;
  final String label;
  final String notes;

  bool get isEditing => id > 0;

  factory ContactDraft.fromRecipient(InternalRecipient row) => ContactDraft(
    id: row.id,
    name: row.name,
    email: row.email,
    company: row.subtitle,
    label: row.tag,
    notes: row.notes,
  );
}

class SaveContactResult {
  const SaveContactResult({required this.ok, this.id = 0, this.message});

  final bool ok;
  final int id;
  final String? message;
}

class RememberResult {
  const RememberResult({required this.ok, this.added = const []});

  final bool ok;
  final List<String> added;
}

String prettyRole(String role) =>
    (role.isEmpty ? 'user' : role).replaceAll('_', ' ');
