import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';

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

class ClientInvoiceItem {
  ClientInvoiceItem({
    this.itemName = '',
    this.component = '',
    this.optionValue = '',
    this.brandName = '',
    this.serialNumber = '',
  });

  final String itemName;
  final String component;
  final String optionValue;
  final String brandName;
  final String serialNumber;

  factory ClientInvoiceItem.fromJson(Map<String, dynamic> json) =>
      ClientInvoiceItem(
        itemName: (json['item_name'] ?? '').toString(),
        component:
            (json['component_name'] ?? json['component'] ?? '').toString(),
        optionValue: (json['option_value'] ?? '').toString(),
        brandName: (json['brand_name'] ?? '').toString(),
        serialNumber: (json['serial_number'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        'component': component,
        'option_value': optionValue,
        'brand_name': brandName,
        'serial_number': serialNumber,
      };

  bool get isEmpty =>
      optionValue.trim().isEmpty &&
      brandName.trim().isEmpty &&
      serialNumber.trim().isEmpty;
}

class ClientSpecReplacement {
  ClientSpecReplacement({
    required this.id,
    required this.rowKey,
    required this.oldComponent,
    required this.oldSerial,
    required this.newComponent,
    required this.newSerial,
    required this.remarks,
    required this.replacedByName,
    required this.replacedAt,
  });

  final int id;
  final String rowKey;
  final String oldComponent;
  final String oldSerial;
  final String newComponent;
  final String newSerial;
  final String remarks;
  final String replacedByName;
  final String replacedAt;

  factory ClientSpecReplacement.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString();
    final when =
        s('replaced_at').trim().isNotEmpty ? s('replaced_at') : s('created_at');
    return ClientSpecReplacement(
      id: _asInt(json['id']),
      rowKey: s('row_key'),
      oldComponent: s('old_component'),
      oldSerial: s('old_serial'),
      newComponent: s('new_component'),
      newSerial: s('new_serial'),
      remarks: s('remarks'),
      replacedByName: s('replaced_by_name'),
      replacedAt: when,
    );
  }
}

class ClientInvoiceCheck {
  const ClientInvoiceCheck({
    required this.exists,
    required this.branch,
    required this.branchMatched,
    required this.clientName,
  });

  final bool exists;
  final String branch;
  final bool branchMatched;
  final String clientName;

  static const ClientInvoiceCheck free = ClientInvoiceCheck(
    exists: false,
    branch: '',
    branchMatched: true,
    clientName: '',
  );
}

class ClientBrief {
  ClientBrief({
    required this.id,
    required this.name,
    required this.invoiceNumber,
    this.branch = '',
    this.birImported = false,
  });

  final int id;
  final String name;
  final String invoiceNumber;
  final String branch;
  final bool birImported;

  factory ClientBrief.fromJson(Map<String, dynamic> json) => ClientBrief(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        invoiceNumber: (json['invoice_number'] ?? '').toString(),
        branch: (json['branch'] ?? '').toString(),
        birImported: json['bir_imported'] == true ||
            json['bir_imported'] == 1 ||
            json['bir_imported'] == '1',
      );

  ClientBrief copyWith({bool? birImported}) => ClientBrief(
        id: id,
        name: name,
        invoiceNumber: invoiceNumber,
        branch: branch,
        birImported: birImported ?? this.birImported,
      );
}

class ClientDetail {
  ClientDetail({
    required this.id,
    required this.name,
    required this.invoiceNumber,
    required this.branch,
    required this.datePrepared,
    required this.systemUnit,
    required this.systemUnitSerial,
    required this.ramConfig,
    required this.motherboardSerial,
    required this.storageConfig,
    required this.storageSerial,
    required this.monitorSize,
    required this.monitorBrand,
    required this.monitorType,
    required this.monitorSerial,
    required this.keyboardSerial,
    required this.mouseSerial,
    required this.barcodeScannerSerial,
    required this.thermalPrinterSerial,
    required this.cashDrawerSerial,
    required this.barcodePrinterSerial,
    required this.cusDisplaySerial,
    required this.systemSerial,
    required this.macAddress,
    required this.min,
    required this.ptu,
    required this.dateApproved,
    required this.tin,
    required this.registeredAddress,
    required this.isVat,
    required this.invoiceItems,
    required this.specReplacements,
  });

  final int id;
  final String name;
  final String invoiceNumber;
  final String branch;
  final String datePrepared;
  final String systemUnit;
  final String systemUnitSerial;
  final String ramConfig;
  final String motherboardSerial;
  final String storageConfig;
  final String storageSerial;
  final String monitorSize;
  final String monitorBrand;
  final String monitorType;
  final String monitorSerial;
  final String keyboardSerial;
  final String mouseSerial;
  final String barcodeScannerSerial;
  final String thermalPrinterSerial;
  final String cashDrawerSerial;
  final String barcodePrinterSerial;
  final String cusDisplaySerial;
  final String systemSerial;
  final String macAddress;
  final String min;
  final String ptu;
  final String dateApproved;
  final String tin;
  final String registeredAddress;
  final bool isVat;
  final List<ClientInvoiceItem> invoiceItems;
  final List<ClientSpecReplacement> specReplacements;

  factory ClientDetail.fromJson(Map<String, dynamic> json) {
    final rawItems = json['invoice_items'];
    final items = (rawItems is List)
        ? rawItems
            .whereType<Map>()
            .map((e) => ClientInvoiceItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ClientInvoiceItem>[];
    final rawRepl = json['spec_replacements'];
    final replacements = (rawRepl is List)
        ? rawRepl
            .whereType<Map>()
            .map((e) =>
                ClientSpecReplacement.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ClientSpecReplacement>[];
    String s(String key) => (json[key] ?? '').toString();
    return ClientDetail(
      id: _asInt(json['id']),
      name: s('name'),
      invoiceNumber: s('invoice_number'),
      branch: s('branch'),
      datePrepared: _cleanDate(json['date_prepared']),
      systemUnit: s('system_unit'),
      systemUnitSerial: s('system_unit_serialnum'),
      ramConfig: s('ram_config'),
      motherboardSerial: s('motherboard_serialnum'),
      storageConfig: s('storage_config'),
      storageSerial: s('storage_serialnum'),
      monitorSize: s('monitorsize_config'),
      monitorBrand: s('monitorbrand_config'),
      monitorType: s('monitorType_config'),
      monitorSerial: s('monitor_serialnum'),
      keyboardSerial: s('keyboard_serialnum'),
      mouseSerial: s('mouse_serialnum'),
      barcodeScannerSerial: s('barcodeScanner_serialnum'),
      thermalPrinterSerial: s('thermalPrinter_serialnum'),
      cashDrawerSerial: s('cashDrawer_serialnum'),
      barcodePrinterSerial: s('barcodePrinter_serialnum'),
      cusDisplaySerial: s('cusdisplay_serialnum'),
      systemSerial: s('system_serialnum'),
      macAddress: s('mac_address'),
      min: s('min'),
      ptu: s('ptu'),
      dateApproved: _cleanDate(json['date_approved']),
      tin: s('tin'),
      registeredAddress: s('registered_address'),
      isVat: _asInt(json['is_vat']) == 1,
      invoiceItems: items,
      specReplacements: replacements,
    );
  }
}

class ClientPrefillEntry {
  const ClientPrefillEntry({
    required this.raw,
    required this.option,
    required this.size,
    required this.brand,
    required this.serial,
    required this.target,
  });

  final String raw;
  final String option;
  final String size;
  final String brand;
  final String serial;
  final String target;

  factory ClientPrefillEntry.fromJson(Map<String, dynamic> json) =>
      ClientPrefillEntry(
        raw: _str(json['raw']),
        option: _str(json['option']),
        size: _str(json['size']),
        brand: _str(json['brand']),
        serial: _str(json['serial']),
        target: _str(json['target']),
      );
}

class ClientPrefillRow {
  const ClientPrefillRow({
    required this.itemName,
    required this.component,
    required this.raw,
    required this.icon,
    required this.optionsKey,
    required this.freeSpec,
    required this.entries,
  });

  final String itemName;
  final String component;
  final String raw;
  final String icon;
  final String optionsKey;
  final bool freeSpec;
  final List<ClientPrefillEntry> entries;
}

class ClientInvoicePrefill {
  const ClientInvoicePrefill({
    required this.fields,
    required this.rows,
    required this.components,
  });

  final Map<String, String> fields;
  final List<ClientPrefillRow> rows;
  final List<String> components;

  String field(String key) => fields[key] ?? '';

  factory ClientInvoicePrefill.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final fields = <String, String>{
      if (rawFields is Map)
        for (final e in rawFields.entries) e.key.toString(): _str(e.value),
    };
    final rows = <ClientPrefillRow>[];
    final groups = json['groups'];
    if (groups is List) {
      for (final g in groups.whereType<Map>()) {
        final name = _str(g['name']);
        final list = g['rows'];
        if (list is! List) continue;
        for (final r in list.whereType<Map>()) {
          final entries = r['entries'];
          rows.add(ClientPrefillRow(
            itemName: name,
            component: _str(r['component']),
            raw: _str(r['raw']),
            icon: _str(r['icon']),
            optionsKey: _str(r['optionsKey']),
            freeSpec: r['freeSpec'] == true,
            entries: entries is List
                ? entries
                    .whereType<Map>()
                    .map((e) => ClientPrefillEntry.fromJson(
                        Map<String, dynamic>.from(e)))
                    .toList()
                : const <ClientPrefillEntry>[],
          ));
        }
      }
    }
    final comps = json['components'];
    return ClientInvoicePrefill(
      fields: fields,
      rows: rows,
      components: comps is List
          ? comps.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const <String>[],
    );
  }
}

class ClientSaveResult {
  ClientSaveResult({
    required this.ok,
    required this.message,
    this.clientId,
    this.transport = false,
  });
  final bool ok;
  final String message;
  final int? clientId;
  final bool transport;
}

class ClientCustomerMatch {
  const ClientCustomerMatch({
    required this.ownerName,
    required this.companyName,
    required this.address,
    required this.serialNumber,
    required this.min,
    required this.tin,
    required this.ptu,
  });

  final String ownerName;
  final String companyName;
  final String address;
  final String serialNumber;
  final String min;
  final String tin;
  final String ptu;

  factory ClientCustomerMatch.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString().trim();
    final owner = <String>[s('first_name'), s('middle_name'), s('last_name')]
        .where((p) => p.isNotEmpty)
        .join(' ');
    return ClientCustomerMatch(
      ownerName: owner,
      companyName: s('company_name'),
      address: s('address'),
      serialNumber: s('serial_number'),
      min: s('min'),
      tin: s('tin'),
      ptu: s('ptu'),
    );
  }
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

  DeliveryBrief withStatus(String next) => DeliveryBrief(
        id: id,
        clientName: clientName,
        date: date,
        deliveryNo: deliveryNo,
        invoiceNo: invoiceNo,
        items: items,
        deliveryDate: deliveryDate,
        branch: branch,
        internalNote: internalNote,
        status: next,
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

class DeliveryException implements Exception {
  DeliveryException(
    this.message, {
    this.retryAfter = 0,
    this.retryable = true,
    this.rateLimited = false,
  });

  final String message;
  final int retryAfter;
  final bool retryable;
  final bool rateLimited;

  @override
  String toString() => message;
}

class ClientService {
  ClientService(this.api);
  final ApiClient api;

  static const Duration _deliveryMinAge = Duration(seconds: 45);

  DeliveryListResult? _deliveryCache;
  DateTime? _deliveryCacheAt;
  Future<DeliveryListResult>? _deliveryInflight;

  Future<({List<ClientBrief> rows, int total})> list({
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    final res = await api.get('getClient', {
      'page': '$page',
      'limit': '$limit',
      if (search != null && search.isNotEmpty) 'search': search,
    });
    final raw = res['data'];
    final total = _asInt(res['totalRecords']);
    if (raw is List) {
      final rows = raw
          .whereType<Map>()
          .map((e) => ClientBrief.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return (rows: rows, total: total == 0 ? rows.length : total);
    }
    return (rows: const <ClientBrief>[], total: 0);
  }

  Future<({bool ok, String? message, int customerId})> importToBir(
    int id,
  ) async {
    try {
      final res =
          await api.post('importClientToBir', body: {'id': id.toString()});
      final ok = res['status'] == 'success';
      final raw = res['customer_id'];
      final customerId = raw is int ? raw : int.tryParse('${raw ?? ''}') ?? 0;
      return (
        ok: ok,
        message: res['message']?.toString(),
        customerId: customerId,
      );
    } catch (_) {
      return (
        ok: false,
        message: 'Could not import client to BIR Registration.',
        customerId: 0,
      );
    }
  }

  Future<ClientDetail?> detail(int id) async {
    try {
      final res = await api.get('getClientbyID', {'id': id.toString()});
      if (res['id'] != null) return ClientDetail.fromJson(res);
      final data = res['data'];
      if (data is Map) {
        return ClientDetail.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {}
    return null;
  }

  Future<({ClientDetail? detail, bool missing})> lookup(int id) async {
    try {
      final res = await api.get('getClientbyID', {'id': id.toString()});
      if (res['id'] != null) {
        return (detail: ClientDetail.fromJson(res), missing: false);
      }
      final data = res['data'];
      if (data is Map) {
        return (
          detail: ClientDetail.fromJson(Map<String, dynamic>.from(data)),
          missing: false,
        );
      }
      if (res.containsKey('data') && (data == false || data == null)) {
        return (detail: null, missing: true);
      }
    } catch (_) {}
    return (detail: null, missing: false);
  }

  Future<ClientInvoicePrefill?> invoicePrefill(
    Map<String, dynamic> invoice,
  ) async {
    try {
      final res = await api.postJson(
        'desktopClientInvoicePrefill',
        body: {'invoice': invoice},
      );
      if (res['status'] != 'success') return null;
      return ClientInvoicePrefill.fromJson(res);
    } catch (_) {
      return null;
    }
  }

  Future<ClientSaveResult> save(Map<String, dynamic> state) async {
    Map<String, String> payload;
    String action;
    try {
      final built =
          await api.postJson('desktopClientFormPayload', body: {'state': state});
      final raw = built['payload'];
      if (built['status'] != 'success' || raw is! Map) {
        return ClientSaveResult(
          ok: false,
          message: (built['message'] ?? 'Could not save. Please try again.')
              .toString(),
        );
      }
      payload = raw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
      action = built['action'] == 'updateClient' ? 'updateClient' : 'addClient';
    } catch (e) {
      return ClientSaveResult(ok: false, message: e.toString(), transport: true);
    }
    return _postClient(action, payload);
  }

  Future<ClientSaveResult> saveSheetSection({
    required int id,
    required String section,
    required Map<String, dynamic> values,
  }) async {
    Map<String, String> payload;
    try {
      final built = await api.postJson('desktopClientSheetPayload', body: {
        'id': id,
        'section': section,
        'values': values,
      });
      final raw = built['payload'];
      if (built['status'] != 'success' || raw is! Map) {
        return ClientSaveResult(
          ok: false,
          message: (built['message'] ?? 'Could not save changes.').toString(),
        );
      }
      payload = raw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
    } catch (_) {
      return ClientSaveResult(ok: false, message: 'Could not save changes.');
    }
    final res = await _postClient('updateClient', payload);
    if (res.ok) return res;
    return ClientSaveResult(
      ok: false,
      message: res.message.trim().isEmpty ? 'Could not save changes.' : res.message,
    );
  }

  Future<ClientSaveResult> _postClient(
    String action,
    Map<String, String> payload,
  ) async {
    try {
      final res = await api.post(action, body: payload);
      final ok = res['status'] == 'success';
      return ClientSaveResult(
        ok: ok,
        message: (res['message'] ?? '').toString(),
        clientId: int.tryParse(payload['clientID'] ?? ''),
      );
    } catch (e) {
      return ClientSaveResult(ok: false, message: e.toString(), transport: true);
    }
  }

  Future<bool> delete(int id) async {
    try {
      await api.post('deleteClient', body: {'id': id.toString()});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<ClientInvoiceCheck> checkInvoice(
    String invoice, {
    String branch = '',
  }) async {
    try {
      final res = await api.get('checkClientInvoice', {
        'invoice': invoice,
        'branch': branch,
      });
      final exists = res['exists'] == true || res['exists'] == 1;
      final matched = res['branch_matched'];
      return ClientInvoiceCheck(
        exists: exists,
        branch: (res['branch'] ?? '').toString(),
        branchMatched: matched == null || matched == true || matched == 1,
        clientName: (res['client_name'] ?? '').toString(),
      );
    } catch (_) {
      return ClientInvoiceCheck.free;
    }
  }

  Future<({bool ok, String message})> addSpecReplacement({
    required int clientId,
    required String src,
    required int index,
    required String serialField,
    required String oldComponent,
    required String newComponent,
    required String newSerial,
  }) async {
    try {
      final res = await api.post('addClientSpecReplacement', body: {
        'clientID': clientId.toString(),
        'src': src,
        'idx': index.toString(),
        'serialField': serialField,
        'oldComponent': oldComponent,
        'newComponent': newComponent,
        'newSerial': newSerial,
      });
      final ok = res['status'] == 'success';
      return (
        ok: ok,
        message: (res['message'] ??
                (ok
                    ? 'Replacement recorded'
                    : 'Could not record the replacement.'))
            .toString(),
      );
    } catch (_) {
      return (ok: false, message: 'Could not record the replacement.');
    }
  }

  Future<List<Map<String, dynamic>>> parseInvoiceSpecs(
    List<String> components,
  ) async {
    if (components.isEmpty) return const [];
    try {
      final res = await api.postJson(
        'parseInvoiceSpecs',
        body: {'components': components},
      );
      if (res['status'] != 'success') return const [];
      final data = res['data'];
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<({List<Map<String, dynamic>> rows, String error})> searchInvoice(
    String term,
  ) async {
    final q = term.trim();
    if (q.isEmpty) return (rows: const <Map<String, dynamic>>[], error: '');
    try {
      final res = await api.get('searchInvoiceCustomer', {'q': q});
      final error = res['error'];
      if (error != null) {
        return (rows: const <Map<String, dynamic>>[], error: error.toString());
      }
      if (res['invoice_number'] != null) {
        return (rows: <Map<String, dynamic>>[res], error: '');
      }
      final raw = res['data'] ?? res['results'] ?? res['invoices'];
      if (raw is List) {
        return (
          rows: raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
          error: '',
        );
      }
      return (rows: const <Map<String, dynamic>>[], error: '');
    } catch (_) {
      return (
        rows: const <Map<String, dynamic>>[],
        error: 'Could not reach the invoice service.',
      );
    }
  }

  Future<List<ClientCustomerMatch>> searchCustomers(String term) async {
    final q = term.trim();
    if (q.isEmpty) return const <ClientCustomerMatch>[];
    try {
      final res = await api.get('getcustomer', {
        'search': q,
        'limit': '8',
        'page': '1',
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) =>
                ClientCustomerMatch.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const <ClientCustomerMatch>[];
  }

  Future<DeliveryListResult> deliveries({bool force = false}) {
    final cached = _deliveryCache;
    final at = _deliveryCacheAt;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < _deliveryMinAge) {
      return Future<DeliveryListResult>.value(cached);
    }
    final inflight = _deliveryInflight;
    if (inflight != null) return inflight;
    final request = _fetchDeliveries();
    _deliveryInflight = request;
    return request.whenComplete(() => _deliveryInflight = null);
  }

  Future<DeliveryListResult> _fetchDeliveries() async {
    final res = await api.get('getDeliveries', {'per_page': '100'});
    final error = res['error'];
    if (error != null && res['data'] is! List) {
      throw DeliveryException(
        (res['message'] ?? error).toString(),
        retryAfter: _asInt(res['retry_after']),
      );
    }
    final raw = res['data'];
    final rows = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => DeliveryBrief.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <DeliveryBrief>[];
    rows.sort((a, b) =>
        deliveryStatusRank(a.status).compareTo(deliveryStatusRank(b.status)));
    final result = DeliveryListResult(
      rows: rows,
      stale: res['stale'] == true,
      cached: res['cached'] == true,
      message: (res['message'] ?? '').toString(),
    );
    _deliveryCache = result;
    _deliveryCacheAt = DateTime.now();
    return result;
  }

  Future<DeliveryDetailResult> delivery(String id) async {
    final res = await api.get('getDelivery', {'id': id});
    final data = res['data'];
    if (data is! Map) {
      throw DeliveryException(
        (res['message'] ?? res['error'] ?? 'Failed to load delivery.')
            .toString(),
        retryAfter: _asInt(res['retry_after']),
      );
    }
    return DeliveryDetailResult(
      detail: DeliveryDetail.fromJson(Map<String, dynamic>.from(data)),
      stale: res['stale'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<DeliveryStatusResult> updateDeliveryStatus({
    required String id,
    required String status,
    bool notify = false,
    bool sms = false,
  }) async {
    try {
      final res = await api.post('updateDeliveryStatus', body: {
        'id': id,
        'status': status,
        'notify': notify ? '1' : '0',
        'sms': sms ? '1' : '0',
      });
      final ok = res['success'] == true;
      if (ok) {
        _deliveryCache = null;
        _deliveryCacheAt = null;
      }
      final email = res['email'];
      final smsRes = res['sms'];
      return DeliveryStatusResult(
        ok: ok,
        message: (res['message'] ?? (ok ? 'Status updated.' : '')).toString(),
        emailSent: email is Map && email['success'] == true,
        emailMessage: email is Map ? (email['message'] ?? '').toString() : '',
        smsSent: smsRes is Map && smsRes['success'] == true,
        smsMessage: smsRes is Map ? (smsRes['message'] ?? '').toString() : '',
      );
    } catch (_) {
      return const DeliveryStatusResult(
        ok: false,
        message: 'Failed to update status.',
      );
    }
  }

  Future<Uint8List> fetchDeliveryPdf(String id, String doc) async {
    var tries = 3;
    for (var n = 1;; n++) {
      final uri = Uri.parse(api.actionUrl('getDeliveryPdf', {
        'doc': doc,
        'id': id,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      }));
      try {
        return await _fetchPdf(uri);
      } on DeliveryException catch (e) {
        if (e.rateLimited) {
          tries = 0;
        } else if (!e.retryable) {
          tries = tries < 2 ? tries : 2;
        }
        if (n >= tries) rethrow;
      } catch (_) {
        if (n >= tries) {
          throw DeliveryException('Could not load this document.');
        }
      }
      await Future<void>.delayed(Duration(milliseconds: n * 700));
    }
  }

  Future<String> saveDeliveryPdf(Uint8List bytes, String fileName) async {
    final safe = fileName
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final base = safe.toLowerCase().endsWith('.pdf')
        ? safe.substring(0, safe.length - 4)
        : safe;
    io.Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }
    dir ??= await getApplicationDocumentsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final sep = io.Platform.pathSeparator;
    var file = io.File('${dir.path}$sep$base.pdf');
    for (var i = 1; await file.exists(); i++) {
      file = io.File('${dir.path}$sep$base ($i).pdf');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> downloadClientPdf(int id) async {
    final base = api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/print/client-pdf.php')
        .replace(queryParameters: {'id': id.toString()});
    return _downloadPdf(uri, 'client-data-sheet-$id.pdf');
  }

  Future<String> _downloadPdf(Uri uri, String fileName) async {
    final bytes = await _fetchPdf(uri);
    final dir = await getTemporaryDirectory();
    final file = io.File('${dir.path}${io.Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List> _fetchPdf(Uri uri) async {
    final res = await http.get(uri, headers: api.authHeaders());
    final bytes = res.bodyBytes;
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    final looksPdf = bytes.length > 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        (!looksPdf && !type.contains('pdf'))) {
      final meta = _pdfMeta(res.body);
      throw DeliveryException(
        _pdfError(res.body, res.statusCode),
        retryAfter: _retryAfter(res.body),
        retryable: meta == null
            ? res.statusCode >= 500
            : meta['retryable'] == true,
        rateLimited: res.statusCode == 429 ||
            (meta != null && meta['rate_limited'] == true),
      );
    }
    return bytes;
  }
}

Map<String, dynamic>? _pdfMeta(String body) {
  try {
    final decoded = jsonDecode(body.trim());
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

String _pdfError(String body, int statusCode) {
  final meta = _pdfMeta(body);
  final message = meta?['message'];
  if (message is String && message.trim().isNotEmpty) return message.trim();
  return 'The document service returned HTTP $statusCode.';
}

int _retryAfter(String body) {
  try {
    final decoded = jsonDecode(body.trim());
    if (decoded is Map) return _asInt(decoded['retry_after']);
  } catch (_) {}
  return 0;
}

String _cleanDate(Object? value) {
  final s = (value ?? '').toString().trim();
  if (s.isEmpty || s.startsWith('0000')) return '';
  return s.split(' ').first.split('T').first;
}

String _str(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return value.toString().trim();
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
