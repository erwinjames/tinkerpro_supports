int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is bool) return v ? 1 : 0;
  return int.tryParse('${v ?? ''}'.trim()) ?? 0;
}

double _double(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}'.trim()) ?? 0;
}

String _str(dynamic v) => v == null ? '' : v.toString();

bool _flag(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v.toInt() == 1;
  final s = '${v ?? ''}'.trim().toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

const List<String> _kMonthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String vendorMoney(num amount) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final whole = fixed.substring(0, dot);
  final cents = fixed.substring(dot + 1);
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '${negative ? '-' : ''}₱$buffer.$cents';
}

String vendorMoneyCentavos(int centavos) => vendorMoney(centavos / 100);

DateTime? parseVendorDate(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
}

String vendorStamp(String value, [String fallback = '—']) {
  final d = parseVendorDate(value);
  if (d == null) return value.trim().isEmpty ? fallback : value;
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final suffix = d.hour < 12 ? 'AM' : 'PM';
  return '${_kMonthsShort[d.month - 1]} ${d.day}, ${d.year}, '
      '${hour.toString().padLeft(2, '0')}:$minute $suffix';
}

String vendorCleanPrice(String raw) =>
    raw.trim().replaceAll(RegExp(r'[,\s₱]'), '');

String? vendorPriceError(String raw) {
  final clean = vendorCleanPrice(raw);
  if (clean.isEmpty) return 'Enter a price of at least ₱1.00.';
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(clean)) {
    return 'Enter a price of at least ₱1.00.';
  }
  if ((double.tryParse(clean) ?? 0) < 1) {
    return 'Enter a price of at least ₱1.00.';
  }
  return null;
}

const List<int> kVendorInviteHours = [24, 48, 168, 720];

String vendorInviteHoursLabel(int hours) {
  switch (hours) {
    case 24:
      return '24 hours';
    case 48:
      return '48 hours';
    case 168:
      return '7 days';
    case 720:
      return '30 days';
    default:
      return '$hours hours';
  }
}

class VendorRow {
  const VendorRow({
    this.id = 0,
    this.vendorCode = '',
    this.companyName = '',
    this.contactPerson = '',
    this.email = '',
    this.mobile = '',
    this.address = '',
    this.status = 'active',
    this.emailVerified = false,
    this.lastLoginAt = '',
    this.createdAt = '',
    this.licensePriceCentavos = 0,
    this.submissions = 0,
    this.logEntries = 0,
    this.keysPaid = 0,
    this.revenueCentavos = 0,
    this.lastPaidAt = '',
  });

  final int id;
  final String vendorCode;
  final String companyName;
  final String contactPerson;
  final String email;
  final String mobile;
  final String address;
  final String status;
  final bool emailVerified;
  final String lastLoginAt;
  final String createdAt;
  final int licensePriceCentavos;
  final int submissions;
  final int logEntries;
  final int keysPaid;
  final int revenueCentavos;
  final String lastPaidAt;

  bool get suspended => status == 'suspended';

  String get statusLabel => suspended ? 'Suspended' : 'Active';

  String get name => companyName.trim().isEmpty
      ? (vendorCode.trim().isEmpty ? 'Vendor' : vendorCode)
      : companyName;

  String get priceLabel => licensePriceCentavos > 0
      ? vendorMoneyCentavos(licensePriceCentavos)
      : 'default';

  factory VendorRow.fromJson(Map<String, dynamic> json) => VendorRow(
    id: _int(json['id']),
    vendorCode: _str(json['vendor_code']),
    companyName: _str(json['company_name']),
    contactPerson: _str(json['contact_person']),
    email: _str(json['email']),
    mobile: _str(json['mobile']),
    address: _str(json['address']),
    status: _str(json['status']).isEmpty ? 'active' : _str(json['status']),
    emailVerified: _flag(json['email_verified']),
    lastLoginAt: _str(json['last_login_at']),
    createdAt: _str(json['created_at']),
    licensePriceCentavos: _int(json['license_price_centavos']),
    submissions: _int(json['submissions']),
    logEntries: _int(json['log_entries']),
    keysPaid: _int(json['keys_paid']),
    revenueCentavos: _int(json['revenue_centavos']),
    lastPaidAt: _str(json['last_paid_at']),
  );
}

class VendorPage {
  const VendorPage({this.vendors = const [], this.total = 0, this.limit = 25});

  final List<VendorRow> vendors;
  final int total;
  final int limit;
}

class VendorLicenseKey {
  const VendorLicenseKey({
    this.key = '',
    this.isUsed = false,
    this.usedAt = '',
  });

  final String key;
  final bool isUsed;
  final String usedAt;

  factory VendorLicenseKey.fromJson(Map<String, dynamic> json) =>
      VendorLicenseKey(
        key: _str(json['key']),
        isUsed: _flag(json['is_used']),
        usedAt: _str(json['used_at']),
      );
}

class VendorLicenseRequest {
  const VendorLicenseRequest({
    this.id = 0,
    this.businessName = '',
    this.tin = '',
    this.keys = const [],
    this.quantity = 1,
    this.unitAmount = 0,
    this.status = '',
    this.paymentStatus = '',
    this.amount = 0,
    this.paidAt = '',
    this.createdAt = '',
  });

  final int id;
  final String businessName;
  final String tin;
  final List<VendorLicenseKey> keys;
  final int quantity;
  final double unitAmount;
  final String status;
  final String paymentStatus;
  final double amount;
  final String paidAt;
  final String createdAt;

  bool get paid => paymentStatus == 'paid';

  int get pendingKeys {
    final missing = quantity - keys.length;
    return missing < 0 ? 0 : missing;
  }

  factory VendorLicenseRequest.fromJson(Map<String, dynamic> json) {
    final rawKeys = json['license_keys'];
    final keys = <VendorLicenseKey>[];
    if (rawKeys is List) {
      for (final entry in rawKeys) {
        if (entry is Map) {
          keys.add(VendorLicenseKey.fromJson(Map<String, dynamic>.from(entry)));
        } else if (entry != null) {
          keys.add(VendorLicenseKey(key: _str(entry)));
        }
      }
    }
    final qty = _int(json['quantity']);
    return VendorLicenseRequest(
      id: _int(json['id']),
      businessName: _str(json['business_name']),
      tin: _str(json['tin']),
      keys: keys,
      quantity: qty < 1 ? 1 : qty,
      unitAmount: _double(json['unit_amount']),
      status: _str(json['status']),
      paymentStatus: _str(json['payment_status']),
      amount: _double(json['amount']),
      paidAt: _str(json['paid_at']),
      createdAt: _str(json['created_at']),
    );
  }
}

class VendorTotals {
  const VendorTotals({
    this.submissions = 0,
    this.keysPaid = 0,
    this.revenue = 0,
    this.pending = 0,
    this.pendingValue = 0,
  });

  final int submissions;
  final int keysPaid;
  final double revenue;
  final int pending;
  final double pendingValue;

  factory VendorTotals.fromJson(Map<String, dynamic> json) => VendorTotals(
    submissions: _int(json['submissions']),
    keysPaid: _int(json['keys_paid']),
    revenue: _double(json['revenue']),
    pending: _int(json['pending']),
    pendingValue: _double(json['pending_value']),
  );
}

class VendorDetail {
  const VendorDetail({
    required this.vendor,
    this.totals = const VendorTotals(),
    this.requests = const [],
  });

  final VendorRow vendor;
  final VendorTotals totals;
  final List<VendorLicenseRequest> requests;

  factory VendorDetail.fromJson(Map<String, dynamic> json) {
    final rawVendor = json['vendor'];
    final rawTotals = json['totals'];
    final rawRequests = json['requests'];
    return VendorDetail(
      vendor: rawVendor is Map
          ? VendorRow.fromJson(Map<String, dynamic>.from(rawVendor))
          : const VendorRow(),
      totals: rawTotals is Map
          ? VendorTotals.fromJson(Map<String, dynamic>.from(rawTotals))
          : const VendorTotals(),
      requests: rawRequests is List
          ? rawRequests
                .whereType<Map>()
                .map(
                  (e) => VendorLicenseRequest.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class VendorLogEntry {
  const VendorLogEntry({
    this.id = 0,
    this.action = '',
    this.details = '',
    this.ipAddress = '',
    this.userAgent = '',
    this.createdAt = '',
  });

  final int id;
  final String action;
  final String details;
  final String ipAddress;
  final String userAgent;
  final String createdAt;

  String get actionLabel => action.replaceAll('_', ' ');

  factory VendorLogEntry.fromJson(Map<String, dynamic> json) => VendorLogEntry(
    id: _int(json['id']),
    action: _str(json['action']),
    details: _str(json['details']),
    ipAddress: _str(json['ip_address']),
    userAgent: _str(json['user_agent']),
    createdAt: _str(json['created_at']),
  );
}

class VendorLogPage {
  const VendorLogPage({
    this.logs = const [],
    this.total = 0,
    this.limit = 25,
    this.offset = 0,
  });

  final List<VendorLogEntry> logs;
  final int total;
  final int limit;
  final int offset;
}

enum VendorInviteState { used, revoked, active, expired }

class VendorInvite {
  const VendorInvite({
    this.id = 0,
    this.note = '',
    this.licensePriceCentavos = 0,
    this.expiresAt = '',
    this.isUsed = false,
    this.usedAt = '',
    this.createdAt = '',
    this.createdByName = '',
    this.usedByCode = '',
    this.isActive = false,
  });

  final int id;
  final String note;
  final int licensePriceCentavos;
  final String expiresAt;
  final bool isUsed;
  final String usedAt;
  final String createdAt;
  final String createdByName;
  final String usedByCode;
  final bool isActive;

  VendorInviteState get state {
    if (isUsed && usedByCode.trim().isNotEmpty) return VendorInviteState.used;
    if (isUsed) return VendorInviteState.revoked;
    if (isActive) return VendorInviteState.active;
    return VendorInviteState.expired;
  }

  String get stateLabel {
    switch (state) {
      case VendorInviteState.used:
        return 'Used · $usedByCode';
      case VendorInviteState.revoked:
        return 'Revoked';
      case VendorInviteState.active:
        return 'Active';
      case VendorInviteState.expired:
        return 'Expired';
    }
  }

  bool get canRevoke => !isUsed && isActive;

  String get priceLabel => licensePriceCentavos > 0
      ? vendorMoneyCentavos(licensePriceCentavos)
      : '—';

  VendorInvite asRevoked() => VendorInvite(
    id: id,
    note: note,
    licensePriceCentavos: licensePriceCentavos,
    expiresAt: expiresAt,
    isUsed: true,
    usedAt: usedAt,
    createdAt: createdAt,
    createdByName: createdByName,
    usedByCode: '',
    isActive: false,
  );

  factory VendorInvite.fromJson(Map<String, dynamic> json) => VendorInvite(
    id: _int(json['id']),
    note: _str(json['note']),
    licensePriceCentavos: _int(json['license_price_centavos']),
    expiresAt: _str(json['expires_at']),
    isUsed: _flag(json['is_used']),
    usedAt: _str(json['used_at']),
    createdAt: _str(json['created_at']),
    createdByName: _str(json['created_by_name']),
    usedByCode: _str(json['used_by_code']),
    isActive: _flag(json['is_active']),
  );
}

class VendorInvitePage {
  const VendorInvitePage({this.invites = const [], this.total = 0});

  final List<VendorInvite> invites;
  final int total;
}

class VendorInviteLink {
  const VendorInviteLink({
    this.url = '',
    this.expiresInHours = 0,
    this.expiresAt = '',
    this.licensePriceLabel = '',
    this.licensePriceCentavos = 0,
  });

  final String url;
  final int expiresInHours;
  final String expiresAt;
  final String licensePriceLabel;
  final int licensePriceCentavos;

  factory VendorInviteLink.fromJson(Map<String, dynamic> json) =>
      VendorInviteLink(
        url: _str(json['url']),
        expiresInHours: _int(json['expires_in_hours']),
        expiresAt: _str(json['expires_at']),
        licensePriceLabel: _str(json['license_price_label']),
        licensePriceCentavos: _int(json['license_price_centavos']),
      );
}

class VendorActionResult {
  const VendorActionResult({required this.ok, this.message, this.data});

  final bool ok;
  final String? message;
  final Map<String, dynamic>? data;

  factory VendorActionResult.failure(String message) =>
      VendorActionResult(ok: false, message: message);
}

class VendorNewRegistrations {
  const VendorNewRegistrations({this.count = 0, this.ids = const []});

  final int count;
  final List<int> ids;

  factory VendorNewRegistrations.fromJson(Map<String, dynamic> json) {
    final raw = json['ids'];
    return VendorNewRegistrations(
      count: _int(json['count']),
      ids: raw is List ? raw.map(_int).where((e) => e > 0).toList() : const [],
    );
  }
}
