/// Models that mirror the JSON the PHP `/api.php` portal endpoints emit.
/// Field names match the wire format so [fromJson] is straight transcription
/// — kept that way to spot server changes quickly during iteration.

class Branch {
  Branch({
    required this.branchCode,
    required this.address,
    required this.city,
  });

  /// Server may return either `effective_branch_code` or `branch_code`
  /// depending on flow; we collapse to one canonical field.
  final String branchCode;
  final String address;
  final String city;

  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
        branchCode: (j['effective_branch_code'] ?? j['branch_code'] ?? '000')
            .toString(),
        address: (j['address'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
      );

  String get displayLocation {
    final parts = [address, city].where((s) => s.isNotEmpty).toList();
    return parts.join(', ');
  }
}

class Customer {
  Customer({
    required this.id,
    required this.companyName,
    required this.tin,
    required this.address,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.email,
    required this.cStatus,
    required this.step2,
    required this.finalStep,
    required this.pdfFile,
    required this.ptuFile,
    required this.actionNotesRaw,
    required this.serialNumber,
    required this.hasFeedback,
  });

  final int id;
  final String companyName;
  final String tin;
  final String address;
  final String firstName;
  final String middleName;
  final String lastName;
  final String email;
  final int cStatus;
  final int step2;
  final int finalStep;
  final String pdfFile;
  final String ptuFile;
  final String actionNotesRaw;
  final String serialNumber;
  final bool hasFeedback;

  String get ownerName {
    final parts = [firstName, middleName, lastName]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.join(' ');
  }

  /// Mirrors the web portal's PROCESSED / SUBMITTED / IN PROGRESS labels.
  String get statusLabel {
    if (finalStep == 1) return 'COMPLETED';
    if (cStatus == 1) return 'PROCESSED';
    if (step2 == 1) return 'IN REVIEW';
    return 'SUBMITTED';
  }

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: int.tryParse((j['id'] ?? 0).toString()) ?? 0,
        companyName: (j['company_name'] ?? '').toString(),
        tin: (j['tin'] ?? '').toString(),
        address: (j['address'] ?? '').toString(),
        firstName: (j['first_name'] ?? '').toString(),
        middleName: (j['middle_name'] ?? '').toString(),
        lastName: (j['last_name'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        cStatus: int.tryParse((j['c_status'] ?? 0).toString()) ?? 0,
        step2: int.tryParse((j['step2'] ?? 0).toString()) ?? 0,
        finalStep: int.tryParse((j['final_step'] ?? 0).toString()) ?? 0,
        pdfFile: (j['pdf_file'] ?? '').toString(),
        ptuFile: (j['ptu_file'] ?? '').toString(),
        actionNotesRaw: (j['action_notes'] ?? '').toString(),
        serialNumber: (j['serial_number'] ?? '').toString(),
        hasFeedback: j['has_feedback'] == true || j['has_feedback'] == 1,
      );
}

/// One row of the per-customer action-note timeline maintained by admins
/// on the staff side. Schema is loose because the server stores it as a
/// JSON blob in `customer.action_notes`.
class ActionNote {
  ActionNote({
    required this.note,
    required this.createdAt,
    required this.author,
  });

  final String note;
  final String createdAt;
  final String author;

  factory ActionNote.fromJson(Map<String, dynamic> j) => ActionNote(
        note: (j['note'] ?? j['message'] ?? '').toString(),
        createdAt: (j['created_at'] ?? j['date'] ?? '').toString(),
        author: (j['author'] ?? j['by'] ?? 'Support').toString(),
      );
}
