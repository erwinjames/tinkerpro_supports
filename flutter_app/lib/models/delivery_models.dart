const List<String> kDeliveryStatuses = <String>[
  'Ready for Delivery',
  'Out for Delivery',
  'Delivered',
  'Cancelled',
];

const List<String> kDeliverySettableStatuses = <String>[
  'Out for Delivery',
  'Delivered',
  'Cancelled',
];

const Map<String, String> kDeliveryDocuments = <String, String>{
  'invoice-pdf': 'Invoice',
  'delivery-note-pdf': 'Delivery Note',
  'packing-slip-pdf': 'Packing Slip',
  'waybill-pdf': 'Waybill',
  'acknowledgement-receipt-pdf': 'Acknowledgement Receipt',
  'return-refund-policy-pdf': 'Return & Refund Policy',
};

int deliveryStatusRank(String status) {
  final i = kDeliveryStatuses.indexOf(status);
  return i == -1 ? 99 : i;
}

class DeliveryBrief {
  const DeliveryBrief({
    required this.id,
    required this.clientName,
    required this.date,
    required this.deliveryNo,
    required this.invoiceNo,
    required this.items,
    required this.deliveryDate,
    required this.branch,
    required this.internalNote,
    required this.status,
  });

  final String id;
  final String clientName;
  final String date;
  final String deliveryNo;
  final String invoiceNo;
  final String items;
  final String deliveryDate;
  final String branch;
  final String internalNote;
  final String status;

  factory DeliveryBrief.fromJson(Map<String, dynamic> json) => DeliveryBrief(
    id: _str(json['id']),
    clientName: _str(json['client_name']),
    date: _str(json['date']),
    deliveryNo: _str(json['delivery_no']),
    invoiceNo: _str(json['invoice_no']),
    items: _str(json['items']),
    deliveryDate: _str(json['delivery_date']),
    branch: _str(json['branch']),
    internalNote: _str(json['internal_note']),
    status: _str(json['status']),
  );

  bool matches(String term) {
    if (term.isEmpty) return true;
    final t = term.toLowerCase();
    for (final field in <String>[
      clientName,
      deliveryNo,
      invoiceNo,
      branch,
      internalNote,
      status,
      date,
      deliveryDate,
    ]) {
      if (field.toLowerCase().contains(t)) return true;
    }
    return false;
  }
}

class DeliveryItem {
  const DeliveryItem({
    required this.description,
    required this.quantity,
    required this.deliveredQuantity,
    required this.unitPrice,
    required this.amount,
  });

  final String description;
  final String quantity;
  final String deliveredQuantity;
  final String unitPrice;
  final String amount;

  factory DeliveryItem.fromJson(Map<String, dynamic> json) => DeliveryItem(
    description: _str(json['description']),
    quantity: _str(json['quantity']),
    deliveredQuantity: _str(json['delivered_quantity']),
    unitPrice: _str(json['unit_price']),
    amount: _str(json['amount']),
  );
}

class DeliveryDetail {
  const DeliveryDetail({
    required this.id,
    required this.clientName,
    required this.date,
    required this.deliveryNo,
    required this.invoiceNo,
    required this.deliveryDate,
    required this.branch,
    required this.internalNote,
    required this.status,
    required this.recipientName,
    required this.recipientPhone,
    required this.recipientAddress,
    required this.notes,
    required this.deliveredAt,
    required this.phone,
    required this.smsEnabled,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.items,
    required this.total,
    required this.currency,
  });

  final String id;
  final String clientName;
  final String date;
  final String deliveryNo;
  final String invoiceNo;
  final String deliveryDate;
  final String branch;
  final String internalNote;
  final String status;
  final String recipientName;
  final String recipientPhone;
  final String recipientAddress;
  final String notes;
  final String deliveredAt;
  final String phone;
  final bool smsEnabled;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final List<DeliveryItem> items;
  final String total;
  final String currency;

  factory DeliveryDetail.fromJson(Map<String, dynamic> json) {
    final rawCustomer = json['customer'];
    final customer = rawCustomer is Map
        ? Map<String, dynamic>.from(rawCustomer)
        : <String, dynamic>{};
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((e) => DeliveryItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <DeliveryItem>[];
    String customerName = _str(customer['company_name']);
    if (customerName.isEmpty) customerName = _str(customer['display_name']);
    if (customerName.isEmpty) customerName = _str(customer['name']);
    if (customerName.isEmpty) customerName = _str(json['client_name']);
    return DeliveryDetail(
      id: _str(json['id']),
      clientName: _str(json['client_name']),
      date: _str(json['date']),
      deliveryNo: _str(json['delivery_no']),
      invoiceNo: _str(json['invoice_no']),
      deliveryDate: _str(json['delivery_date']),
      branch: _str(json['branch']),
      internalNote: _str(json['internal_note']),
      status: _str(json['status']),
      recipientName: _str(json['recipient_name']),
      recipientPhone: _str(json['recipient_phone']),
      recipientAddress: _str(json['recipient_address']),
      notes: _str(json['notes']),
      deliveredAt: _str(json['delivered_at']),
      phone: _str(json['phone']),
      smsEnabled: json['sms_enabled'] == true || json['sms_enabled'] == 1,
      customerName: customerName,
      customerEmail: _str(customer['email']),
      customerPhone: _str(customer['phone']),
      items: items,
      total: _str(json['total']),
      currency: _str(json['currency']),
    );
  }

  String get recipientLabel {
    if (recipientName.trim().isNotEmpty) return recipientName.trim();
    if (clientName.trim().isNotEmpty) return clientName.trim();
    return 'the customer';
  }

  String get companyLabel =>
      customerName.trim().isEmpty ? recipientLabel : customerName.trim();

  String get smsPhone {
    if (phone.trim().isNotEmpty) return phone.trim();
    if (recipientPhone.trim().isNotEmpty) return recipientPhone.trim();
    return customerPhone.trim();
  }

  bool get hasSms => smsEnabled && smsPhone.isNotEmpty;

  DeliveryDetail copyWithStatus(String next) => DeliveryDetail(
    id: id,
    clientName: clientName,
    date: date,
    deliveryNo: deliveryNo,
    invoiceNo: invoiceNo,
    deliveryDate: deliveryDate,
    branch: branch,
    internalNote: internalNote,
    status: next,
    recipientName: recipientName,
    recipientPhone: recipientPhone,
    recipientAddress: recipientAddress,
    notes: notes,
    deliveredAt: deliveredAt,
    phone: phone,
    smsEnabled: smsEnabled,
    customerName: customerName,
    customerEmail: customerEmail,
    customerPhone: customerPhone,
    items: items,
    total: total,
    currency: currency,
  );
}

class DeliveryListResult {
  const DeliveryListResult({
    required this.rows,
    this.stale = false,
    this.cached = false,
    this.message = '',
  });

  final List<DeliveryBrief> rows;
  final bool stale;
  final bool cached;
  final String message;

  int get readyCount =>
      rows.where((r) => r.status == 'Ready for Delivery').length;
}

class DeliveryDetailResult {
  const DeliveryDetailResult({
    required this.detail,
    this.stale = false,
    this.message = '',
  });

  final DeliveryDetail detail;
  final bool stale;
  final String message;
}

class DeliveryStatusResult {
  const DeliveryStatusResult({
    required this.ok,
    required this.message,
    this.emailSent = false,
    this.emailMessage = '',
    this.smsSent = false,
    this.smsMessage = '',
  });

  final bool ok;
  final String message;
  final bool emailSent;
  final String emailMessage;
  final bool smsSent;
  final String smsMessage;
}

String _str(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return value.toString().trim();
}
