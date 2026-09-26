class BarcodeInvoice {
  const BarcodeInvoice({
    required this.invoiceNumber,
    required this.customerName,
    this.batch = 1,
  });

  final String invoiceNumber;
  final String customerName;
  final int batch;
}

class BarcodeRecord {
  const BarcodeRecord({
    required this.id,
    required this.code,
    required this.invoiceNumber,
    required this.customerName,
    required this.batch,
    required this.createdAt,
    required this.scannedBy,
  });

  final int id;
  final String code;
  final String invoiceNumber;
  final String customerName;
  final int batch;
  final String createdAt;
  final String scannedBy;

  factory BarcodeRecord.fromJson(Map<String, dynamic> json) => BarcodeRecord(
    id: barcodeInt(json['id']),
    code: (json['code'] ?? '').toString(),
    invoiceNumber: (json['invoice_number'] ?? '').toString(),
    customerName: (json['customer_name'] ?? '').toString(),
    batch: barcodeInt(json['batch']),
    createdAt: (json['created_at'] ?? '').toString(),
    scannedBy: (json['scanned_by'] ?? '').toString(),
  );
}

class BarcodeBatch {
  const BarcodeBatch({
    required this.batch,
    required this.count,
    required this.lastScan,
  });

  final int batch;
  final int count;
  final String lastScan;

  factory BarcodeBatch.fromJson(Map<String, dynamic> json) => BarcodeBatch(
    batch: barcodeInt(json['batch']),
    count: barcodeInt(json['count']),
    lastScan: (json['last_scan'] ?? '').toString(),
  );
}

class BarcodeList {
  const BarcodeList({
    required this.ok,
    required this.rows,
    required this.batch,
    required this.nextBatch,
    required this.batches,
  });

  final bool ok;
  final List<BarcodeRecord> rows;
  final int batch;
  final int nextBatch;
  final List<BarcodeBatch> batches;

  static const BarcodeList failed = BarcodeList(
    ok: false,
    rows: [],
    batch: 0,
    nextBatch: 0,
    batches: [],
  );
}

enum ScanOutcome { saved, exists, error }

class BarcodeScanResult {
  const BarcodeScanResult({
    required this.outcome,
    required this.code,
    required this.message,
    this.id = 0,
    this.invoiceNumber = '',
    this.customerName = '',
    this.batch = 0,
    this.firstScanned = '',
  });

  final ScanOutcome outcome;
  final String code;
  final String message;
  final int id;
  final String invoiceNumber;
  final String customerName;
  final int batch;
  final String firstScanned;

  factory BarcodeScanResult.fromJson(Map<String, dynamic> json, String sent) {
    final status = (json['status'] ?? '').toString();
    return BarcodeScanResult(
      outcome: status == 'saved'
          ? ScanOutcome.saved
          : status == 'exists'
          ? ScanOutcome.exists
          : ScanOutcome.error,
      code: (json['code'] ?? sent).toString(),
      message: (json['message'] ?? 'Something went wrong.').toString(),
      id: barcodeInt(json['id']),
      invoiceNumber: (json['invoice_number'] ?? '').toString(),
      customerName: (json['customer_name'] ?? '').toString(),
      batch: barcodeInt(json['batch']),
      firstScanned: (json['first_scanned'] ?? '').toString(),
    );
  }
}

class BarcodeActionResult {
  const BarcodeActionResult({
    required this.ok,
    this.message,
    this.batch = 0,
    this.existingInNew = 0,
    this.deleted = 0,
  });

  final bool ok;
  final String? message;
  final int batch;
  final int existingInNew;
  final int deleted;
}

class InvoiceMatch {
  const InvoiceMatch({required this.invoiceNumber, required this.customerName});

  final String invoiceNumber;
  final String customerName;
}

int barcodeInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
