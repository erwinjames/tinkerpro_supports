// Domain models for the "Client & Data Sheet" feature (web `client.php` /
// `ClientFacade`, `client` table). Distinct from the BIR/`customer` feature.

/// One line item in a client's invoice bundle (`client_invoice_items`). The
/// read side (getClientbyID) returns `component_name`; the write side expects
/// `component`.
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
      component.trim().isEmpty &&
      optionValue.trim().isEmpty &&
      brandName.trim().isEmpty &&
      serialNumber.trim().isEmpty;
}

/// Row shape from `getClient` → `data[i]` (list view).
class ClientBrief {
  ClientBrief({required this.id, required this.name, required this.invoiceNumber});

  final int id;
  final String name;
  final String invoiceNumber;

  factory ClientBrief.fromJson(Map<String, dynamic> json) => ClientBrief(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        invoiceNumber: (json['invoice_number'] ?? '').toString(),
      );
}

/// Full `client` row from `getClientbyID` + its `invoice_items`.
class ClientDetail {
  ClientDetail({
    required this.id,
    required this.name,
    required this.invoiceNumber,
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
  });

  final int id;
  final String name;
  final String invoiceNumber;
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

  factory ClientDetail.fromJson(Map<String, dynamic> json) {
    final rawItems = json['invoice_items'];
    final items = (rawItems is List)
        ? rawItems
            .whereType<Map>()
            .map((e) => ClientInvoiceItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ClientInvoiceItem>[];
    String s(String key) => (json[key] ?? '').toString();
    return ClientDetail(
      id: _asInt(json['id']),
      name: s('name'),
      invoiceNumber: s('invoice_number'),
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
    );
  }
}

class ClientSaveResult {
  ClientSaveResult({required this.ok, required this.message, this.clientId});
  final bool ok;
  final String message;
  final int? clientId;
}

String _cleanDate(Object? value) {
  final s = (value ?? '').toString().trim();
  if (s.isEmpty || s.startsWith('0000')) return '';
  return s.split(' ').first.split('T').first;
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
