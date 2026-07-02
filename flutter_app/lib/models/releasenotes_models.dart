// Domain models for the Release Notes feature. Mirrors the
// `getReleaseNotes` row shape on api.php. The SQL aliases the columns as
// NotesID / release_notes / version / posversionID / actionID / action_type,
// so fromJson accepts those keys (with the spec's id/notes/type as fallbacks).

class ReleaseNote {
  ReleaseNote({
    required this.id,
    required this.posversionId,
    required this.actionId,
    required this.notes,
    required this.version,
    required this.type,
  });

  final int id;

  /// FK into `posversion` (the version this note belongs to).
  final int posversionId;

  /// FK into `action` (the action/change type of this note).
  final int actionId;
  final String notes;

  /// Human-readable version string (e.g. "1.4.2").
  final String version;

  /// Human-readable action type (e.g. "Feature", "Bug Fix").
  final String type;

  factory ReleaseNote.fromJson(Map<String, dynamic> json) => ReleaseNote(
        id: _asInt(json['NotesID'] ?? json['id']),
        posversionId: _asInt(json['posversionID']),
        actionId: _asInt(json['actionID']),
        notes: (json['release_notes'] ?? json['notes'] ?? '').toString(),
        version: (json['version'] ?? '').toString(),
        type: (json['action_type'] ?? json['type'] ?? '').toString(),
      );
}

/// A row from `getActionTypes` ({id, type}), used to populate the action
/// type dropdown in the form.
class ActionType {
  ActionType({required this.id, required this.type});

  final int id;
  final String type;

  factory ActionType.fromJson(Map<String, dynamic> json) => ActionType(
        id: _asInt(json['id']),
        type: (json['type'] ?? '').toString(),
      );
}

/// A lightweight reference to a row from `getposversion`, used to populate
/// the version dropdown in the form.
class PosVersionRef {
  PosVersionRef({required this.id, required this.version});

  final int id;
  final String version;

  factory PosVersionRef.fromJson(Map<String, dynamic> json) => PosVersionRef(
        id: _asInt(json['id']),
        version: (json['version'] ?? '').toString(),
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
